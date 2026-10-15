# ReDrive Suzuki Swift 3 (M15A) E2E Test Infrastructure

## 1. Test Philosophy

### 1.1 Opaque-Box & Requirement-Driven Testing
The ReDrive End-to-End (E2E) testing framework treats the system under test as an opaque box driven strictly by requirements defined in `ORIGINAL_REQUEST.md` and architectural interface contracts in `PROJECT.md`. Tests interact exclusively with public API boundaries and simulated telemetry interfaces without relying on internal mock states or private implementation hooks.

Key tenets:
1. **Requirement-Driven Assertions**: Every test case verifies an observable behavior derived from automotive domain requirements (SAE J1979 Mode 01, Mode 03, Mode 04, Mode 07, SAE J2012 DTC decoding, M15A 1.5L physical engine constants, and trapezoidal metric integration).
2. **Simulated Telemetry Streams**: Rather than manipulating internal private variables, tests feed simulated ELM327 byte streams (via TCP socket loopback, `FakeObdConnection`, or live provider feeds) and verify downstream application state (`ObdData`, `ActiveTripState`, persisted trip records, and decoded trouble codes).
3. **Decoupled Architecture**: Subsystems are tested through high-level providers and services (`ObdProvider`, `TripProvider`, `FuelCalculator`, `TripHistoryService`, `DtcService`, `DtcDecoder`), ensuring test resilience against internal refactoring.

### 1.2 Progressive Testability & Dual-Track Verification
The E2E test suite adheres strictly to the **Progressive Testability Principle**:
- Tests are organized across four tiers of increasing complexity (Feature Coverage, Boundary & Corner Cases, Cross-Feature Combinations, and Real-World Scenarios).
- During early milestone execution, tests verify capabilities using entry point contracts, handling known pending milestone behaviors gracefully while establishing strict specification baselines.
- The test suite is self-contained: each test manages its own state setup, resets file stores, and cleans up timers upon completion.

### 1.3 Authoritative Output Derivation
All expected test outputs are derived from authoritative automotive physics, protocol standards, and documented specifications:
- **M15A Fuel Baseline**: Suzuki Swift 3 M15A 1.5L naturally aspirated engine displacement ($1.490\,\text{L}$ nominal $1.5\,\text{L}$), stoichiometric gasoline air-fuel ratio ($14.7:1$), gasoline density ($820\,\text{g/L}$).
  - Theoretical fuel rate formula: $\text{Fuel Rate}\,(\text{L/h}) = \frac{\text{MAF}\,(\text{g/s}) \times 3600}{14.7 \times 820} \approx \text{MAF} \times 0.29866\,\text{L/h}$.
  - Idle fuel flow ($\sim 750\,\text{RPM}$, $\text{MAF} \approx 2.5\,\text{g/s}$): $\approx 0.75\,\text{L/h}$ (validated range: $0.5$–$1.2\,\text{L/h}$).
  - Cruise fuel flow ($60\,\text{km/h}$, $2000\,\text{RPM}$, $\text{MAF} \approx 10\,\text{g/s}$): $\approx 2.99\,\text{L/h}$.
  - Fuel economy formula: $\text{L/100km} = \frac{\text{Fuel Rate}\,(\text{L/h})}{\text{Speed}\,(\text{km/h})} \times 100$.
- **Deceleration Fuel Cut-Off (DFCO)**: Active when $\text{speed} > 20\,\text{km/h}$, $\text{RPM} > 1300$, throttle $< 1.0\%$, and load $< 18.0\%$. Injectors shut off completely ($\text{Fuel Rate} = 0.0\,\text{L/h}$).
- **Trapezoidal Integration**: Distance $\Delta d = \frac{\frac{v_{t-1} + v_t}{2} \times \Delta t}{3600}\,\text{km}$; Fuel $\Delta F = \frac{\text{FuelRate} \times \Delta t}{3600}\,\text{L}$. Assertions enforce $<1.0\%$ relative error against exact analytical integrals.
- **SAE J2012 DTC Encoding**: 2-byte bitmask decoding mapping prefix bits (`00` $\to$ `P`, `01` $\to$ `C`, `10` $\to$ `B`, `11` $\to$ `U`) followed by 4 hexadecimal nibbles.

---

## 2. Feature Inventory Coverage

The E2E test suite comprehensively covers all 21 features defined in `PROJECT.md`:

| # | Feature Name | Tier | Test File | Primary Test Group / Cases | Pass / Fail Validation Criteria |
|---|--------------|------|-----------|---------------------------|---------------------------------|
| 1 | Toolchain & Test Runner Setup | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart` | Toolchain & Pipeline Readiness | Runner executes clean Dart VM headless test suite with 0 failures |
| 2 | Mode 01 PID Telemetry Ingestion | Tier 1 | `test/e2e/tier1_feature_coverage_test.dart` | Area A: Telemetry & Fuel | Ingests Speed, RPM, Coolant, Load, Throttle, MAF hex responses into ObdData |
| 3 | Intake Air Temp (IAT) Pipeline | Tier 1 | `test/e2e/tier1_feature_coverage_test.dart` | Area A: Telemetry & Fuel | Decodes PID 010F (`$A - 40$`) correctly across full temperature range |
| 4 | M15A Fuel Calibration & Density | Tier 1 | `test/e2e/tier1_feature_coverage_test.dart` | Area A: Telemetry & Fuel | Verifies 1.5L displacement, 14.7 AFR, and 820 g/L baseline calculations |
| 5 | Fuel Trim Compensation Fix | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area A: Telemetry & Fuel | Verifies STFT/LTFT modifier impact on fuel flow calculations |
| 6 | DFCO Detection & Zero-Fuel Handling | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area A: Telemetry & Fuel, Scenario 4 | Fuel rate drops to 0.0 L/h during closed-throttle deceleration in gear |
| 7 | Trip Lifecycle Auto-Detection | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area B: Trip Tracking | Automatically activates trip on RPM $\ge 400$ or speed $>0$; terminates on stop |
| 8 | Trip Discard Threshold Fix | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area B: Trip Tracking | Verifies short/urban trips persist when threshold configured or met |
| 9 | Numerical Metric Integration | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area B: Trip Tracking | Symmetrical trapezoidal integration accumulates distance and fuel within 1% |
| 10 | Trip History Persistence & Recovery | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area B: Trip Tracking, Scenario 5 | Persists and reloads trip records to JSON storage across app restart |
| 11 | In-Flight Trip Checkpoint | Tier 2, 4 | `test/e2e/tier2_boundary_corner_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area B: Trip Tracking, Scenario 5 | Preserves active trip metrics without memory loss or NaN values |
| 12 | Mode 03 Stored DTC Decoding | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area C: DTC Operations | Parses Mode 03 hex into confirmed DTCs across P, C, B, U prefixes |
| 13 | Mode 07 Pending DTC Decoding | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area C: DTC Operations | Parses Mode 07 hex into pending warning DTCs |
| 14 | ELM Response Parser Hardening | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area C: DTC Operations, Area D: Pipeline | Handles 2-token responses (`43 00`, `44`), compact hex, and spaced hex |
| 15 | Mode 04 Guarded Clear Execution | Tier 1, 3 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier3_cross_feature_combinations_test.dart` | Area C: DTC Operations, Cross-Feature | Executes Mode 04 clear command and verifies safety interlock while moving |
| 16 | Multiline DTC Support | Tier 1, 2 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier2_boundary_corner_test.dart` | Area C: DTC Operations | Correctly decodes multi-frame CAN responses with ECU header (`7E8`) |
| 17 | ELM327 Emulator Mode 03/04/07 | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area D: Emulation Pipeline | Verifies Mode 03, Mode 04, Mode 07, and PID 015E protocol emulation |
| 18 | ELM327 Emulator DFCO Profile | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area D: Emulation Pipeline, Scenario 4 | Verifies coast-down and DFCO telemetry response simulation |
| 19 | Offline Emulation Socket Pipeline | Tier 1, 4 | `test/e2e/tier1_feature_coverage_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Area D: Emulation Pipeline | Full loopback socket pipeline connecting ObdProvider to emulator server |
| 20 | Dual-Track E2E Test Suite | Tiers 1-4 | `test/e2e/` (All files) | All Tiers | Publishes comprehensive test suite and verifies all test cases pass |
| 21 | Final 100% E2E Pass & Adversarial Hardening | Tier 2, 4 | `test/e2e/tier2_boundary_corner_test.dart`, `test/e2e/tier4_real_world_scenarios_test.dart` | Boundary Cases & Scenario Stress | 100% test pass rate with 0 failures under stress and edge inputs |

---

## 3. Test Architecture & Directory Layout

### 3.1 Directory Structure
```
/workspace/test/e2e/
├── e2e_harness.dart                           # Shared test harness, mock TCP servers, telemetry generators, oracles
├── tier1_feature_coverage_test.dart           # Tier 1: Core Feature Coverage (>=5 test cases per core area)
├── tier2_boundary_corner_test.dart            # Tier 2: Boundary & Corner Cases (>=5 test cases per core area)
├── tier3_cross_feature_combinations_test.dart # Tier 3: Cross-Feature Pairwise Interactions
└── tier4_real_world_scenarios_test.dart       # Tier 4: Real-World Driving Cycles & Scenarios
```

### 3.2 Harness Components (`e2e_harness.dart`)
The E2E test harness provides reusable, deterministic utilities:
- **`MockElmTcpServer`**: An in-process RFC loopback TCP server bound to an ephemeral port (`127.0.0.1:0`), fully simulating Suzuki Swift 3 M15A ELM327 v2.3 adapter protocols (AT commands, Mode 01 sensor polling, Mode 03/07 DTCs, Mode 04 clearing, and simulated K-Line fast init delays).
- **`E2ETelemetryFeeder`**: Utility for sequentially injecting timestamped driving telemetry points into `TripProvider` or `ObdProvider`.
- **`AnalyticalOracles`**: Pure mathematical calculation functions providing authoritative ground truth for distance integration, fuel volume, and stoichiometric fuel rates.
- **`TestEnvironmentSetup`**: Fixtures for resetting mock preferences (`SharedPreferences`), clearing test trip histories, and disposing timers cleanly.

---

## 4. Test Tiers & Specifications

### 4.1 Tier 1: Feature Coverage (Core Feature Areas)
Covers baseline happy-path behaviors across all four core functional pillars:
- **Area A (Engine Telemetry & M15A Fuel Calculations)**:
  - T1.A1: Idle fuel flow calculation ($750$–$800\,\text{RPM}$) with M15A baseline parameters.
  - T1.A2: Cruise fuel flow & economy calculation ($60\,\text{km/h}$, $2000\,\text{RPM}$).
  - T1.A3: DFCO detection and zero-fuel cut-off under closed-throttle deceleration.
  - T1.A4: Direct ECU fuel rate (PID 015E) prioritization over MAF and speed-density.
  - T1.A5: Speed-density fallback calculation when MAF is absent.
  - T1.A6: Mode 010F Intake Air Temperature (IAT) sensor decoding.
- **Area B (Trip Tracking & Lifecycle Management)**:
  - T1.B1: Automatic trip start detection upon engine running ($\text{RPM} \ge 400$ or $\text{speed} > 0$).
  - T1.B2: Symmetrical trapezoidal numerical integration of traveled distance.
  - T1.B3: Instantaneous and cumulative fuel integration over elapsed time slices.
  - T1.B4: Real-time average speed and average fuel consumption calculation.
  - T1.B5: Trip serialization to JSON storage upon completion.
  - T1.B6: Trip history retrieval, deserialization, and chronological sorting.
- **Area C (DTC Operations & Diagnostics)**:
  - T1.C1: Mode 03 stored DTC decoding across Powertrain (P), Chassis (C), Body (B), and Network (U).
  - T1.C2: Mode 07 pending DTC decoding with severity and subsystem lookup.
  - T1.C3: Compact unspaced hex response decoding.
  - T1.C4: Multi-frame CAN DTC response with ECU headers (`7E8`).
  - T1.C5: Mode 04 clear command execution and fault resetting.
  - T1.C6: Clean handling of zero trouble codes (`43 00` / `NO DATA`).
- **Area D (Offline Emulation & Verification Pipeline)**:
  - T1.D1: ELM327 initialization handshake (`ATZ`, `ATE0`, `ATL0`, `ATSP0`).
  - T1.D2: Supported PID discovery and bitmask parsing (`0100`).
  - T1.D3: Continuous sensor stream polling and ObdProvider notification.
  - T1.D4: Transport disconnection and graceful recovery.
  - T1.D5: Complete end-to-end socket telemetry stream into ObdData model.

### 4.2 Tier 2: Boundary & Corner Cases
Covers stress boundaries, physical extremes, and abnormal responses:
- **Area A (Fuel & Telemetry Boundaries)**:
  - T2.A1: Zero RPM / engine off boundary (fuel rate strictly $0.0\,\text{L/h}$).
  - T2.A2: Extreme load/MAF fuel flow clamping at $60.0\,\text{L/h}$.
  - T2.A3: Stationary vehicle speed $= 0$ (fuel economy returns $0.0\,\text{L/100km}$ without division by zero).
  - T2.A4: Extreme fuel economy clamping at upper bound $99.9\,\text{L/100km}$.
  - T2.A5: DFCO threshold boundary testing (e.g. $1301\,\text{RPM}$ vs $1299\,\text{RPM}$; $21\,\text{km/h}$ vs $19\,\text{km/h}$).
  - T2.A6: Extreme fuel trim boundary clamping.
- **Area B (Trip Tracking Boundaries)**:
  - T2.B1: Zero movement / zero distance trip discard handling.
  - T2.B2: Configurable minimum trip distance threshold filtering.
  - T2.B3: Time-slice delta ($\Delta t$) clamping against clock jumps ($[0.05\,\text{s}, 15.0\,\text{s}]$).
  - T2.B4: Empty or missing trip history file handling without crash.
  - T2.B5: Rapid successive trip start and stop cycles.
- **Area C (DTC Operations Boundaries)**:
  - T2.C1: Filtering of non-fault filler byte sequences (`P0000`).
  - T2.C2: Malformed and odd-length DTC byte string robustness.
  - T2.C3: Unrecognized DTC code lookup fallback to valid default system classification.
  - T2.C4: DTC clearing stationary interlock (prevent clearing while moving).
  - T2.C5: Mode 03 / 07 query timeout and bus error handling.
- **Area D (Offline Emulation Boundaries)**:
  - T2.D1: TCP stream fragmentation (ELM response split across multiple packets).
  - T2.D2: Rapid connection flapping (connect $\to$ drop $\to$ reconnect).
  - T2.D3: Unknown ELM command error response (`?`).
  - T2.D4: Adapter error codes (`ERR01`, `BUS INIT: ERROR`).
  - T2.D5: Multi-client connection contention and socket closure.

### 4.3 Tier 3: Cross-Feature Combinations
Covers pairwise and multilateral subsystem interactions:
- T3.1: Active trip tracking concurrent with Mode 03 / Mode 07 DTC diagnostic scan without telemetry stalling.
- T3.2: Mode 04 clear safety interlock triggered when vehicle has active speed during a trip, succeeding once stopped.
- T3.3: Active trip transition into mountain coasting (DFCO), verifying distance accumulates while fuel integration pauses.
- T3.4: OBD connection loss and re-establishment during an active trip, verifying distance and fuel continuity.
- T3.5: Intake air temperature (010F) and extreme coolant temperature dynamics concurrent with fuel calculations and trip logging.
- T3.6: Trip completion and history save followed immediately by fault diagnosis and clearing.

### 4.4 Tier 4: Real-World Driving Cycles
Simulates realistic, multi-minute driving profiles based on standardized automotive drive cycles:
- **Scenario 1: Cold Start Idle & Warm-Up Driving Cycle**: Ignition on $\to$ cold fast idle ($1200\,\text{RPM}$, $25^\circ\text{C}$ coolant) $\to$ gradual warm-up to $88^\circ\text{C}$ $\to$ warm idle settle ($750\,\text{RPM}$); trip auto-starts; fuel flow transitions smoothly.
- **Scenario 2: Urban Stop-and-Go Driving Cycle**: Launch acceleration ($0 \to 45\,\text{km/h}$) $\to$ traffic light stop $\to$ idle pause $\to$ re-acceleration; validates trapezoidal distance and fuel totals within $1.0\%$ error.
- **Scenario 3: Highway Cruise Driving Cycle**: Continuous high-speed cruise ($90\,\text{km/h}$, $2500\,\text{RPM}$, $\text{MAF} \approx 16\,\text{g/s}$); fuel economy stabilizes in expected range ($5.5$–$6.5\,\text{L/100km}$).
- **Scenario 4: Mountain Descent with DFCO Driving Cycle**: Descent from $80\,\text{km/h}$ down to $30\,\text{km/h}$ with closed throttle ($0\%$) and high engine braking ($>1300\,\text{RPM}$); DFCO holds fuel rate at $0.0\,\text{L/h}$; distance increases while fuel used remains constant.
- **Scenario 5: Engine Shutdown, Trip Completion & Restart Persistence Cycle**: Vehicle stops $\to$ engine off $\to$ trip finalized and saved to `trips_history.json` $\to$ engine restart initiates fresh trip; history query recovers past trip intact.
- **Scenario 6: In-Flight Fault Trigger & Diagnostic Resolution Cycle**: High-speed cruise $\to$ ECU triggers DTCs (`P0300`, `P0171`) $\to$ diagnostics scan retrieves codes with descriptions $\to$ vehicle pulls over to stop $\to$ Mode 04 clear resets DTCs $\to$ normal driving resumes.

---

## 5. Pass / Fail Semantics

1. **Deterministic Tolerances**:
   - Numerical integration (distance and fuel consumption): $\le 1.0\%$ relative error against exact mathematical integrals.
   - Instantaneous fuel rate: $\pm 0.05\,\text{L/h}$ tolerance against stoichiometric baseline formulas.
   - DTC parsing: Exact string match for decoded codes (`P0300`, `P0171`, `P0420`, etc.).
2. **Execution Command**:
   ```bash
   flutter test test/e2e/
   ```
3. **Exit Code Semantics**:
   - `0`: All test cases passed with zero failures.
   - Non-zero: Any test assertion failure or unhandled exception fails the test suite.
