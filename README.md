# macos-nothing-ear-utility

A polished, native macOS menu-bar utility to monitor the battery and connection status of your **Nothing Ear (2)** Bluetooth earbuds. 

![macOS Version](https://img.shields.io/badge/macOS-14.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

Nothing Ear (2) does not natively report separate left, right, and case batteries to macOS via the standard Bluetooth menu. `Nothing Ear Utility` solves this by continuously monitoring Google Fast Pair Bluetooth Low Energy (BLE) payloads to extract detailed battery information.

## Features

- **Menu Bar Integration**: A minimalist, Apple-like popover UI that sits perfectly in your menu bar.
- **Battery Status**: Displays precise Left, Right, and Case battery percentages.
- **Diagnostics**: Built-in developer diagnostic view for inspecting proprietary Bluetooth characteristics.
- **Settings**: Support for "Launch at Login" and low battery notifications.

## Architecture

This project is built using:
- **SwiftUI**: For the main popover (`MenuBarExtra`) and Settings UI.
- **CoreBluetooth**: For scanning and parsing the BLE advertisement packets (specifically Fast Pair service `FE2C`).
- **XcodeGen**: To maintain a clean and reproducible project structure without committing `.xcodeproj` blobs.

## Prerequisites

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, if you wish to regenerate the project)

## Installation & Build

Since this project uses XcodeGen, the structure is managed via `project.yml`.

1. Clone the repository:
   ```bash
   git clone git@jazeel-zainudeen:jazeel-zainudeen/macos-nothing-ear-utility.git
   cd macos-nothing-ear-utility
   ```

2. (Optional) Generate the Xcode project using XcodeGen:
   ```bash
   brew install xcodegen
   xcodegen
   ```

3. Open `macos-nothing-ear-utility.xcodeproj` in Xcode.
4. Select your Mac as the destination and run the `NothingEarUtility` scheme (`Cmd + R`).

## How Battery Parsing Works

When connected, Nothing Ear (2) broadcasts a Google Fast Pair BLE packet containing the battery states. `Nothing Ear Utility` uses `CBCentralManager` to capture the `CBAdvertisementDataServiceDataKey` from the `FE2C` service. The payload is parsed in `NothingEarProtocol.swift` to extract the individual charging states and percentages.

## Privacy & Permissions

This application requests **Bluetooth** permissions strictly to read the battery levels of your earbuds. It does not contain any analytics, telemetry, or network calls.

## License

MIT License
