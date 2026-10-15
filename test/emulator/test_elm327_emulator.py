#!/usr/bin/env python3
"""
Test suite for tools/elm327_emulator.py.
Verifies current emulator behavior and identifies gaps against R4 acceptance criteria.
"""

import os
import socket
import subprocess
import sys
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tools.elm327_emulator import SuzukiSwiftSimulator


class TestSuzukiSwiftSimulatorUnit(unittest.TestCase):
    """Unit tests executing SuzukiSwiftSimulator.process_command directly."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_standard_at_commands(self):
        self.assertEqual(self.sim.process_command("ATZ"), "ELM327 v2.3\r\n>")
        self.assertEqual(self.sim.process_command("ATWS"), "ELM327 v2.3\r\n>")
        self.assertEqual(self.sim.process_command("ATE0"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATE1"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATL0"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATL1"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATS0"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATS1"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATH0"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATH1"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATSP0"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATSP5"), "OK\r\n>")
        self.assertEqual(self.sim.process_command("ATDP"), "ISO 14230-4 (KWP FAST)\r\n>")
        self.assertEqual(self.sim.process_command("ATDPN"), "A5\r\n>")
        self.assertEqual(self.sim.process_command("ATRV"), "14.1V\r\n>")

    def test_mode01_pid_discovery(self):
        res = self.sim.process_command("0100")
        self.assertIn("SEARCHING...", res)
        self.assertIn("BUS INIT: OK", res)
        self.assertIn("41 00 BE 3F B8 13", res)
        self.assertTrue(res.endswith("\r\n>"))

        self.assertEqual(self.sim.process_command("0120"), "41 20 80 02 02 01\r\n>")
        self.assertEqual(self.sim.process_command("0140"), "41 40 44 04 00 14\r\n>")

    def test_mode01_core_telemetry(self):
        for pid in ["0103", "0104", "0105", "0106", "0107", "010A", "010B", "010C", "010D", "010E", "010F", "0110", "0111", "012F"]:
            res = self.sim.process_command(pid)
            self.assertTrue(res.startswith(f"41 {pid[2:]} "), f"PID {pid} response unexpected: {res}")
            self.assertTrue(res.endswith("\r\n>"))

    def test_mode01_pid_0103_fuel_system_status(self):
        res = self.sim.process_command("0103")
        self.assertTrue(res.startswith("41 03 "))
        parts = res.strip().split()
        status_b1 = int(parts[2], 16)
        # Bit 1 (0x02) = closed loop, or Bit 2 (0x04) = open loop decel/power
        self.assertIn(status_b1, [0x02, 0x04])

    def test_mode01_pid_015e_fuel_rate(self):
        """PID 015E is required by Feature 17 / PROJECT.md."""
        res = self.sim.process_command("015E")
        # Currently expected to FAIL on unfixed emulator
        self.assertTrue(res.startswith("41 5E"), f"PID 015E expected '41 5E ...' but got '{res.strip()}'")

    def test_mode03_dtc_stored(self):
        """Mode 03 is required by R4 / Feature 17."""
        res = self.sim.process_command("03")
        # Currently expected to FAIL on unfixed emulator
        self.assertTrue(res.startswith("43"), f"Mode 03 expected '43 ...' but got '{res.strip()}'")

    def test_mode04_dtc_clear(self):
        """Mode 04 is required by R4 / Feature 17."""
        res = self.sim.process_command("04")
        # Currently expected to FAIL on unfixed emulator
        self.assertTrue(res.startswith("44") or "OK" in res, f"Mode 04 expected '44' or 'OK' but got '{res.strip()}'")

    def test_mode07_dtc_pending(self):
        """Mode 07 is required by Feature 17."""
        res = self.sim.process_command("07")
        # Currently expected to FAIL on unfixed emulator
        self.assertTrue(res.startswith("47"), f"Mode 07 expected '47 ...' but got '{res.strip()}'")

    def test_mode03_07_exact_payloads(self):
        self.assertEqual(self.sim.process_command("03"), "43 02 01 71 03 00\r\n>")
        self.assertEqual(self.sim.process_command("07"), "47 01 04 20\r\n>")

    def test_mode04_clear_resets_state(self):
        self.assertEqual(self.sim.process_command("04"), "44\r\n>")
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")
        self.assertEqual(self.sim.process_command("07"), "47 00\r\n>")

    def test_pid_015e_decodes_to_plausible_fuel_rate(self):
        res = self.sim.process_command("015E").split()
        a, b = int(res[2], 16), int(res[3], 16)
        lph = (256 * a + b) / 20.0
        self.assertTrue(0.1 <= lph <= 30.0, f"fuel rate {lph} L/h implausible")

    def test_dfco_coastdown_phase(self):
        """Feature 18: During DFCO coast-down phase (Phase 4: 40-52s):
        - speed > 20 km/h (decelerating 60 -> 32 km/h)
        - rpm > 1300 RPM (decelerating 2500 -> 1400 RPM)
        - throttle_pct == 0.0% (closed throttle, raw 41 11 00)
        - load_pct < 15.0%
        - PID 015E returns 41 5E 00 00 (0.0 L/h fuel cut-off)
        """
        self.sim.start_time = time.time() - 45.0
        vals = self.sim.get_dynamic_values()
        self.assertGreater(vals["speed"], 20, "Speed in DFCO must be > 20 km/h")
        self.assertGreater(vals["rpm"], 1300, "RPM in DFCO must be > 1300 RPM")
        self.assertEqual(vals["throttle_pct"], 0.0, "Throttle in DFCO must be 0.0%")
        self.assertLess(vals["load_pct"], 15.0, "Engine load in DFCO must be < 15.0%")

        # Throttle position PID 0111 -> 41 11 00
        self.assertEqual(self.sim.process_command("0111"), "41 11 00\r\n>")

        # Fuel rate PID 015E -> 41 5E 00 00
        self.assertEqual(self.sim.process_command("015E"), "41 5E 00 00\r\n>")

    def test_mode0140_advertises_pid_015e(self):
        """Mode 0140 bitmask must advertise PID 015E (byte 4 bit 2 = 0x04) and PID 015C (0x10)."""
        res = self.sim.process_command("0140")
        self.assertEqual(res, "41 40 44 04 00 14\r\n>")
        tokens = res.strip().split()
        b4 = int(tokens[5], 16)
        self.assertTrue(bool(b4 & 0x04), "PID 015E bit not set in Byte 4 of 0140")
        self.assertTrue(bool(b4 & 0x10), "PID 015C bit not set in Byte 4 of 0140")

    def test_unknown_at_command_rejection(self):
        """Unknown AT commands must return '?' per ELM327 protocol spec."""
        for cmd in ["ATFOO", "ATBAR", "AT123", "ATXYZ", "ATUNKNOWN"]:
            self.assertEqual(self.sim.process_command(cmd), "?\r\n>")

    def test_spaced_commands(self):
        """Interior spaces must be stripped: '01 00', '01 0C', 'AT Z' must succeed."""
        self.assertIn("41 00", self.sim.process_command("01 00"))
        self.assertIn("41 0C", self.sim.process_command("01 0C"))
        self.assertIn("41 0D", self.sim.process_command("01 0D"))
        self.assertEqual(self.sim.process_command("AT Z"), "ELM327 v2.3\r\n>")
        self.assertEqual(self.sim.process_command("AT SP 0"), "OK\r\n>")

    def test_atz_resets_adapter_state(self):
        """ATZ and ATWS must reset echo, linefeeds, spaces, headers, and protocol."""
        self.sim.process_command("ATH1")
        self.sim.process_command("ATS0")
        self.sim.process_command("ATSP5")
        self.assertTrue(self.sim.headers)
        self.assertFalse(self.sim.spaces)
        self.assertEqual(self.sim.protocol, 5)

        self.sim.process_command("ATZ")
        self.assertTrue(self.sim.echo)
        self.assertTrue(self.sim.linefeeds)
        self.assertTrue(self.sim.spaces)
        self.assertFalse(self.sim.headers)
        self.assertEqual(self.sim.protocol, 0)


class TestSuzukiSwiftSimulatorSocketIntegration(unittest.TestCase):
    """Integration tests running emulator in subprocess over real TCP socket."""

    @classmethod
    def setUpClass(cls):
        # Find free ephemeral port
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            cls.port = s.getsockname()[1]

        emulator_script = os.path.join(PROJECT_ROOT, "tools", "elm327_emulator.py")
        cls.proc = subprocess.Popen(
            [sys.executable, emulator_script, "--port", str(cls.port), "--delay", "0.0"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        deadline = time.time() + 10.0
        while time.time() < deadline:
            try:
                socket.create_connection(("127.0.0.1", cls.port), timeout=0.5).close()
                break
            except OSError:
                time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait()

    def _query(self, cmd: str) -> str:
        s = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
        try:
            s.sendall((cmd + "\r").encode("ascii"))
            resp = b""
            while b">" not in resp:
                chunk = s.recv(1024)
                if not chunk:
                    break
                resp += chunk
            return resp.decode("ascii", errors="replace")
        finally:
            s.close()

    def test_socket_clean_startup_and_handshake(self):
        self.assertIsNone(self.proc.poll(), "Emulator process crashed on startup")
        resp = self._query("ATZ")
        self.assertEqual(resp, "ELM327 v2.3\r\n>")

    def test_socket_mode0100_handshake(self):
        resp = self._query("0100")
        self.assertIn("SEARCHING...", resp)
        self.assertIn("41 00 BE 3F B8 13", resp)

    def test_socket_dtc_read_clear_cycle(self):
        self.assertIn("43 02 01 71 03 00", self._query("03"))
        self.assertIn("47 01 04 20", self._query("07"))
        self.assertIn("44", self._query("04"))
        self.assertIn("43 00", self._query("03"))
        self.assertIn("47 00", self._query("07"))

    def test_socket_pipelined_commands(self):
        """Pipelined commands over a single persistent TCP stream."""
        s = socket.create_connection(("127.0.0.1", self.port), timeout=3.0)
        try:
            s.sendall(b"0104\r0105\r010C\r010D\r")
            resp = b""
            while resp.count(b">") < 4:
                chunk = s.recv(512)
                if not chunk:
                    break
                resp += chunk
            self.assertEqual(resp.count(b">"), 4)
            self.assertIn(b"41 04", resp)
            self.assertIn(b"41 05", resp)
            self.assertIn(b"41 0C", resp)
            self.assertIn(b"41 0D", resp)
        finally:
            s.close()

    def test_socket_abrupt_disconnect_handling(self):
        """Server handles abrupt client disconnects without worker crash."""
        for _ in range(5):
            s = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
            s.sendall(b"0100\r010C\r010D\r")
            s.shutdown(socket.SHUT_RDWR)
            s.close()

        # Follow-up query verifies server is healthy
        resp = self._query("ATZ")
        self.assertEqual(resp, "ELM327 v2.3\r\n>")


if __name__ == "__main__":
    unittest.main()
