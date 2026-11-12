#!/usr/bin/env python3
"""Check every list in SaneHosts' blocklist catalog.

For each BlocklistSource in BlocklistCatalog.swift this downloads the list,
counts entries the way the app does, and finds when it last changed. It fails
when a list is unreachable, has not changed in over a year, is larger than the
app accepts, or when its estimatedEntries label is far from the real count.

Usage:
  python3 -I scripts/check_blocklist_catalog.py            # check the catalog
  python3 -I scripts/check_blocklist_catalog.py --json out.json
  python3 -I scripts/check_blocklist_catalog.py --alert ~/SaneApps/outputs/agent-alerts/sanehosts-blocklist-catalog.md
  python3 -I scripts/check_blocklist_catalog.py --catalog other.swift
  python3 -I scripts/check_blocklist_catalog.py --self-test

Exit codes: 0 all lists healthy, or problems found and written to --alert;
1 problems found and no --alert given; 2 the check itself could not run.
The weekly Mini job (com.saneapps.sanehosts-catalog-check) uses --alert so a
stale list becomes an agent alert, not a failed job.
"""

import datetime
import email.utils
import ipaddress
import json
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "SaneHostsPackage/Sources/SaneHostsFeature/Models/BlocklistCatalog.swift"

# Keep in step with the app: RemoteSyncService.maxDownloadBytes / maxEntriesPerList.
MAX_BYTES = 25 * 1024 * 1024
MAX_ENTRIES = 500_000
MAX_AGE_DAYS = 365
ESTIMATE_TOLERANCE = 0.35

RESERVED = {
    "localhost", "localhost.localdomain", "local", "broadcasthost",
    "ip6-localhost", "ip6-loopback", "ip6-localnet", "ip6-mcastprefix",
    "ip6-allnodes", "ip6-allrouters", "ip6-allhosts", "0.0.0.0",
}
LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,62}$")


def valid_host(host):
    return 0 < len(host) <= 253 and all(LABEL.match(p) for p in host.split(".") if p)


def valid_ip(text):
    try:
        ipaddress.ip_address(text)
        return True
    except ValueError:
        return False


def hostnames(text):
    """Mirror of HostsParser.parseBlocklistLine applied to a whole file."""
    found = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#!":
            continue
        parts = line.split("#", 1)[0].split()
        if not parts:
            continue
        if len(parts) == 1:
            host = parts[0]
            if "." in host and valid_host(host) and host.lower() not in RESERVED:
                found.add(host.lower())
        elif valid_ip(parts[0]):
            for host in parts[1:]:
                if valid_host(host) and host.lower() not in RESERVED:
                    found.add(host.lower())
    return found


def parse_catalog(path):
    source = path.read_text()
    entries = []
    for block in re.findall(r"BlocklistSource\((.*?)\n\s*\)", source, re.S):
        item = {}
        for key in ("id", "name", "url", "estimatedEntries", "maintainer"):
            match = re.search(key + r':\s*"([^"]*)"', block)
            item[key] = match.group(1) if match else None
        match = re.search(r"category:\s*\.(\w+)", block)
        item["category"] = match.group(1) if match else None
        entries.append(item)
    return entries


def parse_estimate(label):
    match = re.fullmatch(r"([\d.]+)\s*([KkMm]?)", label or "")
    if not match:
        return None
    value = float(match.group(1))
    return int(value * {"": 1, "k": 1_000, "m": 1_000_000}[match.group(2).lower()])


