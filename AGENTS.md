# AGENTS.md

## General Instructions

- Ask before adding any new package!
- Avoid clean architecture
- Avoid those packages: bloc, provider, riverpod, freezed, build_runner, json_serializable, get_it
- Avoid mocks, use fake implementations instead
- Don't implement e2e tests (integration_tests)

## Setup commands

- Install dependencies: `puro flutter pub get`
- Run app: `puro flutter run`
- Run tests: `puro flutter test`
- Run analysis: `puro flutter analyze`

## Platform Support

- **Mobile**: Android & iOS (current focus)
- **Desktop**: macOS (used heavily for development)
- **Web**: Planned for the future (code should be web-compatible where possible)

## Code style

- Follow Pascal's Code Style (see `/Users/pascalwelsch/Projects/passsy/pascal_rules/principles/`)

## State management

**📖 Essential reading:** [docs/state_beacon_overview.md](./docs/state_beacon_overview.md)

This project uses `state_beacon` for reactive state management. Key patterns:

- Use `Beacon.writable` for mutable state
- Use `Beacon.derived` for computed values  
- Use `.watch(context)` in widget `build()` methods
- **Always prefer transform chains** over manual `.subscribe()` + mutation
- See examples in `lib/state/device_state.dart`
- Never place beacons top-level, making them singletons (which is bad practice)

Example:
```dart
// ✅ GOOD - Transform chain
final activeCount = source.filter((prev, next) => next > 0).map((v) => v * 2);

// ❌ BAD - Manual subscription
final activeCount = Beacon.writable(0);
source.subscribe((value) {
  activeCount.value = value * 2; // Risk of leaks
});
```

## Testing instructions

- Run all tests: `puro flutter test`
- Run specific test file: `puro flutter test test/path/to/test.dart`
- Use fakes (in-memory implementations) over mocks
- Test domain logic without hardware dependencies
- See `test/fake/` for fake implementations
- Use `addTearDown()` for cleanup, avoid `setUp()`/`tearDown()`

## Documentation

- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Overall system architecture
- [docs/state_beacon_overview.md](./docs/state_beacon_overview.md) - **State management guide (read this first)**
- [docs/BLE_DEVICE_ARCHITECTURE.md](./docs/BLE_DEVICE_ARCHITECTURE.md) - BLE device handling
- [docs/DEVICE_ASSIGNMENT_ARCHITECTURE.md](./docs/DEVICE_ASSIGNMENT_ARCHITECTURE.md) - Device role assignment

