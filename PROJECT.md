# Project: ReDrive Suzuki Swift 3 (M15A Engine) Headunit

## Architecture
- **Application Core & UI**: Flutter 3.x / Dart application for Android Automotive / Headunit (with custom broadcast receivers for FYT/SYU, Microntek, and Topway hardware).
- **OBD-II Layer**:
  - Connection abstraction: `ObdConnection` with implementations `TcpObdConnection` (Wi-Fi/Emulator) and `BluetoothObdConnection` (Classic Bluetooth RFCOMM).
  - ELM327 Client: `ElmClient` manages AT command sequences, watchdog timers, and command queuing.
  - PID Registry & Decoders: Extensible registry mapping Mode 01 PIDs to specialized byte decoders for speed, RPM, coolant temp, IAT, throttle, load, and MAF.
  - Polling Controller: Dynamic polling loop querying core sensor PIDs at configured rates.
- **Trip Tracking & Telemetry**:
  - `FuelCalculator`: Instantaneous fuel flow (L/h) and fuel economy (L/100km) calibrated for Suzuki Swift 3 M15A (1490 cc, 14.7:1 AFR, 820 g/L fuel density, DFCO detection).
  - `TripProvider`: Automatic trip start/stop state machine, trapezoidal distance and fuel integration, driving statistics.
  - `TripHistoryService`: Persistent JSON storage (`trips_history.json`) with atomic writes and crash-resilient deserialization.
- **Diagnostics (DTC)**:
  - `DtcDecoder`: ISO 14230-4 K-Line and CAN hex decoder for Mode 03 (stored) and Mode 07 (pending) DTCs supporting P, C, B, U prefixes and lookup mapping.
  - `DtcService`: Mode 03/07 queries and guarded Mode 04 DTC clearing with stationary vehicle interlocks.
- **Offline Emulation & Verification**:
  - `tools/elm327_emulator.py`: TCP socket emulator simulating Suzuki Swift 3 M15A ELM327 v2.3 adapter (AT commands, Mode 01 PIDs, Mode 03/07 DTCs, Mode 04 clearing, DFCO profile).
  - Automated test harnesses: Comprehensive unit, integration, and opaque-box E2E suites verifying all four acceptance criteria pillars.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Toolchain & Test Runner Setup | Ensure Flutter/Dart SDK and test runner execute cleanly with zero environment errors | M0 | survey |
| 2 | Mode 01 PID Telemetry Ingestion | Correct parsing of Speed, RPM, Coolant Temp, IAT, Throttle, Load, and MAF | M1 | survey |
| 3 | Intake Air Temp (IAT) Pipeline | Integrate PID 010F into core keys, default session keys, and ObdData model | M1 | survey |
| 4 | M15A Fuel Calibration & Density | Baseline calibration for 1.5L displacement, 14.7:1 AFR, 820 g/L gasoline density | M1 | survey |
| 5 | Fuel Trim Compensation Fix | Fix mathematical inversion in FuelCalculator so positive trims increase fuel flow | M1 | survey |
| 6 | DFCO Detection & Zero-Fuel Handling | Calibrate closed-throttle DFCO condition for M15A idle/closed throttle ranges | M1 | survey |
| 7 | Trip Lifecycle Auto-Detection | Automatic trip start on engine start/movement and automatic stop on engine off/disconnect | M2 | survey |
| 8 | Trip Discard Threshold Fix | Remove or lower 10 km discard threshold so short and urban trips persist | M2 | survey |
| 9 | Numerical Metric Integration | Symmetric trapezoidal integration for distance and cumulative fuel consumption | M2 | survey |
| 10 | Trip History Persistence & Recovery | Atomic serialization and corruption recovery for trips_history.json surviving restarts | M2 | survey |
| 11 | In-Flight Trip Checkpoint | Crash-resilient active trip checkpointing to prevent in-flight data loss | M2 | survey |
| 12 | Mode 03 Stored DTC Decoding | Correct hex parsing of stored DTCs with K-Line/CAN byte alignment and prefix decoding | M3 | survey |
| 13 | Mode 07 Pending DTC Decoding | Correct hex parsing of pending DTCs matching Mode 03 structure | M3 | survey |
| 14 | ELM Response Parser Hardening | Support 2-token responses (`43 00`, `44`) and unspaced hex in ElmResponseParser | M3 | survey |
| 15 | Mode 04 Guarded Clear Execution | Guarded Mode 04 clear command with confirmation and stationary vehicle interlock | M3 | survey |
| 16 | Multiline DTC Support | Proper handling of multiline and ISO-TP continuation frames | M3 | survey |
| 17 | ELM327 Emulator Mode 03/04/07 | Extend tools/elm327_emulator.py with Mode 03, Mode 04, Mode 07, and PID 015E | M4 | survey |
| 18 | ELM327 Emulator DFCO Profile | Add coast-down/DFCO phases with closed throttle to emulator simulation loop | M4 | survey |
| 19 | Offline Emulation Socket Pipeline | Socket-level automated test harness connecting to emulator or in-process loopback | M4 | survey |
| 20 | Dual-Track E2E Test Suite | Comprehensive opaque-box test suite across Tiers 1-4 published via TEST_READY.md | E2E | survey |
| 21 | Final 100% E2E Pass & Adversarial Hardening | Pass all E2E test suites with 0 failures and adversarial coverage hardening (Tier 5) | M5 | survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Toolchain & Test Runner Readiness | Provision Dart/Flutter test toolchain, fix local.properties, verify test runner execution | none | DONE |
| E2E | E2E Testing Suite (Dual Track) | Opaque-box test harness & test cases (Tiers 1-4) derived from user requirements; publishes TEST_READY.md | M0 | DONE |
| M1 | R1 Telemetry & M15A Fuel Calculations | Calibrate M15A fuel calculations, fix trim inversion, calibrate DFCO, wire IAT telemetry | M0 | DONE |
| M2 | R2 Trip Tracking & Persistence | Fix 10 km discard threshold, symmetrical integration, atomic persistence, restart recovery | M0 | DONE |
| M3 | R3 DTC Operations & Safety Guard | Fix DTC byte alignment, ElmResponseParser 43 00 fix, stationary interlock, Mode 04 | M0 | DONE |
| M4 | R4 Offline Emulation & Verification | Harden tools/elm327_emulator.py (Mode 03/04/07, DFCO profile, PID 015E bitmask) & socket test harness | M0 | DONE |
| M5 | Final Milestone: 100% E2E Pass & Tier 5 Hardening | Verify all tests pass with 0 failures, adversarial testing with Challengers, forensic audit | E2E, M1, M2, M3, M4 | DONE |

