#!/usr/bin/env python3
"""
Adversarial Physics Oracle & Differential Fuzzer for Suzuki Swift 3 M15A Fuel Calculations.
Verifies stoichiometric physics, DFCO boundary conditions, and fuzz resilience.
"""

import sys
import math
import random

# Theoretical physical constants for Suzuki Swift 3 M15A
M15A_DISPLACEMENT_LITERS = 1.5
GASOLINE_STOICHIOMETRIC_AFR = 14.7
GASOLINE_DENSITY_G_PER_L = 820.0
AIR_GRAMS_PER_FUEL_LITER = GASOLINE_STOICHIOMETRIC_AFR * GASOLINE_DENSITY_G_PER_L  # 12054.0

def calculate_fuel_flow_liters_per_hour(
    rpm: int,
    engine_load_percent: float = 25.0,
    maf_grams_per_second: float = None,
    direct_fuel_rate_l_per_hour: float = None,
    throttle_position_percent: float = 0.0,
    speed_km_h: float = 0,
    short_term_fuel_trim_percent: float = 0.0,
    long_term_fuel_trim_percent: float = 0.0,
    displacement_liters: float = M15A_DISPLACEMENT_LITERS,
    air_fuel_ratio: float = GASOLINE_STOICHIOMETRIC_AFR,
    fuel_density_grams_per_liter: float = GASOLINE_DENSITY_G_PER_L,
    calibration_factor: float = 1.0,
) -> float:
    if rpm <= 0:
        return 0.0

    # DFCO Evaluation:
    # Closed throttle: relative (< 1.0%) or physical absolute (10.0% - 14.0%)
    is_throttle_closed = (throttle_position_percent < 1.0) or (10.0 <= throttle_position_percent <= 14.0)
    if speed_km_h > 20.0 and rpm > 1300 and is_throttle_closed and engine_load_percent < 18.0:
        return 0.0

    # Tier 1: Direct ECU Fuel Rate (Mode 01 PID 015E)
    if direct_fuel_rate_l_per_hour is not None and direct_fuel_rate_l_per_hour > 0:
        rate = direct_fuel_rate_l_per_hour * calibration_factor
        return max(0.0, min(60.0, rate))

    # Fuel Trim Compensation
    raw_trim_mult = 1.0 + ((short_term_fuel_trim_percent + long_term_fuel_trim_percent) / 100.0)
    trim_multiplier = max(0.5, min(1.5, raw_trim_mult))
    air_grams_per_liter = air_fuel_ratio * fuel_density_grams_per_liter

    # Tier 2: MAF Sensor (Mode 01 PID 0110)
    if maf_grams_per_second is not None and maf_grams_per_second > 0:
        fuel_l_per_hour = (maf_grams_per_second * 3600.0) / air_grams_per_liter * trim_multiplier
        return max(0.0, min(60.0, fuel_l_per_hour * calibration_factor))

    # Tier 3: Speed-density fallback
    load = max(10.0, min(100.0, engine_load_percent))
    air_grams_per_sec = (rpm * displacement_liters * (load / 100.0)) / 125.0
    fuel_l_per_hour = (air_grams_per_sec * 3600.0) / air_grams_per_liter * trim_multiplier
    return max(0.0, min(60.0, fuel_l_per_hour * calibration_factor))

def calculate_liters_per_100km(fuel_flow_liters_per_hour: float, speed_km_h: float) -> float:
    if speed_km_h <= 0 or fuel_flow_liters_per_hour <= 0:
        return 0.0
    val = (fuel_flow_liters_per_hour / speed_km_h) * 100.0
    return max(0.0, min(99.9, val))

