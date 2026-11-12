#!/usr/bin/env python3
"""Check every list in SaneHosts' blocklist catalog.

For each BlocklistSource in BlocklistCatalog.swift this downloads the list,
counts entries the way the app does, and finds when it last changed. It fails
when a list is unreachable, has not changed in over a year, is larger than the
app accepts, or when its estimatedEntries label is far from the real count.

Usage:
  python3 -I scripts/check_blocklist_catalog.py            # check the catalog
  python3 -I scripts/check_blocklist_catalog.py --json out.json
  python3 -I scripts/check_blocklist_catalog.py --self-test
"""

import datetime
import email.utils
import ipaddress
import json
import pathlib
import re
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


def github_last_change(url):
    match = re.match(r"https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)", url)
    if not match:
        return None
    owner, repo, branch, path = match.groups()
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/{owner}/{repo}/commits?path={path}&sha={branch}&per_page=1",
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
    if updated is not None and (today - updated).days > MAX_AGE_DAYS:
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


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    today = datetime.date.today()
    results = [check(item, today) for item in parse_catalog(CATALOG)]
    failures = 0
    for r in results:
        status = "FAIL" if r["problems"] else "ok"
        failures += bool(r["problems"])
        print(f"{status:4} {r['category']:15} {r['id']:24} label={r['estimatedEntries']:>5} "
              f"real={r['real']:>7} updated={r['updated']}  {'; '.join(r['problems'])}")
    if "--json" in argv:
        pathlib.Path(argv[argv.index("--json") + 1]).write_text(json.dumps(results, indent=1))
    print(f"\n{len(results)} lists, {failures} with problems")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
