#!/usr/bin/env python3
"""
Adversarial challenge test suite for Milestone M4:
Offline Emulation Pipeline (tools/elm327_emulator.py and test/emulator/test_elm327_emulator.py).

Covers 4 core empirical challenge areas:
1. TCP Socket behavior under concurrent connections, reconnection, rapid commands, and pipe errors.
2. Mode 03, 04, 07 interactions, fault state lifecycle, and reset behavior.
3. PID 015E fuel rate calculation, discovery bitmask, and DFCO coast-down phase simulation.
4. Error responses and parser resilience on unknown/malformed AT and OBD commands.
"""

import math
import os
import socket
import sys
import threading
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tools.elm327_emulator import SuzukiSwiftSimulator, handle_client


class TestM4TcpSocketAdversarial(unittest.TestCase):
    """Area 1: TCP Socket behavior under concurrency, reconnection, and rapid commands."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.server.listen(10)
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

    def test_concurrent_connections_and_queries(self):
        """10 concurrent clients querying sensor telemetry simultaneously."""
        num_clients = 10
        queries_per_client = 15
        errors = []

        def worker(client_id):
            try:
                s = socket.create_connection(("127.0.0.1", self.port), timeout=4.0)
                for i in range(queries_per_client):
                    cmd = "010C\r" if i % 2 == 0 else "010D\r"
                    s.sendall(cmd.encode("ascii"))
                    resp = b""
                    while b">" not in resp:
                        chunk = s.recv(512)
                        if not chunk:
                            raise EOFError("Connection closed prematurely")
                        resp += chunk
                    self.assertTrue(resp.startswith(b"41 0C") or resp.startswith(b"41 0D"))
                s.close()
            except Exception as e:
                errors.append((client_id, type(e).__name__, str(e)))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_clients)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=8.0)

        self.assertEqual(len(errors), 0, f"Concurrent clients encountered errors: {errors}")

    def test_rapid_reconnection_burst(self):
        """Rapid successive connect-query-disconnect cycles (30 cycles)."""
        errors = []
        for i in range(30):
            try:
                s = socket.create_connection(("127.0.0.1", self.port), timeout=2.0)
                s.sendall(b"ATZ\r")
                resp = b""
                while b">" not in resp:
                    chunk = s.recv(256)
                    if not chunk:
                        break
                    resp += chunk
                s.close()
                if b"ELM327 v2.3" not in resp:
                    errors.append((i, "Unexpected response", resp))
            except Exception as e:
                errors.append((i, type(e).__name__, str(e)))

        self.assertEqual(len(errors), 0, f"Rapid reconnection failed: {errors}")

    def test_pipelined_rapid_commands(self):
        """Pipelining 5 distinct commands into a single TCP write buffer."""
        s = socket.create_connection(("127.0.0.1", self.port), timeout=3.0)
        s.sendall(b"0104\r0105\r010C\r010D\r03\r")

        resp = b""
        while resp.count(b">") < 5:
            chunk = s.recv(1024)
            if not chunk:
                break
            resp += chunk
        s.close()

        self.assertEqual(resp.count(b">"), 5, "Expected 5 prompts for 5 pipelined commands")
        self.assertIn(b"41 04", resp)
        self.assertIn(b"41 05", resp)
        self.assertIn(b"41 0C", resp)
        self.assertIn(b"41 0D", resp)
        self.assertIn(b"43 02", resp)

    def test_chunked_byte_by_byte_stream(self):
        """Sending a command fragmented into single-byte TCP packets."""
        s = socket.create_connection(("127.0.0.1", self.port), timeout=3.0)
        for b in [b"0", b"1", b"0", b"C", b"\r"]:
            s.sendall(b)
            time.sleep(0.01)

        resp = b""
        while b">" not in resp:
            chunk = s.recv(256)
            if not chunk:
                break
            resp += chunk
        s.close()

        self.assertTrue(resp.startswith(b"41 0C"), f"Unexpected chunked response: {resp}")

    def test_broken_pipe_unhandled_exception(self):
        """Empirical vulnerability check: handle_client catches only ConnectionResetError,

        not BrokenPipeError. When pipelined commands are sent and the client abruptly
        closes before reading all replies, the second sendall raises BrokenPipeError.
        """
        thread_error = []

        def target_with_err(conn, addr, sim):
            try:
                handle_client(conn, addr, sim)
            except Exception as e:
                thread_error.append(e)

        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        p = server.getsockname()[1]
        server.listen(1)

        def accept_one():
            try:
                c, a = server.accept()
                target_with_err(c, a, self.sim)
            except Exception:
                pass

        t = threading.Thread(target=accept_one, daemon=True)
        t.start()

        client = socket.create_connection(("127.0.0.1", p))
        client.sendall(b"0100\r010C\r")
        client.shutdown(socket.SHUT_RDWR)
        client.close()

        time.sleep(0.4)
        server.close()

        # In patched emulator, BrokenPipeError / ConnectionError is handled cleanly in handle_client
        self.assertEqual(
            len(thread_error),
            0,
            f"BrokenPipeError or other error escaped handle_client: {thread_error}",
        )


class TestM4DtcInteractions(unittest.TestCase):
    """Area 2: Mode 03, 04, 07 interactions and fault state lifecycle."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_mode03_initial_stored_codes(self):
        res = self.sim.process_command("03")
        self.assertEqual(res, "43 02 01 71 03 00\r\n>")

    def test_mode07_initial_pending_codes(self):
        res = self.sim.process_command("07")
        self.assertEqual(res, "47 01 04 20\r\n>")

    def test_mode04_clears_stored_and_pending_codes(self):
        # 1. Clear codes
        res_clear = self.sim.process_command("04")
        self.assertEqual(res_clear, "44\r\n>")

        # 2. Verify Mode 03 returns 43 00 (empty)
        res_m03 = self.sim.process_command("03")
        self.assertEqual(res_m03, "43 00\r\n>")

        # 3. Verify Mode 07 returns 47 00 (empty)
        res_m07 = self.sim.process_command("07")
        self.assertEqual(res_m07, "47 00\r\n>")

    def test_repeated_mode04_idempotent(self):
        self.sim.process_command("04")
        res2 = self.sim.process_command("04")
        self.assertEqual(res2, "44\r\n>")
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")

    def test_atz_does_not_restore_dtcs(self):
        """ATZ in ELM327 resets chip, but simulator does not restore cleared DTCs."""
        self.sim.process_command("04")
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")
        self.sim.process_command("ATZ")
        # Simulator keeps DTCs cleared across ATZ
        self.assertEqual(self.sim.process_command("03"), "43 00\r\n>")

    def test_atz_resets_configuration(self):
        """ATZ should reset protocol/headers/spaces to default values."""
        self.sim.process_command("ATH1")
        self.sim.process_command("ATS0")
        self.sim.process_command("ATSP5")
        self.assertTrue(self.sim.headers)
        self.assertFalse(self.sim.spaces)
        self.assertEqual(self.sim.protocol, 5)

        self.sim.process_command("ATZ")
        self.assertFalse(self.sim.headers, "Simulator failed to reset headers on ATZ")
        self.assertTrue(self.sim.spaces, "Simulator failed to reset spaces on ATZ")
        self.assertEqual(self.sim.protocol, 0, "Simulator failed to reset protocol on ATZ")


