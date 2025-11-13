# Device Assignment & Auto-Reconnect Architecture

## Overview

This document describes the architecture for automatic device assignment, persistence, and reconnection. The goal is to create a seamless user experience where devices automatically connect when available, eliminating the need for users to manually reconnect devices each time they start the app.

**Status**: ✅ Fully implemented. DeviceManager integrates with persistence, handles auto-reconnect, and distinguishes between user-initiated and automatic disconnections.

## Architecture Principles

1. **DeviceManager owns the lifecycle**: DeviceManager handles device assignments, persistence, and auto-reconnect coordination.
2. **Simple persistence**: Two standalone functions handle save/load, used internally by DeviceManager.
3. **Token-based scanning**: Scanner uses tokens to allow multiple independent scan requests without interference.
4. **Reactive state**: All state changes flow through reactive beacons, ensuring UI and persistence stay in sync.

## Core Concepts

### Device Assignment

A device assignment binds a physical BLE device to a functional role in the app:

- **primaryTrainer**: Primary trainer for ERG control, can also provide power/cadence data
- **powerSource**: Dedicated power meter, overrides trainer's power if assigned
- **cadenceSource**: Dedicated cadence sensor, overrides trainer's cadence if assigned
- **speedSource**: Dedicated speed sensor, overrides trainer's speed if assigned
- **heartRateSource**: Dedicated heart rate monitor

**Key principles:**
- One device can have multiple roles (e.g., KICKR CORE is both powerSource and primaryTrainer)
- Each role can only have one device assigned at a time
- Assignments persist across app restarts
- Assignments survive device disconnections

### Auto-Reconnect System

The system automatically handles device discovery and connection based on assignments:

**States:**
- **No assignments**: Scanner stays off, manual discovery only
- **All assigned devices connected**: Scanner stays off
- **Some assigned devices missing**: Scanner actively searching
- **Assigned device disconnects unexpectedly**: Scanner starts immediately

#### Manual vs. Automatic Disconnections

The system distinguishes between two types of disconnections:

**User-Initiated Disconnect:**
- User clicks the "Disconnect" button in the UI
- Device is marked as manually disconnected
- Auto-reconnect is **disabled** for this device
- Device will NOT automatically reconnect when it comes back online
- User must manually reconnect via the "Connect" button to re-enable auto-reconnect
- This prevents the frustrating scenario where the user tries to disconnect but the device keeps reconnecting

**Automatic/Unexpected Disconnect:**
- Device powers off (battery dies, device turned off)
- Device goes out of Bluetooth range
- Connection is lost due to interference or other technical issues
- Auto-reconnect is **enabled**
- Device will automatically reconnect when it comes back online
- Scanner starts immediately to search for the device

**Implementation Details:**
- `DeviceManager` maintains a `_manuallyDisconnectedDeviceIds` set
- When `disconnectDevice()` is called (via UI), the device ID is added to this set
- When `connectDevice()` is called (via UI), the device ID is removed from this set
- `_setupDeviceConnectionMonitoring()` checks this set before triggering auto-reconnect
- Auto-connect scanning also skips devices in this set

## Components

### 1. Persistence Layer

Simple save/load functions that:
- Save current device assignments to persistent storage (SharedPreferences)
- Load saved assignments on app start
- Return a map of device IDs to their assigned roles

**Storage format** (JSON in SharedPreferences):
```json
{
  "version": 1,
  "assignments": [
    {
      "deviceId": "DFFE6EF8-640E-AFDB-A557-C3D891F37A55",
      "deviceName": "KICKR CORE 6D9A",
      "role": "powerSource",
      "assignedAt": "2025-01-31T10:30:00.000Z"
    },
    {
      "deviceId": "DFFE6EF8-640E-AFDB-A557-C3D891F37A55",
      "deviceName": "KICKR CORE 6D9A",
      "role": "primaryTrainer",
      "assignedAt": "2025-01-31T10:30:00.000Z"
    },
    {
      "deviceId": "8BC15E62-32F3-4F91-A410-7E1E2E39C8D1",
      "deviceName": "Polar H9 3B4C1F",
      "role": "heartRateSource",
      "assignedAt": "2025-01-31T10:31:00.000Z"
    }
  ]
}
```

