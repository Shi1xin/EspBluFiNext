# EspBluFiNext

EspBluFiNext is an independent native iOS 26 diagnostic client for ESP32 devices that support Espressif's BluFi protocol. It provides Bluetooth Low Energy discovery, connection, provisioning, status inspection, and diagnostic tools.

[简体中文](README.zh-CN.md)

[License](LICENSE) · [Third-party notices](THIRD-PARTY-NOTICES.md) · [Branding guide](docs/BRANDING.md)

## Project status

The core BLE, BluFi protocol, security, Wi-Fi provisioning, custom-data, diagnostics, and self-signing workflows are implemented. The confirmed hardware baseline is:

- ESP32-S3
- ESP-IDF 5.5.2
- BluFi 1.3
- Security V1
- Station provisioning

Additional chips, ESP-IDF 6.x/V2, SoftAP/APSTA behavior, and broader firmware matrices require separate real-device validation.

BluFi is in Espressif's maintenance mode. EspBluFiNext focuses on diagnostics and interoperability with existing BluFi firmware. Use current firmware and validate the security behavior of the target device.

## Architecture

```text
SwiftUI screens
    ↓
AppCoordinator / BluFiSessionController / BluFiDiagnosticsStore
    ↓
BluFiCoreBluetoothTransport + BluFiScanner
    ↓
BluFiKit (frames, CRC, fragmentation, security, provisioning, fake transport)
```

- `project.yml`: XcodeGen source of truth for targets, resources, package dependencies, build settings, and schemes.
- `Sources/EspBlufiNext`: SwiftUI screens, app coordination, CoreBluetooth integration, provisioning, custom data, localization, settings, and diagnostics.
- `Packages/BluFiKit`: transport-independent BluFi framing, security, session behavior, provisioning payloads/parsers, and test transport.
- `Tests/EspBlufiNextTests`: app-level tests.
- `Packages/BluFiKit/Tests`: protocol, security, provisioning, and failure-recovery tests.
- `scripts/build-ios.sh`: simulator or physical-device build.
- `scripts/archive-ios.sh`: Release archive.
- `scripts/export-ios.sh`: signed IPA export.

Protocol behavior lives in BluFiKit, CoreBluetooth behavior in the transport layer, and UI state transitions in the app layer. Generated Xcode projects and local signing files stay outside source control.

## Features

- Discover nearby ESP BluFi peripherals and inspect name, identifier, RSSI, BluFi version, and security state.
- Connect, reconnect, disconnect, and observe Bluetooth/GATT state transitions.
- Negotiate BluFi security and read device Wi-Fi status.
- Request a Wi-Fi scan from the ESP device and inspect SSID/RSSI results.
- Provision Station Wi-Fi with a manually entered SSID/password, the current iPhone Wi-Fi SSID, or a selected device scan result.
- Display device-reported Station Connected and IP Available events after provisioning.
- Send and receive custom data as UTF-8, Hex, or Base64.
- Keep redacted session history and diagnostic events, remove individual sessions, clear history, copy filtered logs, and share diagnostic exports through the iOS share sheet.
- Use English or Simplified Chinese.

## Requirements

- macOS with Xcode 26 or later, including the iOS 26 SDK and Swift 6.
- XcodeGen (`brew install xcodegen`).
- A physical iPhone or iPad for Bluetooth and ESP testing.
- An Apple Development team, certificate, registered bundle ID, and provisioning profile for physical-device builds and sideloading.
- An ESP BluFi device running firmware compatible with the selected test case.

The simulator can validate UI, navigation, state handling, diagnostics, localization, and package tests. CoreBluetooth scanning, GATT traffic, security negotiation, provisioning, and firmware compatibility require a real Apple device and ESP hardware.

## Toolchain setup

Install Xcode 26 or later. When multiple Xcode versions are installed, select the bundle you want to use. For the standard installation path:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
brew install xcodegen

