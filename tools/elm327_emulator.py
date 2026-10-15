#!/usr/bin/env python3
"""
ELM327 OBD-II Emulator for Suzuki Swift 2007 (M15A engine).
Simulates a Vgate iCar Pro ELM327 v2.3 adapter over TCP on port 35000.

Usage:
    python3 tools/elm327_emulator.py [--port 35000] [--delay 1.0]
"""

import argparse
import math
import socket
import sys
import threading
import time

def parse_args():
    parser = argparse.ArgumentParser(description="ELM327 Suzuki Swift Emulator")
    parser.add_argument("--host", default="127.0.0.1", help="Bind IP address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=35000, help="TCP port (default: 35000)")
    parser.add_argument("--delay", type=float, default=1.0, help="Simulated K-Line ECU init delay in seconds (default: 1.0)")
    return parser.parse_args()

class SuzukiSwiftSimulator:
    def __init__(self, init_delay: float):
        self.init_delay = init_delay
        self.echo = True
        self.linefeeds = True
        self.spaces = True
        self.headers = False
        self.protocol = 0  # 0 = Auto, 5 = ISO 14230-4 KWP Fast
        self.start_time = time.time()
        # Stored: P0171 (01 71), P0300 (03 00); Pending: P0420 (04 20)
        self.stored_dtcs = [(0x01, 0x71), (0x03, 0x00)]
        self.pending_dtcs = [(0x04, 0x20)]

    def reset_adapter(self):
        """Reset ELM327 adapter configuration to factory defaults on ATZ / ATWS."""
        self.echo = True
        self.linefeeds = True
        self.spaces = True
        self.headers = False
        self.protocol = 0

    def get_dynamic_values(self):
        elapsed = time.time() - self.start_time
        phase_time = elapsed % 60.0
        coolant = min(88, int(60 + elapsed * 0.2))

        if phase_time < 10.0:
            # Phase 1: Idle (0 - 10s)
            speed = 0
            rpm = int(750 + 30 * math.sin(phase_time * 0.8))
            throttle_pct = 12.0
            load_pct = 20.0
            maf = 2.5 + 0.2 * math.sin(phase_time)
        elif phase_time < 25.0:
            # Phase 2: Acceleration (10 - 25s)
            frac = (phase_time - 10.0) / 15.0
            speed = int(frac * 60.0)
            rpm = int(800.0 + frac * 2000.0)
            throttle_pct = 20.0 + frac * 25.0
            load_pct = 35.0 + frac * 30.0
            maf = max(2.0, (rpm * load_pct) / 6000.0)
        elif phase_time < 40.0:
            # Phase 3: Cruise (25 - 40s)
            frac = (phase_time - 25.0) / 15.0
            speed = 60 + int(3.0 * math.sin(frac * 6.28))
            rpm = 2000 + int(60.0 * math.sin(frac * 6.28))
            throttle_pct = 18.0 + 2.0 * math.sin(frac * 6.28)
            load_pct = 28.0 + 3.0 * math.sin(frac * 6.28)
            maf = max(2.0, (rpm * load_pct) / 6000.0)
        elif phase_time < 52.0:
            # Phase 4: Dedicated Coast-Down / DFCO Phase (40 - 52s)
            # Speed decelerates 60 -> 32 km/h (> 20 km/h)
            # RPM decelerates 2500 -> 1400 RPM (> 1300 RPM)
            # Throttle closed (0.0%, raw 41 11 00), load < 15.0%
            frac = (phase_time - 40.0) / 12.0
            speed = int(60.0 - frac * 28.0)
            rpm = int(2500.0 - frac * 1100.0)
            throttle_pct = 0.0
            load_pct = max(9.0, 12.0 - frac * 3.0)
            maf = 2.8 - frac * 0.8
        else:
            # Phase 5: Braking to Stop / Idle transition (52 - 60s)
            frac = (phase_time - 52.0) / 8.0
            speed = max(0, int(32.0 * (1.0 - frac)))
            rpm = int(1400.0 - frac * 650.0)
            throttle_pct = 8.0
            load_pct = 18.0
            maf = 2.4

        return {
            "rpm": rpm,
            "speed": speed,
            "coolant": coolant,
            "load_pct": load_pct,
            "throttle_pct": throttle_pct,
            "maf": maf,
        }

    def process_command(self, cmd: str) -> str:
        cmd = cmd.replace(" ", "").strip().upper()
        if not cmd:
            return ""

        # AT commands
        if cmd == "ATZ" or cmd == "ATWS":
            self.reset_adapter()
            return "ELM327 v2.3\r\n>"
        if cmd == "ATE0":
            self.echo = False
            return "OK\r\n>"
        if cmd == "ATE1":
            self.echo = True
            return "OK\r\n>"
        if cmd == "ATL0" or cmd == "ATL1":
            self.linefeeds = (cmd == "ATL1")
            return "OK\r\n>"
        if cmd == "ATS0":
            self.spaces = False
            return "OK\r\n>"
        if cmd == "ATS1":
            self.spaces = True
            return "OK\r\n>"
        if cmd == "ATH0":
            self.headers = False
            return "OK\r\n>"
        if cmd == "ATH1":
            self.headers = True
            return "OK\r\n>"
        if cmd.startswith("ATAT"):
            return "OK\r\n>"
        if cmd.startswith("ATSP"):
            try:
                self.protocol = int(cmd[4:], 16)
            except ValueError:
                self.protocol = 0
            return "OK\r\n>"
        if cmd == "ATDP":
            return "ISO 14230-4 (KWP FAST)\r\n>"
        if cmd == "ATDPN":
            return "A5\r\n>"
        if cmd == "ATRV":
            return "14.1V\r\n>"
        if cmd in ("ATI", "AT@1"):
            return "ELM327 v2.3\r\n>"
        if cmd.startswith("ATSH") or cmd.startswith("ATCRA") or cmd.startswith("ATCAF") or cmd.startswith("ATST") or cmd in ("ATD", "ATPC", "ATAL", "ATNL", "ATBD"):
            return "OK\r\n>"
        if cmd.startswith("AT"):
            return "?\r\n>"

        vals = self.get_dynamic_values()

        # OBD-II Mode 01 commands
        if cmd == "0100":
            # Simulate real-world K-Line protocol search / fast init delay
            if self.init_delay > 0:
                time.sleep(self.init_delay)
            # Suzuki Swift K-Line handshake banner
            # Supported PIDs: 01, 03, 04, 05, 0B, 0C, 0D, 0E, 0F, 10, 11, 13, 20
            # Bitmap: BE 3F B8 13
            return "SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>"

        if cmd == "0120":
            # Range 0120 - 0140: supports 21, 2F, 33, 40
            return "41 20 80 02 02 01\r\n>"

        if cmd == "0140":
            # Range 0140 - 0160: supports 42, 46, 5C, 5E
            return "41 40 44 04 00 14\r\n>"

        if cmd == "0104":
            # Engine load: A * 100 / 255
            load_raw = int(vals["load_pct"] * 255 / 100)
            return f"41 04 {load_raw:02X}\r\n>"

        if cmd == "0105":
            # Engine coolant temp: A - 40 -> A = temp + 40
            temp_raw = int(vals["coolant"] + 40)
            return f"41 05 {temp_raw:02X}\r\n>"

        if cmd == "0106":
            # STFT Bank 1: (A - 128) * 100 / 128 (e.g. -1.5%)
            stft = int(128 + (-1.5 * 128 / 100))
            return f"41 06 {stft:02X}\r\n>"

        if cmd == "0107":
            # LTFT Bank 1: (A - 128) * 100 / 128 (e.g. +1.0%)
            ltft = int(128 + (1.0 * 128 / 100))
            return f"41 07 {ltft:02X}\r\n>"

        if cmd == "010A":
            # Fuel Pressure: A * 3 kPa (e.g. 380 kPa)
            fp = int(380 / 3)
            return f"41 0A {fp:02X}\r\n>"

        if cmd == "010B":
            # Intake Manifold Pressure (MAP): A kPa (e.g. 35 to 85 kPa)
            map_kpa = int(30 + (vals["load_pct"] * 0.6))
            return f"41 0B {map_kpa:02X}\r\n>"

        if cmd == "010C":
            # Engine RPM: (256 * A + B) / 4 -> val = rpm * 4
            rpm_raw = int(vals["rpm"] * 4)
            a = (rpm_raw >> 8) & 0xFF
            b = rpm_raw & 0xFF
            return f"41 0C {a:02X} {b:02X}\r\n>"

        if cmd == "010D":
            # Vehicle speed: A km/h
            speed_raw = int(vals["speed"])
            return f"41 0D {speed_raw:02X}\r\n>"

        if cmd == "010E":
            # Timing Advance: (A / 2) - 64 (e.g. 14° + rpm effect)
            adv_deg = 10.0 + (vals["rpm"] / 300.0)
            adv_raw = int((adv_deg + 64.0) * 2.0)
            return f"41 0E {adv_raw:02X}\r\n>"

        if cmd == "010F":
            # Intake Air Temp: A - 40 (e.g. 25°C)
            iat_raw = int(25 + 40)
            return f"41 0F {iat_raw:02X}\r\n>"

        if cmd == "0110":
            # MAF: (256 * A + B) / 100
            maf_raw = int(vals["maf"] * 100)
            a = (maf_raw >> 8) & 0xFF
            b = maf_raw & 0xFF
            return f"41 10 {a:02X} {b:02X}\r\n>"

        if cmd == "0111":
            # Throttle position: A * 100 / 255
            throt_raw = int(vals["throttle_pct"] * 255 / 100)
            return f"41 11 {throt_raw:02X}\r\n>"

        if cmd == "011F":
            # Run time since engine start: (256 * A) + B seconds
            elapsed_sec = int(time.time() - self.start_time)
            a = (elapsed_sec >> 8) & 0xFF
            b = elapsed_sec & 0xFF
            return f"41 1F {a:02X} {b:02X}\r\n>"

        if cmd == "012F":
            # Fuel tank level: A * 100 / 255 (e.g. 70%)
            fuel_raw = int(70 * 255 / 100)
            return f"41 2F {fuel_raw:02X}\r\n>"

        if cmd == "0133":
            # Barometric pressure: A kPa (101 kPa)
            return "41 33 65\r\n>"

        if cmd == "0142":
            # Control module voltage: ((256 * A) + B) / 1000 (e.g. 14.15V)
            mv = int(14150)
            a = (mv >> 8) & 0xFF
            b = mv & 0xFF
            return f"41 42 {a:02X} {b:02X}\r\n>"

        if cmd == "0146":
            # Ambient air temp: A - 40 (e.g. 19°C)
            amb_raw = int(19 + 40)
            return f"41 46 {amb_raw:02X}\r\n>"

        if cmd == "015C":
            # Engine oil temp: A - 40 (coolant + 4°C)
            oil_raw = int(vals["coolant"] + 4 + 40)
            return f"41 5C {oil_raw:02X}\r\n>"

        if cmd == "015E":
            # Engine fuel rate: ((256 * A) + B) / 20 L/h
            # Deceleration Fuel Cut-Off (DFCO): when coasting in gear with closed throttle,
            # fuel flow is cut off completely (0.0 L/h -> 41 5E 00 00).
            if vals["speed"] > 20 and vals["rpm"] > 1300 and vals["throttle_pct"] < 1.0:
                return "41 5E 00 00\r\n>"
            # In non-DFCO phases (idle, acceleration, cruise), compute realistic fuel flow from MAF
            # (stoichiometric 14.7:1 AFR, 820 g/L gasoline density)
            fuel_lph = vals["maf"] * 3600.0 / (14.7 * 820.0)
            fr_raw = int(fuel_lph * 20)
            a = (fr_raw >> 8) & 0xFF
            b = fr_raw & 0xFF
            return f"41 5E {a:02X} {b:02X}\r\n>"

        # OBD-II Mode 03 / 07: stored / pending DTCs (K-Line style, count byte first)
        if cmd in ("03", "07"):
            codes = self.stored_dtcs if cmd == "03" else self.pending_dtcs
            header = "43" if cmd == "03" else "47"
            if not codes:
                return f"{header} 00\r\n>"
            body = " ".join(f"{hi:02X} {lo:02X}" for hi, lo in codes)
            return f"{header} {len(codes):02X} {body}\r\n>"

        # OBD-II Mode 04: clear DTCs / reset MIL (clears stored and pending)
        if cmd == "04":
            self.stored_dtcs = []
            self.pending_dtcs = []
            return "44\r\n>"

        return "NO DATA\r\n>"

def handle_client(conn, addr, simulator):
    print(f"\n[+] Client connected from {addr[0]}:{addr[1]}")
    buffer = ""

    try:
        while True:
            data = conn.recv(1024)
            if not data:
                break

            text = data.decode("ascii", errors="replace")
            buffer += text

            while "\r" in buffer or "\n" in buffer:
                parts = buffer.replace("\n", "\r").split("\r", 1)
                cmd = parts[0].strip()
                buffer = parts[1]

                if not cmd:
                    continue

                print(f"  [RX] <--- {cmd}")
                resp = simulator.process_command(cmd)
                if resp:
                    print(f"  [TX] ---> {repr(resp)}")
                    conn.sendall(resp.encode("ascii"))
    except (ConnectionResetError, BrokenPipeError, ConnectionError, OSError):
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass
        print(f"[-] Client {addr[0]}:{addr[1]} disconnected\n")

def main():
    args = parse_args()
    simulator = SuzukiSwiftSimulator(init_delay=args.delay)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        server.bind((args.host, args.port))
        server.listen(16)
        print("=" * 60)
        print(f"  Vgate iCar Pro ELM327 v2.3 Emulator")
        print(f"  Target: Suzuki Swift 2007 (M15A)")
        print(f"  Listening on {args.host}:{args.port}")
        print(f"  Simulated K-Line init delay: {args.delay}s")
        print("=" * 60)
        print("Connect using ReDrive app (Wi-Fi tab -> 127.0.0.1:35000)")
        print("Press Ctrl+C to stop.\n")

        while True:
            conn, addr = server.accept()
            client_thread = threading.Thread(
                target=handle_client,
                args=(conn, addr, simulator),
                daemon=True,
            )
            client_thread.start()
    except KeyboardInterrupt:
        print("\nStopping emulator...")
    finally:
        server.close()

if __name__ == "__main__":
    main()
