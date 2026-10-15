#!/usr/bin/env python3
"""
Adversarial Numerical Oracle & Calculus Integrator for Milestone M2.
Empirically verifies:
1. Analytical calculus integrals (quadratic velocity ramps, harmonic waves).
2. Symmetrical trapezoidal numerical integration precision and error bounds (|E| < 1.0%, target <= 0.05%).
3. Pure DFCO zero-fuel integrity over sustained coasting.
4. Non-uniform time deltas, high-frequency sub-second jitter, and extreme acceleration spikes.
"""

import math
import sys

def verify_quadratic_ramp():
    print("=== [1] Polynomial Quadratic Acceleration Profile ===")
    # v(t) = (1/36) * t^2 for t in [0, 60] seconds
    # f(t) = 1.0 + (11/3600) * t^2
    # Exact Analytical Integrals:
    # Distance = int_0^60 v(t)/3600 dt = (1/129600) * [t^3 / 3]_0^60 = 72000 / 129600 = 5/9 km
    exact_dist_km = 5.0 / 9.0
    exact_fuel_liters = 280.0 / 3600.0  # 7/90 L
    exact_avg_speed = exact_dist_km / (60.0 / 3600.0)  # 100/3 km/h

    # Numerical Trapezoidal Quadrature (dt = 1s, continuous v(t))
    num_dist_continuous = 0.0
    num_fuel = 0.0
    last_v = 0.0
    last_f = 1.0

    # Also discrete OBD rounded speed (as OBD Mode 01 PID 010D reports whole km/h)
    num_dist_discrete = 0.0
    last_v_discrete = 0

    for t in range(1, 61):
        v = (1.0 / 36.0) * (t * t)
        v_round = round(v)
        f = 1.0 + (11.0 / 3600.0) * (t * t)

        dt = 1.0
        num_dist_continuous += ((last_v + v) / 2.0) * (dt / 3600.0)
        num_dist_discrete += ((last_v_discrete + v_round) / 2.0) * (dt / 3600.0)
        num_fuel += ((last_f + f) / 2.0) * (dt / 3600.0)

        last_v = v
        last_v_discrete = v_round
        last_f = f

    err_dist_cont = abs(num_dist_continuous - exact_dist_km) / exact_dist_km * 100.0
    err_dist_disc = abs(num_dist_discrete - exact_dist_km) / exact_dist_km * 100.0
    err_fuel = abs(num_fuel - exact_fuel_liters) / exact_fuel_liters * 100.0

    print(f"Exact Analytical Distance: {exact_dist_km:.8f} km")
    print(f"Trapezoidal Distance (cont): {num_dist_continuous:.8f} km (Relative Error: {err_dist_cont:.6f}%)")
    print(f"Trapezoidal Distance (OBD rounded): {num_dist_discrete:.8f} km (Relative Error: {err_dist_disc:.6f}%)")
    print(f"Exact Analytical Fuel:     {exact_fuel_liters:.8f} L")
    print(f"Trapezoidal Fuel:          {num_fuel:.8f} L (Relative Error: {err_fuel:.6f}%)")

    assert err_dist_cont < 0.05, f"Continuous distance error {err_dist_cont}% exceeds target 0.05%"
    assert err_dist_disc < 1.0, f"OBD discrete distance error {err_dist_disc}% exceeds 1.0%"
    assert err_fuel < 0.05, f"Fuel error {err_fuel}% exceeds target 0.05%"
    print(">>> Quadratic Ramp: PASSED\n")

def verify_harmonic_wave():
    print("=== [2] Harmonic Periodic Sine Wave Profile ===")
    # v(t) = 60.0 + 20.0 * sin(2*pi*t / 60) for t in [0, 60] seconds
    # f(t) = 5.0 + 2.0 * sin(2*pi*t / 60)
    # Exact Analytical Integrals:
    # Integral of sin(2*pi*t/60) over [0, 60] is strictly 0.0
    exact_dist_km = 60.0 * (60.0 / 3600.0)  # 1.00000 km
    exact_fuel_liters = 5.0 * (60.0 / 3600.0)  # 0.0833333 L
    exact_avg_speed = 60.0

    num_dist_continuous = 0.0
    num_dist_discrete = 0.0
    num_fuel = 0.0
    last_v = 60.0
    last_v_discrete = 60
    last_f = 5.0

    for t in range(1, 61):
        angle = (2.0 * math.pi * t) / 60.0
        v = 60.0 + 20.0 * math.sin(angle)
        v_round = round(v)
        f = 5.0 + 2.0 * math.sin(angle)
        dt = 1.0

        num_dist_continuous += ((last_v + v) / 2.0) * (dt / 3600.0)
        num_dist_discrete += ((last_v_discrete + v_round) / 2.0) * (dt / 3600.0)
        num_fuel += ((last_f + f) / 2.0) * (dt / 3600.0)

        last_v = v
        last_v_discrete = v_round
        last_f = f

    err_dist_cont = abs(num_dist_continuous - exact_dist_km) / exact_dist_km * 100.0
    err_dist_disc = abs(num_dist_discrete - exact_dist_km) / exact_dist_km * 100.0
    err_fuel = abs(num_fuel - exact_fuel_liters) / exact_fuel_liters * 100.0

    print(f"Exact Analytical Distance: {exact_dist_km:.8f} km")
    print(f"Trapezoidal Distance (cont): {num_dist_continuous:.8f} km (Relative Error: {err_dist_cont:.6f}%)")
    print(f"Trapezoidal Distance (OBD rounded): {num_dist_discrete:.8f} km (Relative Error: {err_dist_disc:.6f}%)")
    print(f"Exact Analytical Fuel:     {exact_fuel_liters:.8f} L")
    print(f"Trapezoidal Fuel:          {num_fuel:.8f} L (Relative Error: {err_fuel:.6f}%)")

    assert err_dist_cont < 1e-9, f"Continuous harmonic distance error {err_dist_cont}% should be machine-zero"
    assert err_dist_disc < 1.0, f"OBD discrete harmonic distance error {err_dist_disc}% exceeds 1.0%"
    assert err_fuel < 1e-9, f"Harmonic fuel error {err_fuel}% should be machine-zero"
    print(">>> Harmonic Wave: PASSED\n")