class TestM4Pid015eAndDfco(unittest.TestCase):
    """Area 3: PID 015E fuel rate and DFCO coast-down phase simulation."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_pid_015e_fuel_rate_calculation(self):
        """PID 015E derives L/h from MAF with 14.7 AFR and 820 g/L density."""
        vals = self.sim.get_dynamic_values()
        expected_lph = vals["maf"] * 3600.0 / (14.7 * 820.0)
        expected_raw = int(expected_lph * 20)

        res = self.sim.process_command("015E").split()
        actual_raw = (int(res[2], 16) << 8) | int(res[3], 16)
        self.assertAlmostEqual(actual_raw, expected_raw, delta=1)

    def test_pid_0140_supported_bitmask_advertises_015e(self):
        """Bitmask in PID 0140 response '41 40 44 04 00 14' must have Byte 4 == 0x14,
        meaning both PID 015C (0x10) and PID 015E (0x04) are advertised as supported in discovery.
        """
        res = self.sim.process_command("0140").split()
        # res: ['41', '40', '44', '04', '00', '14']
        b4 = int(res[5], 16)
        # Bit 30 in 0140 (PID 015E) corresponds to bit index 2 in byte 4: 0x04
        is_5e_supported = bool(b4 & 0x04)
        is_5c_supported = bool(b4 & 0x10)
        self.assertTrue(
            is_5e_supported,
            "PID 015E bit must be set in 0140 discovery bitmask (Byte 4 is 0x14)",
        )
        self.assertTrue(
            is_5c_supported,
            "PID 015C bit must be set in 0140 discovery bitmask (Byte 4 is 0x14)",
        )

    def test_dfco_profile_simulated(self):
        """Verify empirical presence of DFCO: throttle drops to 0.0%,
        speed > 20 km/h, rpm > 1300 RPM, and fuel rate 015E reaches 0.0 L/h (41 5E 00 00).
        """
        closed_throttle_seen = False
        zero_fuel_seen = False
        dfco_condition_seen = False

        # Scan 10,000 simulated seconds (covers multiple periods of 60s cycle)
        for t in range(0, 10000, 2):
            self.sim.start_time = time.time() - t
            vals = self.sim.get_dynamic_values()
            if vals["throttle_pct"] < 1.0:
                closed_throttle_seen = True
            if vals["speed"] > 20 and vals["rpm"] > 1300 and vals["throttle_pct"] < 1.0:
                dfco_condition_seen = True
            resp = self.sim.process_command("015E")
            if "41 5E 00 00" in resp:
                zero_fuel_seen = True

        self.assertTrue(
            closed_throttle_seen,
            "DFCO profile: throttle_pct must close to < 1% (0.0%) during coast-down",
        )
        self.assertTrue(
            dfco_condition_seen,
            "DFCO condition (speed>20, rpm>1300, throttle<1%) must occur during coast-down",
        )
        self.assertTrue(
            zero_fuel_seen,
            "DFCO profile: PID 015E fuel rate must drop to 41 5E 00 00 L/h",
        )


class TestM4ParserAndErrorResponses(unittest.TestCase):
    """Area 4: Parser resilience and error responses on malformed commands."""

    def setUp(self):
        self.sim = SuzukiSwiftSimulator(init_delay=0.0)

    def test_unknown_at_commands_return_question_mark(self):
        """Standard ELM327 returns '?' on unknown AT command."""
        for unknown_at in ["ATFOO", "ATBAR", "ATXYZ", "ATUNKNOWN", "AT12345"]:
            resp = self.sim.process_command(unknown_at)
            self.assertEqual(resp, "?\r\n>", f"Expected ? on emulator for {unknown_at}")

    def test_spaced_obd_commands_succeed(self):
        """ELM327 protocol strips interior spaces ('01 0C' -> '010C')."""
        self.assertIn("41 00", self.sim.process_command("01 00"))
        self.assertIn("41 0C", self.sim.process_command("01 0C"))
        self.assertIn("41 0D", self.sim.process_command("01 0D"))

    def test_ats0_spaces_suppression_not_implemented(self):
        """ATS0 should suppress spaces in responses, but emulator ignores self.spaces."""
        self.sim.process_command("ATS0")
        self.assertFalse(self.sim.spaces)
        resp = self.sim.process_command("010C")
        # Still contains spaces e.g. "41 0C 17 A0"
        self.assertIn(" ", resp.strip().rstrip(">").strip())


if __name__ == "__main__":
    unittest.main()