The version field allows for schema evolution. Future versions can migrate old data.

### 2. DeviceManager

**Responsibilities:**
- Manage device collection and role assignments
- Persist assignments automatically when they change
- Load and restore assignments on initialization
- Coordinate with scanner for auto-reconnect
- Track which devices should auto-reconnect
- Distinguish between manual and automatic disconnects

**Key behaviors:**
- Assignment methods automatically persist changes via `_saveAssignmentsAsync()`
- On initialization (`initialize()`), loads saved assignments and restores them
- Monitors device connection state via `_setupDeviceConnectionMonitoring()`
- Controls scanner start/stop based on assignment state
- Tracks manually disconnected devices to prevent unwanted auto-reconnect
- Automatically starts scanning when assigned devices disconnect unexpectedly

### 3. BleScanner

**Responsibilities:**
- Token-based scanning (multiple independent requests)
- Device discovery and lifecycle management
- Bluetooth state monitoring

**Interaction with DeviceManager:**
- DeviceManager requests scan tokens via `startScan()` when needed
- DeviceManager subscribes to `scanner.devices` to monitor discovered devices
- DeviceManager releases tokens via `stopScan()` when all assigned devices are connected
- Both manual scanning (via UI) and auto-reconnect scanning can run simultaneously
- Each scan request gets its own independent token

## User Flows

### Initial Setup Flow

1. User opens app for first time
   → No saved assignments
   → Scanner stays off

2. User navigates to device pairing
   → Manually starts scanner
   → Discovers devices

3. User selects device and connects
   → Device added to DeviceManager
   → User assigns device to appropriate roles via UI
   → Assignments automatically persisted

4. User closes app
   → Assignments are saved

### App Restart Flow (Happy Path)

1. User opens app
   → DeviceManager loads saved assignments during `initialize()`
   → Finds assigned devices

2. DeviceManager checks connected devices
   → Devices not connected yet
   → Starts scanner automatically via `_startAutoConnectScanning()`

3. Scanner discovers assigned device
   → Auto-connect triggered via `_connectAndRestoreDevice()`
   → Device connects successfully
   → Device added to DeviceManager
   → Role assignments restored from saved data via `_restoreAssignmentsForDevice()`
   → Scanner continues (if other devices still missing)

4. All assigned devices connected
   → Scanner stops automatically (checked in `_shouldStopAutoConnectScanning()`)

5. User starts workout
   → All devices ready, seamless experience

### Unexpected Disconnection During Use Flow

1. User is mid-workout, all devices connected
   → Scanner is off

2. Device disconnects unexpectedly (battery died, out of range, etc.)
   → DeviceManager detects disconnection via `_setupDeviceConnectionMonitoring()`
   → Device is NOT in `_manuallyDisconnectedDeviceIds` set
   → Device has assigned role
   → Scanner starts automatically via `_startAutoConnectScanning()`

3. Device comes back online
   → Scanner discovers device
   → Auto-connect triggered
   → Device reconnects
   → Role assignments restored
   → Scanner stops (all devices connected)

4. User continues workout
   → Minimal disruption

### Manual Disconnect Flow

1. User is mid-workout, device is connected and assigned
   → Scanner is off

2. User clicks "Disconnect" button in UI
   → `_handleDisconnect()` calls `deviceManager.disconnectDevice(deviceId)`
   → Device ID is added to `_manuallyDisconnectedDeviceIds` set
   → Device disconnects

3. Device disconnection detected
   → `_setupDeviceConnectionMonitoring()` checks `_manuallyDisconnectedDeviceIds`
   → Device is in the set, so auto-reconnect is skipped
   → Scanner remains off

4. Device comes back online and starts advertising
   → Scanner is not running (or is running but skips this device)
   → Device does NOT automatically reconnect
   → User has control

5. User manually clicks "Connect" button
   → Device ID is removed from `_manuallyDisconnectedDeviceIds` set
   → Device connects
   → Auto-reconnect is re-enabled for this device

## Architecture Details

### Persistence Integration

