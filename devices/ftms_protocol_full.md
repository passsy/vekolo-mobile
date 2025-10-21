# Fitness Machine Service (FTMS) v1.0 — Complete Protocol Documentation

Bluetooth SIG Service Specification (Simplified but Verbose)

---

## Overview
The **Fitness Machine Service (FTMS)** provides standardized Bluetooth Low Energy (BLE) communication between a **Client** (such as a mobile app) and a **Server** (such as a treadmill, bike trainer, or rowing machine). The service enables a Client to:
- Collect real-time exercise data
- Monitor and control training sessions
- Adjust machine parameters such as speed, incline, power, or resistance

Supported machine types:
- Treadmill
- Cross Trainer
- Step Climber
- Stair Climber
- Rower
- Indoor Bike

---

## Service UUID
```
UUID: Fitness Machine Service (FTMS)
```

---

## Primary Characteristics

| Characteristic | Properties | Requirement | Description |
|----------------|-------------|--------------|--------------|
| Fitness Machine Feature | Read | Mandatory | Reports supported features and capabilities |
| Fitness Machine Control Point | Write / Indicate | Optional | Command interface for control |
| Fitness Machine Status | Notify | Conditional | Status notifications from the server |
| Training Status | Read / Notify | Optional | Reports current training phase |
| Machine Data (e.g. Treadmill Data, Bike Data) | Notify | Optional | Periodic data records |
| Supported Ranges (Speed, Incline, Power, Resistance, HR) | Read | Conditional | Machine limits |

---

# Fitness Machine Control Point (FMCP)

This characteristic provides the **command and control interface** from Client to Server.

Client **writes** a request → Server **executes** the procedure → Server **indicates** completion or error.

All commands use this format:

| Field | Size | Type | Description |
|--------|------|------|-------------|
| Op Code | 1 | UINT8 | Defines the command |
| Parameters | Variable | Varies per Op Code | Optional command-specific data |

---

## General Response Format

**Op Code 0x80 — Response Code**

| Field | Type | Description |
|--------|------|-------------|
| Response Op Code | UINT8 | Always 0x80 |
| Request Op Code | UINT8 | Echo of request that triggered this response |
| Result Code | UINT8 | Status of execution |
| Optional Params | — | Procedure specific |

**Result Codes**
| Code | Meaning |
|------|----------|
| 0x00 | Reserved |
| 0x01 | Success |
| 0x02 | Op Code Not Supported |
| 0x03 | Invalid Parameter |
| 0x04 | Operation Failed |
| 0x05 | Control Not Permitted |

---

# Command Reference (Detailed)

## 0x00 — Request Control
Request the right to control the machine.

**Parameters:** None

**Response:**
- 0x01 Success → Client gains control
- 0x05 Control Not Permitted → Another client holds control

---

## 0x01 — Reset
Resets control variables to machine defaults.

**Parameters:** None

**Response:** 0x01 Success

---

## 0x02 — Set Target Speed
Sets treadmill or bike target speed.

**Parameters:**
| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Target Speed | UINT16 | 2 | km/h | 0.01 |

**Example:** 0x02 0x88 0x13 → 50.00 km/h

---

## 0x03 — Set Target Inclination
Adjusts machine incline.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Incline | SINT16 | 2 | % | 0.1 |

**Example:** 0x03 0x64 0x00 → +10.0%

---

## 0x04 — Set Target Resistance Level
Sets resistance level.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Resistance Level | UINT8 | 1 | level | 0.1 |

---

## 0x05 — Set Target Power
Sets the target power output.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Target Power | SINT16 | 2 | Watt | 1 |

---

## 0x06 — Set Target Heart Rate
Sets heart rate target.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Target HR | UINT8 | 1 | BPM | 1 |

---

## 0x07 — Start or Resume
Starts or resumes a training session.

**Parameters:** None

---

## 0x08 — Stop or Pause
Stops or pauses a session.

| Field | Type | Size | Description |
|--------|------|------|-------------|
| Stop Indicator | UINT8 | 1 | 0 = Pause, 1 = Stop |

---

## 0x09 — Set Targeted Expended Energy
Sets calorie goal.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Target Energy | UINT16 | 2 | kcal | 1 |

---

## 0x0A — Set Targeted Number of Steps
Sets step count goal.

| Field | Type | Size | Unit |
|--------|------|------|------|
| Steps | UINT16 | 2 | steps |

---

## 0x0B — Set Targeted Number of Strides
Sets stride goal.

| Field | Type | Size | Unit |
|--------|------|------|------|
| Strides | UINT16 | 2 | strides |

---

