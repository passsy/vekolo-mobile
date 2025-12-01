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

## Domain objects

- **Workout**: Definition of what power values the smart trainer should set over time. Consists of power blocks, ramp blocks, or intervals.
- **Activity**: A completed, uploaded workout recording. Stored on the server. Users can view activities from other users and ride their workouts.
- **WorkoutSession**: An in-progress activity being recorded locally. Has crash recovery support, can be resumed, abandoned, or completed. Becomes an Activity when uploaded.

The distinction between WorkoutSession and Activity exists because:
- Sessions are transient (can crash, be abandoned) while Activities are permanent
- Sessions live locally with crash recovery; Activities live on the server
- Sessions have in-progress state (currentBlockIndex, elapsedMs) that completed Activities don't need


## Platform Support

- **Mobile**: Android & iOS (current focus)
- **Desktop**: macOS (used heavily for development)
- **Web**: Planned for the future (code should be web-compatible where possible)

## Code style

- Follow Pascal's Code Style (see `/Users/pascalwelsch/Projects/passsy/pascal_rules/principles/`)

## State management

**📖 Essential reading:** [docs/state_beacon_overview.md](./docs/state_beacon_overview.md)

This project uses `state_beacon` for reactive state management.
DO NOT USE `StreamController`, always create a Beacon insteada which is way more flexible!

Key patterns:
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
- Use `addTearDown()` or `addFlutterTearDown()` for cleanup, avoid `setUp()`/`tearDown()`
- Never update `test/robot_kit.dart`. It is a copy of a Flutter platform file, which is very unlikely to have any bugs
- prefer robot.idle() without passing in a duration when no exact duration is known to "just wait a bit for async operations"
- **CRITICAL: ALWAYS test the real production code in /lib!**
  - **NEVER EVER create a local implementation in test files**
  - **NEVER copy/duplicate production code into tests**
  - Tests must import and test the actual implementation from /lib
  - If production code needs fixing, FIX IT FIRST, then test it
  - Creating "reference implementations" in tests is the WORST anti-pattern possible

### Fixing tests
- When a tests fails, first read the error/exception
- Add logging (with chirp) at key boundaries upfront when investigating. It simplifies debugging when actions can be viewed in order
- Remove logs AFTER tests are green
- Trust the users gut feeling. Explore and verify the user hypotheses first before looking for alternative solutions

## Documentation

- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Overall system architecture
- [docs/state_beacon_overview.md](./docs/state_beacon_overview.md) - **State management guide (read this first)**
- [docs/BLE_DEVICE_ARCHITECTURE.md](./docs/BLE_DEVICE_ARCHITECTURE.md) - BLE device handling
- [docs/DEVICE_ASSIGNMENT_ARCHITECTURE.md](./docs/DEVICE_ASSIGNMENT_ARCHITECTURE.md) - Device role assignment