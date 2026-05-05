# SaneHosts Distribution Guide

Current release flow for SaneHosts direct downloads, Sparkle updates, and website deployment.

## Source Of Truth

- Use the shared SaneApps release pipeline. Do not generate Sparkle keys, build DMGs manually, upload release files manually, or deploy Pages manually for normal releases.
- Public downloads live in the shared Cloudflare R2 bucket and are served through the SaneApps distribution service.
- Sparkle uses the shared SaneApps EdDSA public key configured in `Config/Shared.xcconfig`.
- App Store/TestFlight work uses the primary SaneApps Apple API key `S34998ZCRT`.

## Required Commands

Run release work from the project root on the Mac Mini.

```bash
./scripts/SaneMaster.rb release_preflight
./scripts/SaneMaster.rb appstore_preflight

bash ~/SaneApps/infra/SaneProcess/scripts/release.sh \
  --project "$(pwd)" --full --version X.Y.Z --notes "..." --deploy
```

Website-only deploys also go through the shared release script:

```bash
bash ~/SaneApps/infra/SaneProcess/scripts/release.sh \
  --project "$(pwd)" --website-only
```

## Release Checklist

- [ ] Version bumped before release.
- [ ] `CHANGELOG.md` updated with customer-facing notes.
- [ ] `./scripts/SaneMaster.rb release_preflight` passes.
- [ ] `./scripts/SaneMaster.rb appstore_preflight` passes when App Store lanes are involved.
- [ ] Shared `release.sh --full --deploy` completes signing, notarization, upload, appcast, and website deploy.
- [ ] Public `https://sanehosts.com/appcast.xml` advertises the new version.
- [ ] Public privacy page includes current third-party disclosures.
- [ ] Download link fetches the latest direct build.
- [ ] Sparkle update path is tested from the previous public version.

## Do Not Do

- Do not run Sparkle key-generation scripts.
- Do not commit private keys or release artifacts.
- Do not host app releases on GitHub Releases.
- Do not run ad hoc `wrangler r2 object put` or `wrangler pages deploy` for normal releases.
- Do not call unreleased `main` changes "shipped" in public replies.

## Credentials

- Apple notarization/TestFlight key: `S34998ZCRT`
- Team ID: `M78L6FXD48`
- Issuer ID: `c98b1e0a-8d10-4fce-a417-536b31c09bfb`
- Notary profile: `notarytool`

Secrets stay in Keychain or the shared SaneApps environment files. Do not add credential material to this repo.