## 0x0C — Set Targeted Distance
Sets distance goal.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Distance | UINT24 | 3 | meters | 1 |

---

## 0x0D — Set Targeted Training Time
Sets total session time.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Time | UINT16 | 2 | seconds | 1 |

---

## 0x0E — Set Targeted Time in Two Heart Rate Zones
Defines time goal for each HR zone.

| Field | Type | Size | Unit | Description |
|--------|------|------|------|-------------|
| Zone1 Time | UINT16 | 2 | seconds | Time in lower HR zone |
| Zone2 Time | UINT16 | 2 | seconds | Time in upper HR zone |

---

## 0x0F — Set Targeted Time in Three Heart Rate Zones
Defines time goal for three HR zones.

| Field | Type | Size | Unit |
|--------|------|------|------|
| Zone1 Time | UINT16 | 2 | seconds |
| Zone2 Time | UINT16 | 2 | seconds |
| Zone3 Time | UINT16 | 2 | seconds |

---

## 0x10 — Set Targeted Time in Five Heart Rate Zones
Defines time goal for five HR zones.

| Field | Type | Size | Unit |
|--------|------|------|------|
| Zone1 Time | UINT16 | 2 | seconds |
| Zone2 Time | UINT16 | 2 | seconds |
| Zone3 Time | UINT16 | 2 | seconds |
| Zone4 Time | UINT16 | 2 | seconds |
| Zone5 Time | UINT16 | 2 | seconds |

---

## 0x11 — Set Indoor Bike Simulation Parameters
Applies to smart trainers simulating virtual terrain and environmental resistance.

| Field | Type | Size | Unit | Range | Description |
|--------|------|------|------|--------|-------------|
| Wind Speed | SINT16 | 2 | m/s | -327.67–327.67 | Headwind/tailwind. Positive = headwind |
| Grade | SINT16 | 2 | % | -100–100 | Road gradient |
| Rolling Resistance Coefficient (Crr) | UINT8 | 1 | — | 0–255 | Rolling resistance factor |
| Wind Resistance Coefficient (Cw) | UINT8 | 1 | — | 0–255 | Aerodynamic resistance factor |

**Total Length:** 6 bytes

---

## 0x12 — Set Wheel Circumference
Sets the wheel circumference for virtual distance computation.

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Circumference | UINT16 | 2 | millimeter | 0.1 |

---

## 0x13 — Spin Down Control
Performs a spin-down calibration test.

| Field | Type | Size | Description |
|--------|------|------|-------------|
| Control | UINT8 | 1 | 1 = Start, 2 = Accept, 3 = Reject, 4 = Abort |

---

## 0x14 — Set Targeted Cadence
Sets target cadence (pedal rate).

| Field | Type | Size | Unit | Resolution |
|--------|------|------|------|-------------|
| Cadence | UINT16 | 2 | RPM | 0.5 |

---

## 0x80 — Response Code
Indicates completion or error for any command.

**Format:** `[0x80, <Request OpCode>, <ResultCode>]`

---

# Fitness Machine Status (Notifications)

Characteristic used by Server to report machine state changes or confirmations.

| Op Code | Description | Parameter |
|----------|-------------|------------|
| 0x01 | Reset | — |
| 0x02 | Stopped or Paused by User | Stop Reason |
| 0x03 | Stopped by Safety Key | — |
| 0x04 | Started or Resumed by User | — |
| 0x05 | Target Speed Changed | Speed |
| 0x06 | Target Incline Changed | Incline |
| 0x07 | Target Resistance Changed | Resistance |
| 0x08 | Target Power Changed | Power |
| 0x09 | Target HR Changed | Heart Rate |
| 0x0A–0x13 | Target / Simulation parameter changes | Varies |
| 0x14 | Spin Down Status | UINT8 |
| 0xFF | Control Permission Lost | — |

---

# Notes
- All values use **Little Endian** byte order.
- ATT_MTU limitations apply; large records may require multiple notifications.
- Each control procedure must be completed (via indication) before starting another.
- Commands unsupported by the machine return Result Code `0x02`.

---

# Example Interaction

### Request Control
```
Client → Write [0x00]
Server → Indicate [0x80, 0x00, 0x01] // Success
```

### Set Target Power
```
Client → Write [0x05, 0x64, 0x00] // 100 W
Server → Indicate [0x80, 0x05, 0x01] // Success
Server → Notify [0x08, 0x64, 0x00] // Status update
```

### Indoor Bike Simulation Example
```
Client → Write [0x11, 0xF6, 0xFF, 0x0A, 0x00, 0x10, 0x20]
Server → Indicate [0x80, 0x11, 0x01]
```
---

End of FTMS v1.0 Command Documentation.