def gh_binary():
    for candidate in (shutil.which("gh"), "/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    return None


def github_last_change(url):
    match = re.match(r"https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)", url)
    if not match:
        return None
    owner, repo, branch, path = match.groups()
    gh = gh_binary()
    if gh is None:
        return None
    try:
        out = subprocess.run(
            [gh, "api", f"repos/{owner}/{repo}/commits?path={path}&sha={branch}&per_page=1",
             "--jq", ".[0].commit.committer.date"],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return datetime.date.fromisoformat(out[:10]) if out else None


def check(item, today):
    problems = []
    request = urllib.request.Request(item["url"], headers={"User-Agent": "SaneHosts-catalog-check"})
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read(MAX_BYTES + 1)
            last_modified = response.headers.get("Last-Modified")
    except Exception as error:  # noqa: BLE001 - report every failure the same way
        return {**item, "real": 0, "updated": None, "problems": [f"unreachable: {error}"]}

    if len(data) > MAX_BYTES:
        problems.append("larger than the app's 25 MB download limit")
    count = len(hostnames(data.decode("utf-8", "replace")))
    if count == 0:
        problems.append("no entries parsed")
    if count > MAX_ENTRIES:
        problems.append(f"{count} entries is over the app's {MAX_ENTRIES} per-list cap")

    updated = github_last_change(item["url"])
    if updated is None and last_modified:
        try:
            updated = email.utils.parsedate_to_datetime(last_modified).date()
        except (TypeError, ValueError):
            updated = None
    if updated is None:
        problems.append("could not tell when the list last changed")
    elif (today - updated).days > MAX_AGE_DAYS:
        problems.append(f"not updated since {updated}")

    estimate = parse_estimate(item["estimatedEntries"])
    if estimate is None:
        problems.append(f"estimatedEntries '{item['estimatedEntries']}' is not a number like 42K")
    elif count and abs(estimate - count) / count > ESTIMATE_TOLERANCE:
        problems.append(f"estimate {item['estimatedEntries']} but list has {count}")

    return {**item, "real": count, "updated": str(updated) if updated else None, "problems": problems}


def self_test():
    sample = "\n".join([
        "# comment", "! adblock comment", "127.0.0.1 localhost",
        "::1 localhost ip6-localhost ip6-loopback", "0.0.0.0 0.0.0.0",
        "0.0.0.0 ads.example.com # tracking network", "0.0.0.0\ttabbed.example.com",
        "bare.example.com", "# 0.0.0.0 disabled.example.com", "0.0.0.0 bad_host",
    ])
    got = sorted(hostnames(sample))
    want = ["ads.example.com", "bare.example.com", "tabbed.example.com"]
    assert got == want, got
    assert parse_estimate("42K") == 42_000 and parse_estimate("3.5K") == 3_500 and parse_estimate("350") == 350
    items = parse_catalog(CATALOG)
    assert items and all(i["id"] and i["url"] and i["category"] for i in items), "catalog parse failed"
    ids = [i["id"] for i in items]
    assert len(ids) == len(set(ids)), "duplicate ids"
    urls = [i["url"] for i in items]
    assert len(urls) == len(set(urls)), "two entries share one URL"
    print(f"self-test ok ({len(items)} catalog entries parsed)")


def option(argv, name):
    if name in argv and argv.index(name) + 1 < len(argv):
        return argv[argv.index(name) + 1]
    return None


def write_alert(path, results, catalog):
    bad = [r for r in results if r["problems"]]
    stamp = datetime.datetime.now().strftime("%-d %B %Y, %-I:%M %p")
    lines = [
        "# SaneHosts blocklist catalog needs attention",
        "",
        f"- Seen: {stamp}, weekly job `com.saneapps.sanehosts-catalog-check` on the Mini.",
        f"- {len(bad)} of {len(results)} lists in `{catalog}` have problems:",
        "",
    ]
    lines += [f"  - `{r['id']}` ({r['name']}): {'; '.join(r['problems'])}" for r in bad]
    lines += [
        "",
        "- Fix: replace dead or stale lists with maintained ones (hosts format, under 500K entries,",
        "  updated within a year), correct size labels, update ProfilePresets if an id changes,",
        "  then run `python3 -I scripts/check_blocklist_catalog.py` until it reports 0 problems,",
        "  run `SaneMaster verify`, and move this file to `done/`.",
    ]
    pathlib.Path(path).expanduser().write_text("\n".join(lines) + "\n")


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    catalog = pathlib.Path(option(argv, "--catalog") or CATALOG)
    items = parse_catalog(catalog)
    if not items:
        print(f"no BlocklistSource entries found in {catalog}")
        return 2
    today = datetime.date.today()
    results = [check(item, today) for item in items]
    failures = 0
    for r in results:
        status = "FAIL" if r["problems"] else "ok"
        failures += bool(r["problems"])
        print(f"{status:4} {r['category']:15} {r['id']:24} label={r['estimatedEntries']:>5} "
              f"real={r['real']:>7} updated={r['updated']}  {'; '.join(r['problems'])}")
    if option(argv, "--json"):
        pathlib.Path(option(argv, "--json")).write_text(json.dumps(results, indent=1))
    print(f"\n{len(results)} lists, {failures} with problems")
    alert = option(argv, "--alert")
    if alert:
        alert_path = pathlib.Path(alert).expanduser()
        if failures:
            write_alert(alert_path, results, catalog)
            print(f"alert written: {alert_path}")
        elif alert_path.exists():
            done = alert_path.parent / "done"
            done.mkdir(exist_ok=True)
            alert_path.rename(done / alert_path.name)
            print(f"alert cleared: moved to {done / alert_path.name}")
        return 0
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
