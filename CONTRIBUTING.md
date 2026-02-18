# Contributing to SaneHosts

Thank you for your interest in contributing to SaneHosts! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites
- macOS 14.0+ (Sonoma)
- Xcode 16.0+
- Ruby 3.0+ (for SaneMaster tooling)

### Getting Started

1. Clone the repository:
```bash
git clone https://github.com/sane-apps/SaneHosts.git
cd SaneHosts
```

2. Open the workspace in Xcode:
```bash
open SaneHosts.xcworkspace
```

3. Build + test (preferred):
```bash
./scripts/SaneMaster.rb verify
```

4. Build + launch (full cycle):
```bash
./scripts/SaneMaster.rb test_mode
```

### Project Structure
```
SaneHosts/
├── SaneHosts.xcworkspace/     # Open this file
├── SaneHosts/                 # App target (minimal)
│   ├── SaneHostsApp.swift     # App entry point
│   └── Assets.xcassets/       # App icons
├── SaneHostsPackage/          # Feature code (SPM package)
│   ├── Sources/SaneHostsFeature/
│   └── Tests/SaneHostsFeatureTests/
└── Config/                    # Build configurations
```

## How to Contribute

### Reporting Bugs
- Check if the issue already exists
- Use the bug report template
- Include macOS version, app version
- Provide steps to reproduce

### Feature Requests
- Use the feature request template
- Describe the use case
- Consider implementation complexity

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Run tests: `./scripts/SaneMaster.rb verify`
5. Ensure no SwiftLint warnings
6. Commit with a descriptive message
7. Push and create a PR

### Code Style
- Follow existing code patterns
- Use Swift's naming conventions
- Keep functions focused and small
- Add comments for complex logic
- Use `// MARK:` for code organization

### Testing
- Write unit tests for new features
- Ensure existing tests pass
- Test with both light and dark mode

## Architecture Notes

### SPM Package Structure
Most development happens in `SaneHostsPackage/Sources/SaneHostsFeature/`:
- `Models/` - Data models (Profile, HostEntry)
- `Services/` - Business logic (HostsService, ProfileStore, DNSService)
- `Views/` - SwiftUI views

### Key Services
- **HostsService** - Writes /etc/hosts via privileged helper (Touch ID) with AppleScript fallback
- **ProfileStore** - Profile CRUD and persistence
- **DNSService** - Flushes DNS cache

### Security Considerations
- Hosts file modifications require admin authentication
- Privileged helper is preferred (Touch ID). AppleScript is fallback.
- Never store credentials

## Getting Help

- Open an issue for questions
- Check existing issues and discussions
- Review the codebase documentation

## License

By contributing, you agree that your contributions will be licensed under GPL v3.

<!-- SANEAPPS_AI_CONTRIB_START -->
## Become a Contributor (Even if You Don't Code)

Are you tired of waiting on the dev to get around to fixing your problem?  
Do you have a great idea that could help everyone in the community, but think you can't do anything about it because you're not a coder?

Good news: you actually can.

Copy and paste this into Claude or Codex, then describe your bug or idea:

```text
I want to contribute to this repo, but I'm not a coder.

Repository:
https://github.com/sane-apps/SaneHosts

Bug or idea:
[Describe your bug or idea here in plain English]

Please do this for me:
1) Understand and reproduce the issue (or understand the feature request).
2) Make the smallest safe fix.
3) Open a pull request to https://github.com/sane-apps/SaneHosts
4) Give me the pull request link.
5) Open a GitHub issue in https://github.com/sane-apps/SaneHosts/issues that includes:
   - the pull request link
   - a short summary of what changed and why
6) Also give me the exact issue link.

Important:
- Keep it focused on this one issue/idea.
- Do not make unrelated changes.
```

If needed, you can also just email the pull request link to hi@saneapps.com.

I review and test every pull request before merge.

If your PR is merged, I will publicly give you credit, and you'll have the satisfaction of knowing you helped ship a fix for everyone.
<!-- SANEAPPS_AI_CONTRIB_END -->