## Interface Contracts

### `FuelCalculator` ↔ `ObdProvider` / `TripProvider`
- `double calculateFuelFlowLitersPerHour({double? mafGramsPerSecond, double? rpm, double? engineLoadPercent, double? shortTermFuelTrimPercent, double? longTermFuelTrimPercent, double? speedKmH, double? throttlePositionPercent})`
  - Returns: instantaneous fuel flow in L/h. Clamped between `0.0` and `60.0`.
  - Under DFCO (`speedKmH > 20`, `rpm > 1300`, closed throttle, light load): returns `0.0`.
  - Trims: positive trim increases fuel rate proportionally; negative trim decreases fuel rate.
- `double calculateLitersPer100Km(double fuelFlowLPerHour, double speedKmH)`
  - Returns: fuel economy in L/100km. When `speedKmH <= 0` or `fuelFlowLPerHour <= 0`, returns `0.0`. Clamped to `[0.0, 99.9]`.

### `TripProvider` ↔ `TripHistoryService`
- `Future<void> saveTrip(Trip trip)`
  - Serializes trip to `trips_history.json` atomically using temporary file rename.
- `Future<List<Trip>> loadTrips()`
  - Reads `trips_history.json`. If corrupt, backs up corrupt file and recovers without wiping valid history.

### `DtcService` ↔ `DtcDecoder`
- `Future<List<DtcCode>> getConfirmedTroubleCodes()`: sends `'03'`, passes response raw to `DtcDecoder.decode('43', raw)`.
- `Future<List<DtcCode>> getPendingTroubleCodes()`: sends `'07'`, passes response raw to `DtcDecoder.decode('47', raw)`.
- `Future<bool> clearAllCodes({bool allowWhileMoving = false})`: validates vehicle is stationary (`speed == 0 && rpm == 0`), sends `'04'`, verifies `'44'` or `'OK'`.

### `tools/elm327_emulator.py` ↔ OBD Client
- Protocol: TCP line-delimited ASCII commands ending with `\r` or `\n`.
- Prompt: `>` after each response.
- Commands:
  - `AT*` commands: return `OK\r\n>` or configuration string; unrecognized AT commands return `?\r\n>`; `ATZ`/`ATWS` resets configuration.
  - Spaced commands: interior whitespace ignored (`01 00` -> `0100`).
  - `0100`: `SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>`
  - `0120`: `41 20 80 02 02 01\r\n>`
  - `0140`: `41 40 44 04 00 14\r\n>` (advertises PIDs 0142, 0146, 015C, 015E)
  - `0104`, `0105`, `010C`, `010D`, `010F`, `0110`, `0111`, `015E`: formatted Mode 01 hex payloads.
  - Dedicated DFCO coast-down phase: when speed > 20 km/h, RPM > 1300, throttle = 0.0%, and load < 15.0%, PID `0111` emits `41 11 00\r\n>` and PID `015E` emits `41 5E 00 00\r\n>`.
  - `03`: `43 02 01 71 03 00\r\n>` (or active DTC list, `43 00\r\n>` if empty)
  - `07`: `47 01 04 20\r\n>` (or pending DTC list, `47 00\r\n>` if empty)
  - `04`: `44\r\n>` and resets DTC list to empty.

## Code Layout
- `lib/obd/`: OBD connection, ELM command processor, PID decoders, polling controller.
- `lib/services/trip/`: `fuel_calculator.dart`, `trip_history_service.dart`.
- `lib/services/dtc/`: `dtc_decoder.dart`, `dtc_service.dart`, `dtc_database.dart`.
- `lib/providers/`: `obd_provider.dart`, `trip_provider.dart`.
- `tools/`: `elm327_emulator.py`.
- `test/`: Unit and widget tests mirroring `lib/` structure.
- `test_e2e/`: Opaque-box E2E test suite covering Tiers 1-4.
