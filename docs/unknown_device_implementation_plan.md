# Unknown Device Discovery - Implementation Plan

## Overview
Enable users to report unsupported Bluetooth devices by scanning all BLE devices, collecting comprehensive GATT data, and submitting reports to the backend for future device support.

## User Flow
1. User on ScannerPage clicks "My device is not listed"
2. Navigate to UnknownDeviceReportPage → auto-start BLE scan (no filters)
3. User selects their device from the list
4. App connects and collects all GATT data (services/characteristics/descriptors/properties/values)
5. User optionally adds notes (brand/model/other info)
6. App generates TXT file and submits to backend
7. Success message → navigate back to ScannerPage

---

## Backend API Specification

### Endpoint
```
POST /api/devices/report-unknown
Content-Type: multipart/form-data
Authorization: Bearer <access-token>
```

### Request Parameters
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `deviceId` | string | Yes | Bluetooth device ID/address |
| `deviceName` | string | Yes | Device name (can be empty string) |
| `notes` | string | No | Optional user notes (brand, model, etc.) |
| `reportFile` | file | Yes | TXT file with comprehensive BLE data |

### Response (200 OK)
```json
{
  "success": true,
  "message": "Device report submitted successfully",
  "reportId": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Error Responses
```json
// 401 Unauthorized
{
  "success": false,
  "message": "Authentication required"
}

// 400 Bad Request
{
  "success": false,
  "message": "Missing required field: deviceId"
}

// 500 Internal Server Error
{
  "success": false,
  "message": "Failed to save device report"
}
```

### Report File Format (TXT)
Human/LLM readable format with all available BLE data:

```
========================================
UNKNOWN DEVICE REPORT
========================================

DEVICE INFORMATION
------------------
Device ID: XX:XX:XX:XX:XX:XX
Device Name: Unknown Trainer
RSSI: -65 dBm
Connection Time: 2025-10-17 14:32:15 UTC

ADVERTISEMENT DATA
------------------
Manufacturer Data: [hex dump]
Service UUIDs: [...list of advertised service UUIDs...]

GATT SERVICES
=============

Service: Device Information Service
UUID: 0000180a-0000-1000-8000-00805f9b34fb
------------------
  Characteristic: Manufacturer Name String
  UUID: 00002a29-0000-1000-8000-00805f9b34fb
  Properties: Read
  Value: "Acme Corp"

  Descriptor: Characteristic User Description
  UUID: 00002901-0000-1000-8000-00805f9b34fb
  Value: "Manufacturer name"

Service: Custom Service
UUID: 0000ff00-0000-1000-8000-00805f9b34fb
------------------
  Characteristic: Custom Data
  UUID: 0000ff01-0000-1000-8000-00805f9b34fb
  Properties: Read, Notify, Write
  Value: [Unable to read - requires pairing]

  Descriptor: Client Characteristic Configuration
  UUID: 00002902-0000-1000-8000-00805f9b34fb
  Value: [0x00, 0x00]

[... all services/characteristics/descriptors ...]

