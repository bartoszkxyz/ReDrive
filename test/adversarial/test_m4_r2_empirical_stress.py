#!/usr/bin/env python3
"""
Empirical stress-testing and adversarial challenge suite for Milestone M4 Round 2:
Offline Emulation Pipeline (tools/elm327_emulator.py & test/emulator/test_elm327_emulator.py).

Written by challenger_m4_r2.
"""

import math
import os
import socket
import subprocess
import sys
import threading
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tools.elm327_emulator import SuzukiSwiftSimulator, handle_client


class TestM4R2DfcoCoastDownEmpirical(unittest.TestCase):
    """Stress-test and empirically assert the DFCO coast-down phase and 60s cycle."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_full_60s_drive_cycle_invariants(self):
        """Sample all 600 decisecond intervals (0.1s step) of the 60s cycle:
        - Phase 1 (0-10s): Idle: speed == 0, rpm in [720, 780], throttle == 12.0%, load == 20.0%, fuel rate > 0
        - Phase 2 (10-25s): Acceleration: speed 0 -> 60, rpm 800 -> 2800, throttle 20 -> 45%, load 35 -> 65%
        - Phase 3 (25-40s): Cruise: speed ~ 60, rpm ~ 2000, throttle ~ 18%, load ~ 28%
        - Phase 4 (40-52s): Dedicated DFCO Coast-Down:
            - throttle_pct == 0.0% STRICTLY for all samples
            - PID 0111 returns 41 11 00 STRICTLY
            - speed > 20 km/h STRICTLY (60 down to 32 km/h)
            - rpm > 1300 RPM STRICTLY (2500 down to 1400 RPM)
            - load_pct < 15.0% STRICTLY (12.0 down to 9.0%)
            - PID 015E returns '41 5E 00 00\r\n>' STRICTLY for all samples
        - Phase 5 (52-60s): Braking to Stop: speed 32 -> 0, throttle == 8.0%, load == 18.0%
        """
        phase4_samples = 0
        phase1_samples = 0
        phase2_samples = 0
        phase3_samples = 0
        phase5_samples = 0

        # Scan exactly one 60s period with 0.1s precision
        for step in range(600):
            t = step * 0.1
            self.sim.start_time = time.time() - t
            vals = self.sim.get_dynamic_values()

            if t < 10.0:
                phase1_samples += 1
                self.assertEqual(vals["speed"], 0, f"Idle speed at t={t} must be 0")
                self.assertTrue(720 <= vals["rpm"] <= 780, f"Idle RPM at t={t}: {vals['rpm']}")
                self.assertEqual(vals["throttle_pct"], 12.0)
                self.assertFalse("41 5E 00 00" in self.sim.process_command("015E"))
            elif t < 25.0:
                phase2_samples += 1
                self.assertTrue(0 <= vals["speed"] <= 60)
                self.assertTrue(800 <= vals["rpm"] <= 2800)
                self.assertTrue(20.0 <= vals["throttle_pct"] <= 45.0)
                self.assertFalse("41 5E 00 00" in self.sim.process_command("015E"))
            elif t < 40.0:
                phase3_samples += 1
                self.assertTrue(55 <= vals["speed"] <= 65)
                self.assertTrue(1900 <= vals["rpm"] <= 2100)
                self.assertTrue(15.0 <= vals["throttle_pct"] <= 21.0)
                self.assertFalse("41 5E 00 00" in self.sim.process_command("015E"))
            elif t < 52.0:
                phase4_samples += 1
                # DFCO phase checks
                self.assertEqual(
                    vals["throttle_pct"],
                    0.0,
                    f"DFCO throttle at t={t} must be exactly 0.0%, got {vals['throttle_pct']}",
                )
                self.assertGreater(
                    vals["speed"],
                    20,
                    f"DFCO speed at t={t} must be > 20 km/h, got {vals['speed']}",
                )
                self.assertGreater(
                    vals["rpm"],
                    1300,
                    f"DFCO rpm at t={t} must be > 1300 RPM, got {vals['rpm']}",
                )
                self.assertLess(
                    vals["load_pct"],
                    15.0,
                    f"DFCO load at t={t} must be < 15.0%, got {vals['load_pct']}",
                )

                # Hex response assertions
                throt_resp = self.sim.process_command("0111")
                self.assertEqual(
                    throt_resp,
                    "41 11 00\r\n>",
                    f"DFCO PID 0111 at t={t} must return '41 11 00', got {repr(throt_resp)}",
                )

                fuel_resp = self.sim.process_command("015E")
                self.assertEqual(
                    fuel_resp,
                    "41 5E 00 00\r\n>",
                    f"DFCO PID 015E at t={t} must return '41 5E 00 00', got {repr(fuel_resp)}",
                )
            else:
                phase5_samples += 1
                self.assertTrue(0 <= vals["speed"] <= 32)
                self.assertEqual(vals["throttle_pct"], 8.0)
                self.assertFalse("41 5E 00 00" in self.sim.process_command("015E"))

        self.assertEqual(phase1_samples, 100)
        self.assertEqual(phase2_samples, 150)
        self.assertEqual(phase3_samples, 150)
        self.assertEqual(phase4_samples, 120)  # Exactly 12 seconds in DFCO = 120 samples
        self.assertEqual(phase5_samples, 80)

    def test_dfco_boundary_transitions(self):
        """Test exact transitions entering DFCO at t=40.0s and exiting DFCO at t=52.0s."""
        # Just before DFCO: t = 39.9s (Cruise)
        self.sim.start_time = time.time() - 39.9
        vals_pre = self.sim.get_dynamic_values()
        self.assertGreater(vals_pre["throttle_pct"], 15.0)
        self.assertNotEqual(self.sim.process_command("015E"), "41 5E 00 00\r\n>")

        # Just entering DFCO: t = 40.0s
        self.sim.start_time = time.time() - 40.0
        vals_dfco_start = self.sim.get_dynamic_values()
        self.assertEqual(vals_dfco_start["throttle_pct"], 0.0)
        self.assertEqual(self.sim.process_command("0111"), "41 11 00\r\n>")
        self.assertEqual(self.sim.process_command("015E"), "41 5E 00 00\r\n>")

        # Just before DFCO exit: t = 51.9s
        self.sim.start_time = time.time() - 51.9
        vals_dfco_end = self.sim.get_dynamic_values()
        self.assertEqual(vals_dfco_end["throttle_pct"], 0.0)
        self.assertEqual(self.sim.process_command("0111"), "41 11 00\r\n>")
        self.assertEqual(self.sim.process_command("015E"), "41 5E 00 00\r\n>")

        # Just after DFCO: t = 52.0s (Braking phase)
        self.sim.start_time = time.time() - 52.0
        vals_post = self.sim.get_dynamic_values()
        self.assertEqual(vals_post["throttle_pct"], 8.0)
        self.assertNotEqual(self.sim.process_command("015E"), "41 5E 00 00\r\n>")

    def test_long_term_dfco_recurrence(self):
        """Over 10 hours (600 cycles = 36,000s), verify DFCO activates 600 times."""
        dfco_cycle_count = 0
        in_dfco = False

        for second in range(0, 36000, 5):
            self.sim.start_time = time.time() - second
            vals = self.sim.get_dynamic_values()
            is_dfco = (vals["throttle_pct"] == 0.0 and vals["speed"] > 20 and vals["rpm"] > 1300)

            if is_dfco and not in_dfco:
                dfco_cycle_count += 1
                in_dfco = True
                resp = self.sim.process_command("015E")
                self.assertEqual(resp, "41 5E 00 00\r\n>")
            elif not is_dfco:
                in_dfco = False

        # 36000 seconds / 60 seconds = 600 cycles
        self.assertEqual(dfco_cycle_count, 600)


class TestM4R2TcpSocketStress(unittest.TestCase):
    """Stress-test TCP socket with pipelined commands, bursts, and abrupt disconnects."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.server.listen(16)
        self.running = True

        def accept_loop():
            while self.running:
                try:
                    conn, addr = self.server.accept()
                    threading.Thread(
                        target=handle_client,
                        args=(conn, addr, self.sim),
                        daemon=True,
                    ).start()
                except OSError:
                    break

        self.accept_thread = threading.Thread(target=accept_loop, daemon=True)
        self.accept_thread.start()

    def tearDown(self):
        self.running = False
        try:
            self.server.close()
        except Exception:
            pass

    def test_massive_burst_concurrent_clients(self):
        """30 concurrent clients connecting and querying simultaneously."""
        num_clients = 30
        queries_per_client = 10
        errors = []

        def worker(cid):
            try:
                s = socket.create_connection(("127.0.0.1", self.port), timeout=5.0)
                for q in range(queries_per_client):
                    cmd = "0100\r" if q == 0 else ("010C\r" if q % 2 == 0 else "015E\r")
                    s.sendall(cmd.encode("ascii"))
                    resp = b""
                    while b">" not in resp:
                        chunk = s.recv(256)
                        if not chunk:
                            raise EOFError("Socket closed prematurely")
                        resp += chunk
                s.close()
            except Exception as e:
                errors.append((cid, type(e).__name__, str(e)))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_clients)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10.0)

        self.assertEqual(len(errors), 0, f"Errors in concurrent burst: {errors}")

    def test_repeated_abrupt_disconnects_stress(self):
        """50 rapid clients connecting, sending pipelined commands, and immediately
        closing/shutting down socket before responses are delivered.
        Must produce ZERO unhandled crashes in handle_client.
        """
        for i in range(50):
            s = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
            # Send multi-command pipeline
            s.sendall(b"0100\r010C\r010D\r0110\r0111\r015E\r03\r07\r04\r")
            # Immediately close or reset
            if i % 2 == 0:
                s.shutdown(socket.SHUT_RDWR)
            s.close()

        # Check server is still healthy and responsive
        time.sleep(0.2)
        s_verify = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
        s_verify.sendall(b"ATZ\r")
        resp = b""
        while b">" not in resp:
            chunk = s_verify.recv(256)
            if not chunk:
                break
            resp += chunk
        s_verify.close()
        self.assertEqual(resp, b"ELM327 v2.3\r\n>")

    def test_heavy_pipelined_commands_order_and_count(self):
        """Pipelining 12 commands in a single TCP write; verify exact order and count of responses."""
        commands = [
            "ATZ", "ATE0", "ATL0", "0100", "0120", "0140",
            "0104", "0105", "010C", "010D", "03", "07"
        ]
        pipeline_data = "".join(cmd + "\r" for cmd in commands).encode("ascii")

        s = socket.create_connection(("127.0.0.1", self.port), timeout=3.0)
        s.sendall(pipeline_data)

        resp = b""
        while resp.count(b">") < len(commands):
            chunk = s.recv(1024)
            if not chunk:
                break
            resp += chunk
        s.close()

        self.assertEqual(resp.count(b">"), len(commands))
        decoded = resp.decode("ascii", errors="replace")
        self.assertIn("ELM327 v2.3", decoded)
        self.assertIn("41 00 BE 3F B8 13", decoded)
        self.assertIn("41 20 80 02 02 01", decoded)
        self.assertIn("41 40 44 04 00 14", decoded)
        self.assertIn("41 04", decoded)
        self.assertIn("41 05", decoded)
        self.assertIn("41 0C", decoded)
        self.assertIn("41 0D", decoded)
        self.assertIn("43 02 01 71 03 00", decoded)
        self.assertIn("47 01 04 20", decoded)

    def test_rapid_reconnection_tight_loop(self):
        """100 rapid connection/query/disconnection cycles."""
        for i in range(100):
            s = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
            s.sendall(b"010C\r")
            resp = b""
            while b">" not in resp:
                chunk = s.recv(128)
                if not chunk:
                    break
                resp += chunk
            s.close()
            self.assertTrue(resp.startswith(b"41 0C"))


