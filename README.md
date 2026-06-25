# libhr 🫀

**libhr** is a modern, cross-platform C++ library for interacting with Bluetooth Low Energy (BLE) Heart Rate Monitors. 
It provides a simple, robust interface to discover devices, stream data, and perform advanced cardiovascular analysis 
(HRV, Recovery, Zones, etc.).

## Features

- **BLE Device Management**: Connect, read, and manage BLE heart rate monitors effortlessly.
- **Advanced Metrics & Analysis**:
  - Heart Rate Variability (HRV) calculation
  - Rolling Averages & Signal Smoothing
  - Workout Zones (e.g., Fat Burn, Aerobic, Anaerobic)
  - Trend Detection (Increasing/Decreasing)
  - Peak Detection & Recovery Rate Calculation
  - Comprehensive Session Statistics (Min, Max, Avg, etc.)
- **Versatile Utilities**:
  - Export data to CSV/JSON formats for external analysis.
  - Playback mode for recorded sessions (ideal for testing/development).
  - Battery level monitoring for BLE devices.

## Supported Platforms

Currently focusing on Apple-based systems (macOS, iOS) via CoreBluetooth.

*Planned future support for:*
- Windows (via WinRT)
- Linux (via BlueZ)
- Android

## Installation & Build

Build `libhr` and the accompanying `heart-cli` tool using CMake.

```bash
mkdir build && cd build
cmake ..
cmake --build .
```

## CLI Tool (`heart-cli`)

A command-line tool `heart-cli` is included for rapid testing and debugging.

```bash
# Scan and connect to the nearest Heart Rate Monitor
./heart-cli --monitor

# Export real-time data to a CSV
./heart-cli --monitor --export session.csv
```

## Roadmap

- [ ] Core BLE connection and data reading functionality.
- [ ] Implement robust unit testing to ensure reliability and correctness.
- [ ] Flesh out advanced metrics functions (HRV, Zones, Trending).
- [ ] Implement backend support for Windows, Linux, and Android.
- [ ] Create an iOS/macOS demonstration application.
- [ ] CI/CD pipeline for automated testing and deployment.