def test_stoichiometric_physics_oracle():
    print("--- [1] STOICHIOMETRIC PHYSICS ORACLE VERIFICATION ---")
    # Verify constant derivation
    expected_air_per_liter = 14.7 * 820.0  # 12054.0 g air / L fuel
    assert math.isclose(AIR_GRAMS_PER_FUEL_LITER, 12054.0), "Air grams per fuel liter mismatch"

    # MAF theoretical flow check: 1 g/s air -> 3600 g/h air -> 3600 / 12054 ≈ 0.298656 L/h fuel
    base_flow_1g = calculate_fuel_flow_liters_per_hour(rpm=2000, maf_grams_per_second=1.0)
    expected_1g = 3600.0 / 12054.0
    assert math.isclose(base_flow_1g, expected_1g, rel_tol=1e-5), f"Expected {expected_1g}, got {base_flow_1g}"

    # Verify linear proportionality across MAF range [0.1 to 150.0] g/s
    for maf in [0.5, 1.0, 2.3, 5.0, 10.0, 25.0, 50.0, 100.0]:
        flow = calculate_fuel_flow_liters_per_hour(rpm=2000, maf_grams_per_second=maf)
        theoretical = (maf * 3600.0) / 12054.0
        assert math.isclose(flow, min(60.0, theoretical), rel_tol=1e-5)

    # Fuel Trim Linearity: +10% trim must equal exactly 1.10 * base_flow
    flow_nominal = calculate_fuel_flow_liters_per_hour(rpm=2000, maf_grams_per_second=10.0)
    flow_plus_10 = calculate_fuel_flow_liters_per_hour(
        rpm=2000, maf_grams_per_second=10.0, short_term_fuel_trim_percent=10.0
    )
    assert math.isclose(flow_plus_10, flow_nominal * 1.10, rel_tol=1e-5), "Positive trim proportionality failure"

    # Negative trim Linearity: -10% trim must equal exactly 0.90 * base_flow
    flow_minus_10 = calculate_fuel_flow_liters_per_hour(
        rpm=2000, maf_grams_per_second=10.0, short_term_fuel_trim_percent=-10.0
    )
    assert math.isclose(flow_minus_10, flow_nominal * 0.90, rel_tol=1e-5), "Negative trim proportionality failure"

    # Calibration factor linearity
    flow_calibrated = calculate_fuel_flow_liters_per_hour(
        rpm=2000, maf_grams_per_second=10.0, calibration_factor=1.15
    )
    assert math.isclose(flow_calibrated, flow_nominal * 1.15, rel_tol=1e-5), "Calibration factor failure"

    print("Stoichiometric physics oracle: PASSED (Air/Fuel 12054 g/L, trim scaling, and linearity validated).")

