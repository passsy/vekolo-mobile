# Claude Code Instructions

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md


## Platform Support

- **Mobile**: Android & iOS (current focus)
- **Desktop**: macOS (used heavily for development)
- **Web**: Planned for the future (code should be web-compatible where possible)


## General Instructions

- Ask before adding any new package!
- Avoid clean architecture
- Avoid those packages: bloc, provider, riverpod, freezed, build_runner, json_serializable, get_it
- Avoid mocks, use fake implementations instead
- Don't implement e2e tests (integration_tests)