**When assignments are saved:**
- Automatically when any assignment method is called (`assignPrimaryTrainer()`, `assignPowerSource()`, etc.)
- Uses `_saveAssignmentsAsync()` with fire-and-forget pattern (doesn't block assignment operations)
- Errors are logged but don't block the assignment

**When assignments are loaded:**
- On app start when `DeviceManager.initialize()` is called
- Loads via `persistence.loadAssignments()`
- Creates `AssignedDevice` wrappers without connected devices (devices not yet connected)
- These wrappers are updated when devices connect

**Assignment restoration:**
- When a device auto-connects via `_connectAndRestoreDevice()`, DeviceManager checks saved assignments
- `_restoreAssignmentsForDevice()` updates `AssignedDevice` wrappers with actual device references
- This links the persisted assignment to the now-connected device instance
- Assignments are restored regardless of capabilities (assumes saved assignments were valid when created)

### Scanner Control

**Decision logic:**
1. If no assignments exist → don't scan
2. If all assigned devices connected → don't scan
3. If auto-reconnect disabled → don't scan
4. Otherwise → start scanning

**Token management:**
- DeviceManager holds one scan token for auto-reconnect
- Token released when scanning no longer needed
- Token managed independently from manual scanning tokens

### Connection Logic

Auto-connect uses the same connection flow as manual connection:
1. Detect device type via `transportRegistry.detectCompatibleTransports()`
2. Create `BleDevice` instance with detected transports
3. Add device to DeviceManager via `addDevice()`
4. Connect to device via `connectDevice(deviceId).value`
5. Restore role assignments from saved data via `_restoreAssignmentsForDevice()`

This ensures consistency between manual and automatic connections.

**Implementation:** See `_connectAndRestoreDevice()` in `DeviceManager`

### Lifecycle Integration

**App start:**
- DeviceManager initializes auto-reconnect system via `initialize()`
- Loads saved assignments via `persistence.loadAssignments()`
- Restores assignment wrappers via `_restoreAssignments()`
- Starts scanner if needed via `_startAutoConnectIfNeeded()`

**App background:**
- Auto-reconnect continues scanning (no special handling)
- Assignments remain in memory and storage
- Connection monitoring continues

**App foreground:**
- No special handling needed
- Auto-reconnect continues working

**App shutdown:**
- Assignments already saved (saved on each change)
- DeviceManager `dispose()` cleans up:
  - Stops auto-connect scanning
  - Cancels connection state subscriptions
  - Disconnects all devices
  - Disposes all beacons

## Error Handling

### Connection Failures

- Auto-connect failures are logged
- Scanner continues running (will retry on next discovery)
- No user interruption (failures are silent)

### Assignment Conflicts

- When restoring assignments, skip if device no longer supports required capabilities
- Log warnings for skipped assignments
- Continue with available assignments

### Storage Corruption

- Persistence functions handle corruption gracefully
- Return empty assignments if data invalid
- App continues with fresh start
- Log errors for debugging

## State Management

DeviceManager uses reactive beacons for state:

- Assignment beacons track which device is assigned to each role
- Device list beacon tracks all connected devices
- Derived beacons automatically update when assignments change
- UI watches beacons for reactive updates
- Persistence reads from beacons when saving

This ensures:
- UI automatically updates when assignments change
- Persistence always reflects current state
- No manual synchronization needed

## Testing Strategy

### Unit Tests

- Test assignment persistence (save/load)
- Test assignment restoration
- Test scanner control logic
- Test assignment methods trigger persistence

### Integration Tests

- Test full auto-reconnect flow
- Test disconnection handling
- Test multiple device scenarios
- Test app restart scenarios

## Future Enhancements

### Connection Retry Strategy

Add exponential backoff for failed connections with max attempts.

### Device Preferences

Store per-device settings alongside assignments (e.g., preferred ERG mode, calibration data).

### Connection Priority

Order connection attempts by role priority (trainer > power > HR > cadence > speed).

### Geofencing

Only auto-connect in specific locations (e.g., home gym).

## Migration Path

For existing apps with manually managed devices:

1. On first launch, detect currently connected devices
2. Offer to assign them automatically
3. User confirms or declines
4. Future connections use new auto-reconnect system
