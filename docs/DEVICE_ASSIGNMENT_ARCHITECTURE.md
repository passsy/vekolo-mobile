# Device Assignment & Auto-Reconnect Architecture

## Overview

This document describes the planned architecture for automatic device assignment, persistence, and reconnection. The goal is to create a seamless user experience where devices automatically connect when available, eliminating the need for users to manually reconnect devices each time they start the app.

**Status**: This architecture is planned but not yet fully implemented. The persistence functions exist but are not yet integrated with DeviceManager. Auto-reconnect functionality has not been implemented yet.

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
- **Assigned device disconnects**: Scanner starts immediately

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

**Key behaviors (planned):**
- Assignment methods automatically persist changes (not yet implemented)
- On initialization, loads saved assignments and restores them to connected devices (not yet implemented)
- Monitors device list for disconnections (not yet implemented)
- Controls scanner start/stop based on assignment state (not yet implemented)

**Current state:**
- DeviceManager manages device collection and role assignments
- Assignment methods exist but don't persist changes
- No auto-reconnect functionality exists yet
- Devices are not automatically removed on disconnection

### 3. BleScanner

**Responsibilities:**
- Token-based scanning (multiple independent requests)
- Device discovery and lifecycle management
- Bluetooth state monitoring

**Planned interaction with DeviceManager:**
- DeviceManager will request scan tokens when needed (not yet implemented)
- DeviceManager will listen to discovered devices (not yet implemented)
- DeviceManager will release tokens when all devices connected (not yet implemented)

**Current state:**
- BleScanner provides token-based scanning
- Scanner is manually controlled by UI (scanner_page.dart)
- No automatic coordination with DeviceManager yet

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
   → Auto-assigned to appropriate roles based on capabilities (current behavior)
   → Assignments automatically persisted (planned, not yet implemented)

4. User closes app
   → Assignments would be saved (planned, not yet implemented)

### App Restart Flow (Happy Path) - Planned

1. User opens app
   → DeviceManager loads saved assignments (planned)
   → Finds assigned devices

2. DeviceManager checks connected devices
   → Devices not connected yet
   → Starts scanner automatically (planned)

3. Scanner discovers assigned device
   → Auto-connect triggered (planned)
   → Device connects successfully
   → Device added to DeviceManager
   → Role assignments restored from saved data (planned)
   → Scanner continues (if other devices still missing)

4. All assigned devices connected
   → Scanner stops automatically (planned)

5. User starts workout
   → All devices ready, seamless experience

**Current state**: Users must manually reconnect devices after app restart.

### Disconnection During Use Flow - Planned

1. User is mid-workout, all devices connected
   → Scanner is off

2. Device disconnects (battery died, out of range, etc.)
   → DeviceManager detects disconnection (planned)
   → Scanner starts automatically (planned)

3. Device comes back online
   → Scanner discovers device
   → Auto-connect triggered (planned)
   → Device reconnects
   → Role assignments restored (planned)
   → Scanner stops (all devices connected)

4. User continues workout
   → Minimal disruption

**Current state**: Devices remain in DeviceManager when disconnected. Users must manually reconnect.

## Architecture Details

### Persistence Integration

**When assignments are saved (planned):**
- Automatically when any assignment method is called
- Fire-and-forget pattern (doesn't block assignment operations)

**When assignments are loaded (planned):**
- On app start when DeviceManager initializes auto-reconnect
- Assignments are restored to devices that are already connected

**Assignment restoration (planned):**
- When a device connects, DeviceManager checks if it matches any saved assignments
- If match found, automatically restores role assignments
- Only restores if device still supports the required capabilities

**Current state**: Persistence functions exist (`device_assignment_persistence.dart`) but are not called anywhere. Assignments are not persisted or restored.

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

### Connection Logic (Planned)

Auto-connect will use the same connection flow as manual connection:
1. Detect device type (via transport registry)
2. Create device instance
3. Connect to device
4. Add to DeviceManager
5. Restore role assignments from saved data

This ensures consistency between manual and automatic connections.

**Current state**: Manual connection exists in `scanner_page.dart`. Auto-connect has not been implemented yet.

### Lifecycle Integration (Planned)

**App start:**
- DeviceManager initializes auto-reconnect system (planned)
- Loads saved assignments (planned)
- Starts scanner if needed (planned)

**App background:**
- Auto-reconnect stops scanning (planned)
- Assignments remain saved

**App foreground:**
- Auto-reconnect resumes (planned)
- Checks current state and starts scanner if needed (planned)

**App shutdown:**
- Assignments already saved (saved on each change) (planned)

**Current state**: No lifecycle integration exists. No auto-reconnect system to integrate.

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
