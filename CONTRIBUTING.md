# Contributing to SaneHosts

Thank you for your interest in contributing to SaneHosts! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites
- macOS 15.0+
- Xcode 16.0+

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

3. Build and run (Cmd+R)

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
4. Run tests: Cmd+U in Xcode
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
- Test on both Intel and Apple Silicon if possible
- Test with both light and dark mode

## Architecture Notes

### SPM Package Structure
Most development happens in `SaneHostsPackage/Sources/SaneHostsFeature/`:
- `Models/` - Data models (Profile, HostEntry)
- `Services/` - Business logic (HostsService, ProfileStore, DNSService)
- `Views/` - SwiftUI views

### Key Services
- **HostsService** - Reads/writes /etc/hosts via AppleScript
- **ProfileStore** - Profile CRUD and persistence
- **DNSService** - Flushes DNS cache

### Security Considerations
- Hosts file modifications require admin authentication
- Use AppleScript `do shell script with administrator privileges`
- Never store credentials

## Getting Help

- Open an issue for questions
- Check existing issues and discussions
- Review the codebase documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