========================================
END OF REPORT
========================================
```

---

## Implementation Tickets

### Ticket 1: Backend API Implementation
**Priority**: High
**Team**: Backend
**Estimated**: 2-3 days

**Description**:
Implement `POST /api/devices/report-unknown` endpoint to receive and store device reports.

**Acceptance Criteria**:
- [ ] Endpoint accepts multipart/form-data with deviceId, deviceName, notes (optional), reportFile
- [ ] Validates required fields (deviceId, deviceName, reportFile)
- [ ] Requires authentication (Bearer token)
- [ ] Stores report file in cloud storage (S3/GCS)
- [ ] Creates database record with metadata + file URL
- [ ] Returns success response with reportId
- [ ] Handles errors appropriately (400, 401, 500)
- [ ] API documented in backend README

**Technical Notes**:
- File storage: Store TXT files in cloud storage
- Database schema: `device_reports` table with: id, user_id, device_id, device_name, notes, file_url, created_at
- Consider file size limit (suggest 1MB max)

---

### Ticket 2: BleDeviceInspector Service
**Priority**: High
**Team**: Mobile
**Estimated**: 3-4 days
**File**: `lib/services/ble_device_inspector.dart`

**Description**:
Create service to connect to BLE device and collect comprehensive GATT data.

**Acceptance Criteria**:
- [ ] Connect to device by deviceId using flutter_reactive_ble
- [ ] Discover all services
- [ ] For each service: discover all characteristics
- [ ] For each characteristic: discover all descriptors
- [ ] Read properties (read/write/notify flags) for each characteristic
- [ ] Attempt to read all readable characteristics (handle errors gracefully)
- [ ] Attempt to read all descriptors
- [ ] Capture advertisement data (manufacturer data, service UUIDs)
- [ ] Generate human-readable TXT report with all data
- [ ] Handle connection failures, timeouts, permission errors
- [ ] Disconnect properly after collection
- [ ] Log errors using developer.log() with stackTrace

**Technical Notes**:
- Use existing flutter_reactive_ble from scanner_page.dart
- Timeout: 30 seconds for connection, 10 seconds per characteristic read
- Error handling: Continue collection even if some reads fail
- Format: Plain text, human-readable (see example above)

**Dependencies**: None

---

### Ticket 3: UnknownDeviceReportPage - Scanning & Selection
**Priority**: High
**Team**: Mobile
**Estimated**: 2-3 days
**File**: `lib/pages/unknown_device_report_page.dart`

**Description**:
Create page with BLE scanning and device selection UI.

**Acceptance Criteria**:
- [ ] Page auto-starts BLE scan on load (NO service filters)
- [ ] Shows explanatory text: "Scanning for all Bluetooth devices..."
- [ ] Displays loading indicator while scanning
- [ ] Shows list of discovered devices with: name (or "Unknown Device"), RSSI indicator, deviceId
- [ ] Updates list as devices are discovered
- [ ] User can tap device to select
- [ ] Handle Bluetooth permissions (request if needed)
- [ ] Handle Bluetooth disabled state (show error + link to settings)
- [ ] "Scan Again" button to restart scan
- [ ] Proper error messages with retry options

**Technical Notes**:
- Reuse flutter_reactive_ble from scanner_page.dart
- Consider using flutter_reactive_ble's scanForDevices() without service filter
- Sort devices by RSSI (strongest first)
- Debounce device list updates (200ms)

**Dependencies**: None

---

### Ticket 4: UnknownDeviceReportPage - Data Collection & Review
**Priority**: High
**Team**: Mobile
**Estimated**: 3-4 days
**File**: `lib/pages/unknown_device_report_page.dart` (continuation)

**Description**:
Implement device connection, data collection, and review/submit UI.

**Acceptance Criteria**:
- [ ] On device selection: show loading overlay "Connecting and collecting device information..."
- [ ] Call BleDeviceInspector to collect data
- [ ] Generate TXT file in memory
- [ ] On success: transition to review state
- [ ] Show "Device information collected" message
- [ ] Optional preview of first 10 lines of TXT data
- [ ] Single optional text field: "Additional info (brand, model, notes)" using reactive_forms
- [ ] Submit button
- [ ] Handle connection failures: show error + "Try Again" or "Back to List" buttons
- [ ] Handle collection errors gracefully (partial data is OK)

**Technical Notes**:
- Use BleDeviceInspector service (Ticket 2)
- Store TXT content in memory (String)
- Use reactive_forms for optional notes field
- Single-field form: FormGroup with 'notes' control (no validation)

**Dependencies**: Ticket 2 (BleDeviceInspector)

---

### Ticket 5: API Client - Report Unknown Device
**Priority**: Medium
**Team**: Mobile
**Estimated**: 2 days
**Files**:
- `lib/api/devices/report_unknown_device.dart`
- `lib/api/vekolo_api_client.dart`

**Description**:
Create API client method to submit device reports to backend.

**Acceptance Criteria**:
- [ ] Create `lib/api/devices/report_unknown_device.dart` following existing pattern
- [ ] Implement `postReportUnknownDevice()` function accepting ApiContext, deviceId, deviceName, notes, reportFileContent
- [ ] Use multipart/form-data with dio's FormData
- [ ] Include Authorization header (Bearer token)
- [ ] Return ReportUnknownDeviceResponse with success, message, reportId
- [ ] Handle errors with developer.log (error + stackTrace)
- [ ] Add method to VekoloApiClient: `reportUnknownDevice()`
- [ ] Export from vekolo_api_client.dart

**Technical Notes**:
- Follow pattern from update_profile.dart
- Use Rekord for response parsing
- FormData example:
```dart
FormData.fromMap({
  'deviceId': deviceId,
  'deviceName': deviceName,
  'notes': notes,
  'reportFile': MultipartFile.fromString(
    reportFileContent,
    filename: 'device_report_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.txt',
    contentType: MediaType('text', 'plain'),
  ),
})
```

**Dependencies**: Ticket 1 (Backend API must be ready)

---

### Ticket 6: Integration - Scanner & Router
**Priority**: Medium
**Team**: Mobile
**Estimated**: 1 day
**Files**:
- `lib/pages/scanner_page.dart`
- `lib/router.dart`

**Description**:
Add "My device is not listed" button to ScannerPage and configure routing.

**Acceptance Criteria**:
- [ ] Add button at bottom of device list in ScannerPage: "My device is not listed"
- [ ] Button navigates to `/unknown-device`
- [ ] Add route to router.dart: `/unknown-device` → UnknownDeviceReportPage
- [ ] Button styling consistent with app design

**Technical Notes**:
- Add button in scanner_page.dart around line 257 (after device list)
- Use context.go('/unknown-device') for navigation
- After successful report submission, navigate back: context.go('/scanner')

**Dependencies**: Ticket 3, 4 (UnknownDeviceReportPage must exist)

---

### Ticket 7: Error Handling & Polish
**Priority**: Medium
**Team**: Mobile
**Estimated**: 1-2 days

**Description**:
Implement comprehensive error handling and user feedback across all states.

**Acceptance Criteria**:
- [ ] Bluetooth disabled: Show error message + "Open Settings" button
- [ ] No permission: Request permission, handle denial gracefully
- [ ] No devices found: "No devices found" message + "Scan Again" button
- [ ] Connection timeout: Error message + "Try Again" or "Back to List"
- [ ] Data collection partial failure: Continue with available data
- [ ] Backend upload failed: Error message + "Retry" button (keep data in memory)
- [ ] Network offline: Appropriate error message
- [ ] All errors logged with developer.log(error, stackTrace)
- [ ] Loading states have appropriate messages
- [ ] Success state has clear "Back to Scanner" action

**Dependencies**: Tickets 3, 4, 5

---

### Ticket 8: End-to-End Testing
**Priority**: Medium
**Team**: Mobile + QA
**Estimated**: 2 days

**Description**:
Test complete flow with real BLE devices.

**Test Cases**:
- [ ] Happy path: Scanner → "Not listed" → Scan → Select → Collect → Submit → Success → Back
- [ ] Device with full GATT data (all characteristics readable)
- [ ] Device with restricted characteristics (some reads fail)
- [ ] Device with minimal GATT data
- [ ] Connection failure during collection
- [ ] Backend failure (500 error) → Retry succeeds
- [ ] Network offline during submission
- [ ] Bluetooth disabled mid-flow
- [ ] User cancels at various steps
- [ ] Submit with notes field empty
- [ ] Submit with notes field filled
- [ ] Multiple devices in scan list (verify correct one selected)
- [ ] Verify TXT file format is human-readable
- [ ] Verify backend receives complete data

**Dependencies**: All previous tickets

---

## Technical Stack
- **BLE**: flutter_reactive_ble (existing)
- **Forms**: reactive_forms (existing)
- **HTTP**: dio (existing)
- **Routing**: go_router (existing)
- **Data parsing**: Rekord + deep_pick (existing)

## No New Dependencies Required

## Development Order
1. **Backend**: Ticket 1 (can be developed in parallel with mobile)
2. **Mobile Foundation**: Ticket 2 (BleDeviceInspector)
3. **Mobile UI**: Ticket 3, 4 (UnknownDeviceReportPage)
4. **Mobile API**: Ticket 5 (API client)
5. **Integration**: Ticket 6 (Scanner + Router)
6. **Polish**: Ticket 7 (Error handling)
7. **Testing**: Ticket 8 (E2E tests)

## Estimated Total Timeline
- **Backend**: 2-3 days
- **Mobile**: 10-12 days (can overlap with backend)
- **Total**: ~2 weeks with testing

## Notes for Developers
- Follow existing code patterns (see scanner_page.dart, update_profile.dart)
- Use `puro flutter` instead of `flutter` CLI
- Always capture stack traces: `catch (e, stackTrace)`
- Use `developer.log()` with stackTrace for Flutter debugging
- All error handling must be comprehensive
- User experience is critical - clear messages, loading states, retry options
