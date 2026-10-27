# OBDrive (Extended In-Car & Headunit Edition)

> OBDrive is a high-performance OBD2 cockpit launcher and companion platform for in-car Android headunits and mobile devices, featuring real-time telemetry, trip tracking, diagnostics, and wireless sync.
> 
> A customized derivative originating from [ReDrive by iUnreallx](https://github.com/iUnreallx/ReDrive).

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)](https://dart.dev/)
[![OBD2: ELM327](https://img.shields.io/badge/OBD2-ELM327-orange?style=flat)](https://github.com/bartoszkxyz/ReDrive)

---

## Attribution & Upstream Credits

* **Original Project**: [ReDrive](https://github.com/iUnreallx/ReDrive)
* **Original Author**: [@iUnreallx](https://github.com/iUnreallx)
* **License**: GNU General Public License v3.0 (GPL-3.0)

All foundational OBD2 communication architecture, core ELM protocol parsers, and base UI designs originated from the upstream [ReDrive](https://github.com/iUnreallx/ReDrive) project by **iUnreallx**. 

This repository is a customized derivative maintained by [@bartoszkxyz](https://github.com/bartoszkxyz) for personal and in-car use. In accordance with Section 5(a) of the GNU General Public License v3.0, prominent notices of modification and an overview of structural additions are detailed below.

---

## Major Enhancements in This Edition

This fork introduces extensive architectural and functional changes across multiple application layers:

### 1. New Screens & Layout Overhaul
* **Dashboard Tab (`DashboardScreen`)**: Real-time gauge cluster view designed for quick driving readouts and minimal distraction.
* **Trips Tab (`TripsScreen`)**: Automated trip logger tracking distance, elapsed driving time, fuel consumption, and telemetry history.
* **Diagnostics Tab (`DiagnosticsScreen`)**: Full DTC (Diagnostic Trouble Codes) scanner with fault code decoding, descriptions, and ECU clearing.
* **Redesigned Home & Settings**: Expanded telemetry tiles (engine load, engine temperature, fuel rate, active trip card) and granular adapter configurations.

### 2. Android Headunit & In-Car Integration
* **Auto-Start on Boot (`HeadunitBootReceiver`)**: Automatically launches and connects when an Android car stereo or headunit powers on with vehicle ignition.
* **Background Service (`BackgroundService`)**: Keeps telemetry streaming and Bluetooth/Wi-Fi connection alive when switching between apps or running navigation in the foreground.

### 3. Extended OBD-II Protocol & Connectivity
* **Wi-Fi / TCP Support (`TcpObdConnection`)**: Full support for Wi-Fi ELM327 adapters alongside classic Bluetooth.
* **Extended PID Decoders**: Added support for:
  * MAF Air Flow Rate (`0110`)
  * Calculated Engine Load (`0104`)
  * Throttle Position (`0111`)
  * Engine Fuel Rate (`015E`)
* **Local Emulator Suite (`tools/elm327_emulator.py`)**: Included Python ELM327 socket emulator for testing and UI development without requiring a physical car.

---

## Installation & Setup

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.10)
* Android device, tablet, or Android headunit
* ELM327 OBD-II adapter (Bluetooth Classic or Wi-Fi TCP)

### Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/bartoszkxyz/ReDrive.git
   cd ReDrive
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the application:
   ```bash
   flutter run
   ```

---

## License

This program is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License v3.0** as published by the Free Software Foundation. See the [LICENSE](LICENSE) file for complete details.