def test_exact_dfco_boundary_stress():
    print("\n--- [2] EXACT DFCO BOUNDARY STRESS TEST ---")
    # Exact specified boundary edges:
    # Speed: 19.9 vs 20.1 km/h
    # RPM: 1299 vs 1301 RPM
    # Throttle: 14.0% vs 14.1%
    # Load: 17.9% vs 18.0%

    base_active = dict(
        rpm=1301,
        speed_km_h=20.1,
        throttle_position_percent=14.0,
        engine_load_percent=17.9,
        maf_grams_per_second=5.0,
        direct_fuel_rate_l_per_hour=3.0,
    )
    flow_active = calculate_fuel_flow_liters_per_hour(**base_active)
    assert flow_active == 0.0, f"Expected DFCO active (0.0), got {flow_active}"

    # Edge 1: Speed = 19.9 km/h (below 20.0 threshold) -> DFCO INACTIVE
    c1 = base_active.copy()
    c1["speed_km_h"] = 19.9
    flow_c1 = calculate_fuel_flow_liters_per_hour(**c1)
    assert flow_c1 > 0.0, f"DFCO should NOT activate at speed 19.9 km/h, got {flow_c1}"

    # Edge 1b: Speed = 20.1 km/h (above 20.0 threshold) -> DFCO ACTIVE
    c1b = base_active.copy()
    c1b["speed_km_h"] = 20.1
    flow_c1b = calculate_fuel_flow_liters_per_hour(**c1b)
    assert flow_c1b == 0.0, f"DFCO should activate at speed 20.1 km/h, got {flow_c1b}"

    # Discrete speed: 20 vs 21
    c1_int_20 = base_active.copy()
    c1_int_20["speed_km_h"] = 20
    assert calculate_fuel_flow_liters_per_hour(**c1_int_20) > 0.0, "Speed 20 must NOT trigger DFCO"
    c1_int_21 = base_active.copy()
    c1_int_21["speed_km_h"] = 21
    assert calculate_fuel_flow_liters_per_hour(**c1_int_21) == 0.0, "Speed 21 must trigger DFCO"

    # Edge 2: RPM = 1299 RPM (below 1300 threshold) -> DFCO INACTIVE
    c2 = base_active.copy()
    c2["rpm"] = 1299
    flow_c2 = calculate_fuel_flow_liters_per_hour(**c2)
    assert flow_c2 > 0.0, f"DFCO should NOT activate at 1299 RPM, got {flow_c2}"

    # Edge 2b: RPM = 1301 RPM (above 1300 threshold) -> DFCO ACTIVE
    c2b = base_active.copy()
    c2b["rpm"] = 1301
    flow_c2b = calculate_fuel_flow_liters_per_hour(**c2b)
    assert flow_c2b == 0.0, f"DFCO should activate at 1301 RPM, got {flow_c2b}"

    # Edge 2c: RPM = 1300 RPM (exact threshold rpm > 1300) -> DFCO INACTIVE
    c2c = base_active.copy()
    c2c["rpm"] = 1300
    flow_c2c = calculate_fuel_flow_liters_per_hour(**c2c)
    assert flow_c2c > 0.0, f"DFCO should NOT activate at exactly 1300 RPM, got {flow_c2c}"

    # Edge 3: Throttle = 14.0% (inside physical closed stop <= 14.0%) -> DFCO ACTIVE
    c3 = base_active.copy()
    c3["throttle_position_percent"] = 14.0
    flow_c3 = calculate_fuel_flow_liters_per_hour(**c3)
    assert flow_c3 == 0.0, f"DFCO should activate at throttle 14.0%, got {flow_c3}"

    # Edge 3b: Throttle = 14.1% (outside closed stop > 14.0%) -> DFCO INACTIVE
    c3b = base_active.copy()
    c3b["throttle_position_percent"] = 14.1
    flow_c3b = calculate_fuel_flow_liters_per_hour(**c3b)
    assert flow_c3b > 0.0, f"DFCO should NOT activate at throttle 14.1%, got {flow_c3b}"

    # Edge 3c: Throttle relative edges: 0.9% (active) vs 1.0% (inactive) vs 9.9% (inactive) vs 10.0% (active)
    c3c_09 = base_active.copy()
    c3c_09["throttle_position_percent"] = 0.9
    assert calculate_fuel_flow_liters_per_hour(**c3c_09) == 0.0, "Throttle 0.9% should activate DFCO"

    c3c_10 = base_active.copy()
    c3c_10["throttle_position_percent"] = 1.0
    assert calculate_fuel_flow_liters_per_hour(**c3c_10) > 0.0, "Throttle 1.0% should NOT activate DFCO"

    c3c_99 = base_active.copy()
    c3c_99["throttle_position_percent"] = 9.9
    assert calculate_fuel_flow_liters_per_hour(**c3c_99) > 0.0, "Throttle 9.9% should NOT activate DFCO"

    c3c_100 = base_active.copy()
    c3c_100["throttle_position_percent"] = 10.0
    assert calculate_fuel_flow_liters_per_hour(**c3c_100) == 0.0, "Throttle 10.0% should activate DFCO"

    # Edge 4: Load = 17.9% (below 18.0% threshold) -> DFCO ACTIVE
    c4 = base_active.copy()
    c4["engine_load_percent"] = 17.9
    flow_c4 = calculate_fuel_flow_liters_per_hour(**c4)
    assert flow_c4 == 0.0, f"DFCO should activate at load 17.9%, got {flow_c4}"

    # Edge 4b: Load = 18.0% (at or above 18.0% threshold) -> DFCO INACTIVE
    c4b = base_active.copy()
    c4b["engine_load_percent"] = 18.0
    flow_c4b = calculate_fuel_flow_liters_per_hour(**c4b)
    assert flow_c4b > 0.0, f"DFCO should NOT activate at load 18.0%, got {flow_c4b}"

    # Edge 4c: Load = 18.1% (above threshold) -> DFCO INACTIVE
    c4c = base_active.copy()
    c4c["engine_load_percent"] = 18.1
    flow_c4c = calculate_fuel_flow_liters_per_hour(**c4c)
    assert flow_c4c > 0.0, f"DFCO should NOT activate at load 18.1%, got {flow_c4c}"

    print("DFCO Boundary Stress Tests: ALL PASSED (Speed, RPM, Throttle, Load strict boundary activation confirmed).")

