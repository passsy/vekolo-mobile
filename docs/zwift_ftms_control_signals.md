# Zwift FTMS Control Signals Analysis

This document analyzes the FTMS (Fitness Machine Service) control signals sent by Zwift to a fitness device during a test session.

**Test Session Details:**
- Date: 2025-10-21
- Device: Zwack (simulated FTMS trainer)
- Modes tested: Free Ride and ERG Mode (180W)
- Source: `devices/control_from_zwift.txt`

## FTMS Control Point Characteristic

All commands are sent via the **Fitness Machine Control Point** characteristic:
- **UUID:** `2AD9`
- **Service:** FTMS (UUID `1826`)
- **Specification:** FTMS v1.0, Section 4.16.1

---

## Commands Received from Zwift

### 1. Request Control (Op Code `0x00`)

```
Raw Buffer: <Buffer 00>
Hex: 00
Dec: [0]
```

**Purpose:** Requests exclusive control over the fitness machine before making any changes.

**Frequency:** Sent **4 times** during the session (not just once):
- Line 949 (03:55:30.569)
- Line 995 (03:55:35.789)
- Line 1110 (03:55:49.978)
- Line 1156 (03:55:55.198)

**Pattern:** Zwift re-requests control when:
- Initially connecting
- Switching between modes (Free Ride ↔ ERG)
- Re-establishing control after state changes

**Expected Response:** Device should respond with success/failure via indication on characteristic `2AD9`.

---

### 2. Reset (Op Code `0x01`)

```
Raw Buffer: <Buffer 01>
Hex: 01
Dec: [1]
```

**Purpose:** Resets the fitness machine to its initial state.

**Frequency:** Sent **6 times** during the session:
- Line 962, 982, 1123, 1143 (after Request Control)

**Pattern:** Always follows a Request Control command.

**Expected Response:** Device should reset all parameters and confirm via indication.

---

### 3. Start or Resume (Op Code `0x07`)

```
Raw Buffer: <Buffer 07>
Hex: 07
Dec: [7]
```

**Purpose:** Starts or resumes the training session.

**Frequency:** Sent **4 times**:
- Line 1008, 1028, 1169

**Pattern:** Sent after Request Control → Reset sequence, before applying workout parameters.

**Expected Response:** Device should begin accepting workout data and confirm via indication.

---

### 4. Set Indoor Bike Simulation Parameters (Op Code `0x11`)

```
Raw Buffer: <Buffer 11 00 00 64 00 28 33>
Hex: 11 00 00 64 00 28 33
Dec: [17, 0, 0, 100, 0, 40, 51]
```

**Purpose:** Sets simulation parameters for realistic road feel (Free Ride mode).

**Frequency:** Sent **4 times**:
- Line 1042, 1059, 1076, 1093

**Parameters (per FTMS v1.0 §4.16.2.3):**

| Field | Bytes | Value (Hex) | Value (Dec) | Resolution | Calculated | Unit |
|-------|-------|-------------|-------------|------------|------------|------|
| Op Code | 0 | `11` | 17 | - | - | - |
| Wind Speed | 1-2 | `00 00` | 0 | 0.001 m/s | 0.00 m/s | m/s |
| Grade | 3-4 | `64 00` | 100 | 0.01% | +1.0% | % |
| Crr (Rolling Resistance) | 5 | `28` | 40 | 0.0001 | 0.0040 | - |
| Cw (Wind Resistance) | 6 | `33` | 51 | 0.01 kg/m | 0.51 kg/m | kg/m |

**Interpretation:** Simulates a **flat road with 1% incline**, no wind, typical rolling resistance.

**Expected Response:** Device should apply these parameters to calculate required resistance based on user's speed/cadence.

---

### 5. Set Target Power (Op Code `0x05`)

```
Raw Buffer: <Buffer 05 b4 00>
Hex: 05 B4 00
Dec: [5, 180, 0]
```

**Purpose:** Sets a fixed power target (ERG mode).

**Frequency:** Sent **2 times**:
- Line 1212, 1229

**Parameters (per FTMS v1.0 §4.16.2.2):**

| Field | Bytes | Value (Hex) | Value (Dec) | Resolution | Calculated | Unit |
|-------|-------|-------------|-------------|------------|------------|------|
| Op Code | 0 | `05` | 5 | - | - | - |
| Target Power | 1-2 | `b4 00` | 180 | 1 W | 180 W | W |

**Interpretation:** Device should maintain **180W constant power** regardless of user cadence/speed.

**Expected Response:** Device should adjust resistance to maintain target power.

---

## Typical Control Flow

Zwift follows this command sequence:

```
1. Request Control (0x00)
   └→ Response: Success
2. Reset (0x01)
   └→ Response: Success
3. Start or Resume (0x07)
   └→ Response: Success
4. Apply Workout:
   a) Set Indoor Bike Simulation (0x11) - for Free Ride
      OR
   b) Set Target Power (0x05) - for ERG mode
   └→ Response: Success
```

### Mode Switching Pattern

When switching from Free Ride to ERG mode:
```
Request Control (0x00)
└→ Reset (0x01)
   └→ Start/Resume (0x07)
      └→ Set Target Power (0x05, 180W)
```