xcode-select -p
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-version
```

The build scripts use the active developer directory selected by `xcode-select`. You can also provide `DEVELOPER_DIR` explicitly for another Xcode installation.

## Local signing configuration

Keep signing identifiers in the ignored local configuration:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Edit Config/Local.xcconfig and set DEVELOPMENT_TEAM to your Team ID.
```

The app uses bundle identifier `com.espblufi.next` and the Wi-Fi information entitlement for reading the current iPhone Wi-Fi SSID. The Apple Developer account must be able to sign that bundle ID and profile.

## Simulator build

Generate the project and build an unsigned iOS simulator target:

```bash
xcodegen generate
./scripts/build-ios.sh
```

Equivalent direct build:

```bash
xcodebuild \
  -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Physical-device build

Use the local signing team for a generic iOS device build:

```bash
DESTINATION='generic/platform=iOS' ./scripts/build-ios.sh
```

Select the connected iPhone or iPad as the Xcode run destination when installing from Xcode. Grant Bluetooth and location permissions when requested. Location permission is required by iOS for reading the current Wi-Fi network name.

## Archive and self-signing

The repository distributes source code and repeatable local build steps. Each user creates an IPA signed by their own Apple team.

Create the export configuration:

```bash
cp Config/ExportOptions.plist.example Config/ExportOptions.plist
# Set teamID and the development provisioning profile name for com.espblufi.next.
```

Create a Release archive and override the version when needed:

```bash
MARKETING_VERSION=0.1.0 \
CURRENT_PROJECT_VERSION=1 \
./scripts/archive-ios.sh
```

Export the signed IPA:

```bash
./scripts/export-ios.sh
```

Artifacts are written to:

```text
build/archive/EspBlufiNext.xcarchive
build/export/EspBlufiNext.ipa
```

The export template uses manual development signing. Replace its Team ID and certificate/profile values, or use an equivalent export configuration generated by your own Xcode account. `Config/Local.xcconfig`, `Config/ExportOptions.plist`, archives, and exported packages are ignored by Git.

For build-only archive verification:

```bash
CODE_SIGNING_ALLOWED=NO \
CODE_SIGNING_REQUIRED=NO \
./scripts/archive-ios.sh
```

The resulting archive requires a valid user signature before installation. TestFlight and App Store Connect are outside the current release workflow.

## Tests and verification

Run transport-independent protocol tests:

```bash
swift test --package-path Packages/BluFiKit
```

Run app tests on a concrete simulator destination:

```bash
xcodebuild \
  -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The package suite covers frame encoding, CRC, fragmentation, ACK handling, transport cancellation, V1/V2 security vectors, Wi-Fi status/scan parsing, provisioning payloads, and invalid security input. App tests cover navigation, payload formats, diagnostics persistence, redaction, and session history.

Use a real iPhone or iPad with ESP hardware to verify scanning, connection, GATT writes, notifications, security negotiation, Wi-Fi status, device Wi-Fi scans, Station provisioning, device-reported connection events, and disconnect recovery.

## Project notices

- Original EspBluFiNext source code is released under the [MIT License](LICENSE).
- [Third-party notices](THIRD-PARTY-NOTICES.md) include BigInt's MIT license and the Espressif BluFi reference-project notice.
- The app does not bundle Espressif's Android/Objective-C reference source, OpenSSL headers/libraries, or ESP-IDF source. Any future copied material must retain its exact file-level license and notices.
- EspBluFiNext is an independent project and is not affiliated with, sponsored by, or endorsed by Espressif Systems (Shanghai) Co., Ltd. `ESP32` and `BluFi` are used only to describe compatibility.
- The app icon, screenshots, and marketing artwork use original assets. The [branding guide](docs/BRANDING.md) defines approved wording and asset rules.

Protocol reference: [Espressif BluFi documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c2/api-guides/ble/blufi.html). Security background: [ESP-IDF BluFi advisory](https://github.com/espressif/esp-idf/security/advisories/GHSA-9w88-r2vm-qfc4).