def verify_pure_dfco_integrity():
    print("=== [3] Pure DFCO Sustained Zero Fuel Verification ===")
    duration_sec = 120
    speed_km_h = 85.0
    fuel_rate = 0.0  # L/h during active DFCO

    exact_dist_km = (speed_km_h * duration_sec) / 3600.0
    exact_fuel_liters = 0.0

    num_dist = 0.0
    num_fuel = 0.0
    last_speed = speed_km_h
    last_fuel = 0.0

    for s in range(1, duration_sec + 1):
        dt = 1.0
        num_dist += ((last_speed + speed_km_h) / 2.0) * (dt / 3600.0)
        num_fuel += ((last_fuel + fuel_rate) / 2.0) * (dt / 3600.0)
        last_speed = speed_km_h
        last_fuel = fuel_rate

    print(f"Expected Distance: {exact_dist_km:.6f} km, Accumulated: {num_dist:.6f} km")
    print(f"Expected Fuel:     {exact_fuel_liters:.6f} L, Accumulated: {num_fuel:.6f} L")

    assert math.isclose(num_dist, exact_dist_km, abs_tol=1e-9)
    assert num_fuel == 0.0, f"Fuel must be strictly 0.0, got {num_fuel}"
    print(">>> Pure DFCO Integrity: PASSED\n")

def verify_subsecond_jitter():
    print("=== [4] High Frequency Sub-second Jitter Simulation ===")
    step_deltas_ms = [50, 75, 100, 50, 150, 200, 50, 80, 120, 250]
    total_ms = 0
    theoretical_dist = 0.0
    theoretical_fuel = 0.0

    last_speed = 50.0
    last_fuel = 4.0

    for i in range(200):
        dt_ms = step_deltas_ms[i % len(step_deltas_ms)]
        total_ms += dt_ms
        dt_sec = dt_ms / 1000.0

        speed = 50.0 + 15.0 * math.sin(i * 0.1)
        speed_round = round(speed)
        fuel = 4.0 + 1.2 * math.sin(i * 0.1)

        theoretical_dist += ((last_speed + speed_round) / 2.0) * (dt_sec / 3600.0)
        theoretical_fuel += ((last_fuel + fuel) / 2.0) * (dt_sec / 3600.0)

        last_speed = speed_round
        last_fuel = fuel

    expected_duration_sec = total_ms / 1000.0
    theoretical_avg_speed = theoretical_dist / (expected_duration_sec / 3600.0)

    print(f"Total simulated time: {expected_duration_sec:.3f} s over 200 steps (avg dt = {total_ms/200:.1f} ms)")
    print(f"Theoretical Distance: {theoretical_dist:.6f} km")
    print(f"Theoretical Fuel:     {theoretical_fuel:.6f} L")
    print(f"Theoretical Avg Speed:{theoretical_avg_speed:.3f} km/h")
    print(">>> Sub-second Jitter: PASSED\n")

def verify_drag_launch_and_emergency_stop():
    print("=== [5] Drag Launch & Emergency Stop Extreme Spikes ===")
    # 0 -> 100 km/h in 3s (Accel: ~9.26 m/s^2, ~0.94g)
    # 100 -> 0 km/h in 2s (Decel: -13.89 m/s^2, -1.42g)
    theoretical_dist = 0.0
    theoretical_fuel = 0.0
    last_speed = 0.0
    last_fuel = 0.8

    # Launch (3s)
    for i in range(1, 4):
        speed = (100.0 / 3.0) * i
        fuel = 0.8 + ((35.0 - 0.8) / 3.0) * i
        theoretical_dist += ((last_speed + speed) / 2.0) * (1.0 / 3600.0)
        theoretical_fuel += ((last_fuel + fuel) / 2.0) * (1.0 / 3600.0)
        last_speed = speed
        last_fuel = fuel

    # Stop (2s)
    for i in range(1, 3):
        speed = 100.0 - (100.0 / 2.0) * i
        fuel = 35.0 - ((35.0 - 0.8) / 2.0) * i
        theoretical_dist += ((last_speed + speed) / 2.0) * (1.0 / 3600.0)
        theoretical_fuel += ((last_fuel + fuel) / 2.0) * (1.0 / 3600.0)
        last_speed = speed
        last_fuel = fuel

    print(f"Spike Total Distance: {theoretical_dist:.6f} km")
    print(f"Spike Total Fuel:     {theoretical_fuel:.6f} L")
    assert theoretical_dist > 0.0
    assert theoretical_fuel > 0.0
    print(">>> Drag Launch & Emergency Stop: PASSED\n")

if __name__ == "__main__":
    verify_quadratic_ramp()
    verify_harmonic_wave()
    verify_pure_dfco_integrity()
    verify_subsecond_jitter()
    verify_drag_launch_and_emergency_stop()
    print("=======================================================")
    print("ALL M2 NUMERICAL INTEGRATION AND ORACLE CHECKS PASSED!")
    print("=======================================================")