When switching from ERG to Free Ride:
```
Request Control (0x00)
└→ Reset (0x01)
   └→ Start/Resume (0x07)
      └→ Set Indoor Bike Simulation (0x11, grade=1%)
```

---

## Periodic Command Updates / Keep-Alive Mechanism

### Why Commands Are Sent Repeatedly

Both **Set Indoor Bike Simulation (0x11)** and **Set Target Power (0x05)** commands are sent **periodically every ~2 seconds** with identical parameters, even when nothing has changed.

#### Timing Analysis from Logs

**Simulation Parameters (0x11):**
```
Line 1042: 03:55:41.788  <Buffer 11 00 00 64 00 28 33>
Line 1059: 03:55:43.829  <Buffer 11 00 00 64 00 28 33>  (+2.04s)
Line 1076: 03:55:45.868  <Buffer 11 00 00 64 00 28 33>  (+2.04s)
Line 1093: 03:55:47.909  <Buffer 11 00 00 64 00 28 33>  (+2.04s)
```

**Target Power (0x05):**
```
Line 1212: 03:56:24.811  <Buffer 05 b4 00>  (180W)
Line 1229: 03:56:26.791  <Buffer 05 b4 00>  (180W)  (+1.98s)
```

### Reasons for Periodic Updates

This is **normal FTMS protocol behavior** for several important reasons:

#### 1. Keep-Alive / Heartbeat
Periodic resending acts as a heartbeat signal that:
- Zwift is still running and maintaining control
- The workout session is still active
- The device should continue using these parameters

#### 2. State Synchronization
Ensures the device hasn't lost state due to:
- BLE connection issues or packet loss
- Device firmware glitches or unexpected resets
- Another application attempting to take control
- User switching apps or device disconnection/reconnection

#### 3. Protocol Robustness
BLE isn't perfectly reliable, so periodic resending ensures:
- Commands aren't lost in transmission
- The device stays in the correct mode
- Parameters are continuously maintained even if a single packet is dropped

#### 4. Quick Parameter Updates
By sending parameters every 2 seconds, Zwift can instantly adjust to virtual world changes:
- **Grade changes** when climbing/descending hills in the game
- **Wind resistance** when headwind/tailwind conditions change
- **Rolling resistance** when surface type changes (asphalt → gravel)
- **Target power** when ERG workout intervals change

Even though parameters were identical in this test session (flat road, constant 180W), the mechanism allows for seamless updates during actual workouts.

### Implementation Considerations

Your device firmware should:

**✅ DO:**
- Accept and acknowledge repeated commands even when parameters are unchanged
- Reset any connection timeout timers when receiving these updates
- Treat this as normal expected behavior, not an error condition
- Continue applying the parameters until new ones are received

**❌ DON'T:**
- Treat repeated identical commands as errors or duplicates
- Ignore commands just because parameters haven't changed
- Log warnings about "duplicate commands"
- Implement deduplication logic for these control messages

### Update Rate

The observed update rate is **~2 seconds** (500ms tolerance). This appears to be Zwift's standard control update rate for active workout sessions.

Device implementations should:
- Accept updates at this rate without performance issues
- Consider a control session "stale" if no update received for >5-10 seconds
- Optionally implement timeout logic to revert to safe state if updates stop

---

## Response Protocol

For each command received, the device should respond via **indication** on characteristic `2AD9` with:

```
Response Format (3 bytes):
[0x80, Op Code, Result Code]
```

**Result Codes (FTMS v1.0 §4.16.1.2):**
- `0x01` - Success
- `0x02` - Op Code Not Supported
- `0x03` - Invalid Parameter
- `0x04` - Operation Failed
- `0x05` - Control Not Permitted

**Example from logs:**
```
subscription note: {length = 3, bytes = 0x800001}
                                         ││││││
                                         ││││└└─ Result: 0x01 (Success)
                                         ││└└─── Op Code: 0x00 (Request Control)
                                         └└───── Response Code: 0x80
```

---

## Implementation Notes

### Device Requirements

1. **Must support indications** on Control Point characteristic (2AD9)
2. **Must respond to every command** within reasonable time (~100ms)
3. **Must validate parameters** and return appropriate error codes
4. **Must enforce control logic**: Only accept workout commands after Request Control succeeds

### Observed Zwift Behavior

- Re-requests control frequently (not just once at start)
- Always resets before changing modes
- Sends simulation parameters repeatedly (every ~2 seconds) in Free Ride
- Sends power target when switching to ERG mode
- Expects timely responses (may timeout/retry if no indication received)

### State Machine

Device should maintain state:
```
IDLE → CONTROLLED → ACTIVE → (SIMULATION | ERG)
  ↑        ↑          ↑              ↑
  │        │          │              │
0x00   Success    0x07        0x11 or 0x05
Request   ACK     Start        Workout
Control                         Mode
```

---

## References

- **FTMS Specification:** v1.0 (See `devices/FTMS_v1.0.pdf`)
- **Control Point:** Section 4.16.1
- **Set Target Power:** Section 4.16.2.2
- **Set Indoor Bike Simulation:** Section 4.16.2.3
- **Test Log:** `devices/control_from_zwift.txt`