class TestM4R2ProtocolAndEdgeCases(unittest.TestCase):
    """Test spaced commands, unknown AT commands, Mode 03/04/07 cycles, and bitmasks."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_spaced_commands_exhaustive(self):
        """Verify various interior and exterior whitespace combinations."""
        test_cases = [
            ("01 00", "41 00 BE 3F B8 13"),
            (" 01  00 ", "41 00 BE 3F B8 13"),
            ("01 0C", "41 0C"),
            ("0 1 0 C", "41 0C"),
            ("01 0D", "41 0D"),
            ("01 11", "41 11"),
            ("01 5E", "41 5E"),
            ("0 1 5 E", "41 5E"),
            ("01 40", "41 40 44 04 00 14"),
            ("0 3", "43 02 01 71 03 00"),
            ("0 4", "44"),
            ("0 7", "47 00"),  # 04 was just executed above, so 07 should return 47 00
            ("A T Z", "ELM327 v2.3"),
            ("AT   Z", "ELM327 v2.3"),
            ("AT SP 5", "OK"),
            ("AT SP 0", "OK"),
            ("AT DP", "ISO 14230-4 (KWP FAST)"),
        ]
        for cmd, expected_substring in test_cases:
            resp = self.sim.process_command(cmd)
            self.assertIn(
                expected_substring,
                resp,
                f"Command {repr(cmd)} failed to produce {repr(expected_substring)}, got {repr(resp)}",
            )

    def test_unknown_at_commands_exhaustive(self):
        """ELM327 spec: all unsupported/unknown AT commands must return '?'."""
        unknown_commands = [
            "AT",
            "ATFOO",
            "ATBAR",
            "ATXYZ",
            "AT123",
            "AT999",
            "ATUNKNOWN",
            "ATINVALID",
            "AT??",
            "AT$$$",
            "AT@@@",
            "AT PROBE",
        ]
        for cmd in unknown_commands:
            resp = self.sim.process_command(cmd)
            self.assertEqual(resp, "?\r\n>", f"Command {repr(cmd)} did not return '?': got {repr(resp)}")

    def test_known_at_commands_validity(self):
        """Supported AT commands must succeed."""
        valid_commands = [
            ("ATZ", "ELM327 v2.3\r\n>"),
            ("ATWS", "ELM327 v2.3\r\n>"),
            ("ATE0", "OK\r\n>"),
            ("ATE1", "OK\r\n>"),
            ("ATL0", "OK\r\n>"),
            ("ATL1", "OK\r\n>"),
            ("ATS0", "OK\r\n>"),
            ("ATS1", "OK\r\n>"),
            ("ATH0", "OK\r\n>"),
            ("ATH1", "OK\r\n>"),
            ("ATAT1", "OK\r\n>"),
            ("ATSP5", "OK\r\n>"),
            ("ATSP0", "OK\r\n>"),
            ("ATDP", "ISO 14230-4 (KWP FAST)\r\n>"),
            ("ATDPN", "A5\r\n>"),
            ("ATRV", "14.1V\r\n>"),
            ("ATI", "ELM327 v2.3\r\n>"),
            ("AT@1", "ELM327 v2.3\r\n>"),
            ("ATSH7E0", "OK\r\n>"),
            ("ATCRA7E8", "OK\r\n>"),
            ("ATCAF1", "OK\r\n>"),
            ("ATST32", "OK\r\n>"),
            ("ATD", "OK\r\n>"),
            ("ATPC", "OK\r\n>"),
            ("ATAL", "OK\r\n>"),
            ("ATNL", "OK\r\n>"),
            ("ATBD", "OK\r\n>"),
        ]
        for cmd, expected in valid_commands:
            resp = self.sim.process_command(cmd)
            self.assertEqual(resp, expected, f"Command {repr(cmd)} returned {repr(resp)}")

    def test_dtc_clear_and_read_cycles(self):
        """Full Mode 03 / 04 / 07 DTC lifecycle test:
        1. Stored DTCs: P0171, P0300
        2. Pending DTC: P0420
        3. Clear with 04 -> returns 44
        4. Stored DTCs -> returns 43 00
        5. Pending DTCs -> returns 47 00
        6. Second 04 -> returns 44
        7. Stored and pending remain empty
        """
        # Step 1 & 2
        self.assertEqual(self.sim.process_command("03"), "43 02 01 71 03 00\r\n>")
        self.assertEqual(self.sim.process_command("07"), "47 01 04 20\r\n>")

        # Step 3
        self.assertEqual(self.sim.process_command("04"), "44\r\n>")

        # Step 4 & 5
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")
        self.assertEqual(self.sim.process_command("07"), "47 00\r\n>")

        # Step 6 & 7
        self.assertEqual(self.sim.process_command("04"), "44\r\n>")
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")
        self.assertEqual(self.sim.process_command("07"), "47 00\r\n>")

    def test_mode0140_bitmask_mathematical_validation(self):
        """Validate SAE J1979 Mode 0140 discovery bitmask structure:
        Bitmask: 44 04 00 14
        Byte 1: 0x44 = 0100 0100b -> PIDs 0x42 (Control module voltage) and 0x46 (Ambient temp)
        Byte 2: 0x04 = 0000 0100b -> PID 0x4E (Time run with MIL on) or similar
        Byte 3: 0x00
        Byte 4: 0x14 = 0001 0100b:
          - Bit 4 (0x10): PID 0x40 + 28 = PID 0x5C (Engine oil temp)
          - Bit 2 (0x04): PID 0x40 + 30 = PID 0x5E (Engine fuel rate)
        """
        resp = self.sim.process_command("0140")
        tokens = resp.strip().split()
        self.assertEqual(tokens[:2], ["41", "40"])
        bytes_hex = [int(b, 16) for b in tokens[2:6]]
        self.assertEqual(bytes_hex, [0x44, 0x04, 0x00, 0x14])

        b4 = bytes_hex[3]
        self.assertTrue(bool(b4 & 0x04), "PID 015E bit must be set in Byte 4")
        self.assertTrue(bool(b4 & 0x10), "PID 015C bit must be set in Byte 4")


class TestM4R2SubprocessIntegration(unittest.TestCase):
    """End-to-end integration test spawning tools/elm327_emulator.py as a live subprocess."""

    def test_subprocess_cli_full_handshake(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]

        proc = subprocess.Popen(
            [sys.executable, os.path.join(PROJECT_ROOT, "tools", "elm327_emulator.py"), "--port", str(port), "--delay", "0.0"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        try:
            # Wait for startup
            deadline = time.time() + 5.0
            connected = False
            while time.time() < deadline:
                try:
                    s = socket.create_connection(("127.0.0.1", port), timeout=0.5)
                    connected = True
                    s.close()
                    break
                except OSError:
                    time.sleep(0.05)
            self.assertTrue(connected, "Subprocess emulator failed to accept connections within deadline")

            # Connect and execute full handshake
            sock = socket.create_connection(("127.0.0.1", port), timeout=3.0)
            commands = [
                ("ATZ", "ELM327 v2.3"),
                ("ATE0", "OK"),
                ("ATL0", "OK"),
                ("ATH0", "OK"),
                ("ATSP5", "OK"),
                ("0100", "41 00 BE 3F B8 13"),
                ("0120", "41 20 80 02 02 01"),
                ("0140", "41 40 44 04 00 14"),
                ("010C", "41 0C"),
                ("010D", "41 0D"),
                ("0111", "41 11"),
                ("015E", "41 5E"),
                ("03", "43 02 01 71 03 00"),
                ("07", "47 01 04 20"),
                ("04", "44"),
                ("03", "43 00"),
                ("ATFOO", "?"),
            ]
            for cmd, expected in commands:
                sock.sendall((cmd + "\r").encode("ascii"))
                buf = b""
                while b">" not in buf:
                    chunk = sock.recv(256)
                    if not chunk:
                        raise EOFError(f"Premature EOF for {cmd}")
                    buf += chunk
                self.assertIn(expected, buf.decode("ascii", errors="replace"))

            sock.close()
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                proc.kill()
            if proc.stdout:
                proc.stdout.close()
            if proc.stderr:
                proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