def test_fuzzing_and_extremes(iterations=100_000):
    print(f"\n--- [3] ADVERSARIAL FUZZING & EXTREME VALUES ({iterations:,} iterations) ---")
    random.seed(42)

    nan_count = 0
    inf_count = 0
    flow_clamp_violations = 0
    economy_clamp_violations = 0

    for i in range(iterations):
        # Sample across extreme ranges including negatives and beyond-physical values
        rpm = random.choice([
            random.randint(-1000, 0),
            random.randint(0, 8000),
            random.randint(8001, 50000)
        ])
        speed = random.choice([
            random.uniform(-50.0, 0.0),
            random.uniform(0.0, 250.0),
            random.uniform(251.0, 500.0)
        ])
        maf = random.choice([
            None,
            random.uniform(-50.0, 0.0),
            random.uniform(0.0, 300.0),
            random.uniform(300.0, 10000.0)
        ])
        direct_fuel = random.choice([
            None,
            random.uniform(-20.0, 0.0),
            random.uniform(0.0, 60.0),
            random.uniform(60.1, 500.0)
        ])
        throttle = random.uniform(-20.0, 150.0)
        load = random.uniform(-20.0, 150.0)
        stft = random.uniform(-100.0, 100.0)
        ltft = random.uniform(-100.0, 100.0)
        cal = random.choice([0.8, 1.0, 1.2, 1.5])

        flow = calculate_fuel_flow_liters_per_hour(
            rpm=rpm,
            engine_load_percent=load,
            maf_grams_per_second=maf,
            direct_fuel_rate_l_per_hour=direct_fuel,
            throttle_position_percent=throttle,
            speed_km_h=speed,
            short_term_fuel_trim_percent=stft,
            long_term_fuel_trim_percent=ltft,
            calibration_factor=cal,
        )

        economy = calculate_liters_per_100km(flow, speed)

        if math.isnan(flow) or math.isnan(economy):
            nan_count += 1
        if math.isinf(flow) or math.isinf(economy):
            inf_count += 1
        if not (0.0 <= flow <= 60.0):
            flow_clamp_violations += 1
        if not (0.0 <= economy <= 99.9):
            economy_clamp_violations += 1

    print(f"Iterations tested: {iterations:,}")
    print(f"NaN count: {nan_count}")
    print(f"Inf count: {inf_count}")
    print(f"Flow clamp violations [0.0, 60.0]: {flow_clamp_violations}")
    print(f"Economy clamp violations [0.0, 99.9]: {economy_clamp_violations}")

    assert nan_count == 0, f"Found {nan_count} NaNs!"
    assert inf_count == 0, f"Found {inf_count} Infs!"
    assert flow_clamp_violations == 0, f"Found {flow_clamp_violations} flow clamp violations!"
    assert economy_clamp_violations == 0, f"Found {economy_clamp_violations} economy clamp violations!"
    print("Fuzzing & Extremes: ALL 100,000 COMBINATIONS PASSED DEFENSIVE INVARIANTS.")

if __name__ == "__main__":
    test_stoichiometric_physics_oracle()
    test_exact_dfco_boundary_stress()
    test_fuzzing_and_extremes()
    print("\n>>> ALL ADVERSARIAL CHALLENGES EMPIRICALLY PASSED! <<<")
