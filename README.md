<a id="english"></a>

# EspBluFiNext

Native iOS 26 ESP BluFi diagnostics for engineers who need to discover, connect, provision, inspect, and troubleshoot ESP BluFi devices over Bluetooth Low Energy.

[简体中文](#chinese)

[License](LICENSE) · [Third-party notices](THIRD-PARTY-NOTICES.md) · [Branding guide](docs/BRANDING.md)

## Project status

The core BLE, BluFi protocol, security, Wi-Fi provisioning, custom-data, diagnostics, and self-signing workflows are implemented. The confirmed hardware baseline is:

- ESP32-S3
- ESP-IDF 5.5.2
- BluFi 1.3
- Security V1
- Station provisioning

Additional chips, ESP-IDF 6.x/V2, SoftAP/APSTA behavior, and broader firmware matrices require separate real-device validation.

BluFi is in Espressif's maintenance mode. This project remains focused on
diagnostics and interoperability with existing BluFi firmware; it does not
claim to be an official Espressif client or a production security tool. Use
current firmware and validate the security behavior of the target device.

## Licensing, trademarks, and release boundary

- Original EspBluFiNext source code is released under the [MIT License](LICENSE).
- The [third-party notices](THIRD-PARTY-NOTICES.md) include BigInt's MIT license and the Espressif BluFi reference-project notice.
- The current app does not bundle Espressif's Android/Objective-C reference source, OpenSSL headers/libraries, or ESP-IDF source. Future copied material must retain its exact file-level license and notices.
- `ESP32` and `BluFi` identify compatibility. EspBluFiNext is an independent project and is not affiliated with, sponsored by, or endorsed by Espressif Systems (Shanghai) Co., Ltd.
- The app icon, screenshots, and marketing artwork use original assets. The [branding guide](docs/BRANDING.md) defines approved wording and asset rules.
- GitHub releases provide source and repeatable self-signing steps. Each user signs their own IPA with their Apple Development team.

Protocol reference: [Espressif BluFi documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c2/api-guides/ble/blufi.html). Security background: [ESP-IDF BluFi advisory](https://github.com/espressif/esp-idf/security/advisories/GHSA-9w88-r2vm-qfc4).

## Features

- Discover nearby ESP BluFi peripherals and inspect name, identifier, RSSI, BluFi version, and security state.
- Connect, reconnect, disconnect, and observe Bluetooth/GATT state transitions.
- Negotiate BluFi security and read device Wi-Fi status.
- Request a Wi-Fi scan from the ESP device and inspect SSID/RSSI results.
- Provision Station Wi-Fi with a manually entered SSID/password, the current iPhone Wi-Fi SSID, or a selected device scan result.
- Display device-reported Station Connected and IP Available events after provisioning.
- Send and receive custom data as UTF-8, Hex, or Base64.
- Keep redacted session history and diagnostic events, remove individual sessions, clear history, copy filtered logs, and share diagnostic exports through the iOS share sheet.
- Use English, Simplified Chinese, or the system language.

Siri, Shortcuts, Spotlight, and App Intents actions remain a separate planned scope.

## Requirements

- macOS with Xcode beta that includes the iOS 26 SDK.
- Swift 6 toolchain from the selected Xcode bundle.
- XcodeGen (`brew install xcodegen`).
- A physical iPhone or iPad for Bluetooth and ESP testing.
- An Apple Development team, certificate, registered bundle ID, and provisioning profile for physical-device builds and sideloading.
- An ESP BluFi device running firmware compatible with the selected test case.

The simulator can validate UI, navigation, state handling, diagnostics, localization, and package tests. CoreBluetooth scanning, GATT traffic, security negotiation, provisioning, and firmware compatibility require a real Apple device and ESP hardware.

## One-time toolchain setup

Select the full Xcode beta toolchain before building:

```bash
sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
brew install xcodegen

xcode-select -p
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-version
```

The active developer directory should point to the Xcode beta bundle. The generated project uses iOS 26 as its deployment target.

## Local signing configuration

Keep signing identifiers in the ignored local configuration:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Edit Config/Local.xcconfig and set DEVELOPMENT_TEAM to your Team ID.
```

The app uses bundle identifier `com.espblufi.next` and the Wi-Fi information entitlement for reading the current iPhone Wi-Fi SSID. The Apple Developer account must be able to sign that bundle ID and profile.

## Simulator build

Generate the project and build an unsigned iOS 26 simulator target:

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

Select the connected iPhone or iPad as the Xcode run destination when installing from Xcode. Grant Bluetooth and location permissions when the app requests them. Location permission is required by iOS for reading the current Wi-Fi network name.

## GitHub build and self-signing

The repository distributes source code and repeatable local build steps. Every user creates an IPA signed by their own Apple team.

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

The export template uses manual development signing. Replace its Team ID, certificate/profile values, or use an equivalent export configuration generated by your own Xcode account. Install the resulting IPA with the sideloading tool of your choice. `Config/Local.xcconfig`, `Config/ExportOptions.plist`, archives, and exported packages are ignored by Git.

For build-only archive verification:

```bash
CODE_SIGNING_ALLOWED=NO \
CODE_SIGNING_REQUIRED=NO \
./scripts/archive-ios.sh
```

That archive verifies the Release build and needs a valid user signature before installation. TestFlight and App Store Connect are outside the current distribution scope.

## Tests and verification

Run transport-independent protocol tests:

```bash
swift test --package-path Packages/BluFiKit
```

Run App tests on a concrete simulator destination:

```bash
xcodebuild \
  -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The package suite covers frame encoding, CRC, fragmentation, ACK handling, transport cancellation, V1/V2 security vectors, Wi-Fi status/scan parsing, provisioning payloads, and invalid security input. App tests cover navigation, payload formats, diagnostics persistence, redaction, and session history.

Use a real iPhone/iPad plus ESP hardware to verify scanning, connection, GATT writes, notifications, security negotiation, Wi-Fi status, device Wi-Fi scan, Station provisioning, device-reported connection events, and disconnect recovery.

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

- `project.yml`: XcodeGen source of truth for targets, resources, package dependency, build settings, and schemes.
- `Sources/EspBlufiNext`: SwiftUI screens, app coordination, CoreBluetooth integration, provisioning, custom data, localization, settings, and diagnostics.
- `Packages/BluFiKit`: transport-independent BluFi framing, security, session behavior, provisioning payloads/parsers, and test transport.
- `Tests/EspBlufiNextTests`: app-level tests.
- `Packages/BluFiKit/Tests`: protocol, security, provisioning, and failure-recovery tests.
- `scripts/build-ios.sh`: simulator or physical-device build.
- `scripts/archive-ios.sh`: Release archive.
- `scripts/export-ios.sh`: signed IPA export.

Keep protocol behavior in BluFiKit, CoreBluetooth behavior in the transport layer, and UI state transitions in the app layer. Generated `.xcodeproj` files and user signing files remain outside the source workflow.

## Privacy and diagnostics

- Wi-Fi passwords are sent once for provisioning and are not retained in session state or logs.
- Diagnostic exports are redacted by default. Credentials, keys, certificates, and sensitive raw payloads are excluded while protocol metadata and byte counts remain available.
- Custom-data payloads are shown in the console for the active session; do not share diagnostic files containing sensitive information without reviewing them.
- Local session history is bounded and can be removed from the Logs tab.

## Development guidance

Read [`AGENTS.md`](AGENTS.md) for repository boundaries, required commands, signing rules, real-device validation, and Build iOS Apps plugin workflow. The planning map and decisions live in [`../EspBluFiNextPlans`](../EspBluFiNextPlans/).

<a id="chinese"></a>

## 简体中文

[English](#english)

### 项目定位

EspBluFiNext 是面向 ESP BluFi 调试的原生 iOS 26 应用，使用 SwiftUI、CoreBluetooth 和 BluFiKit，实现设备发现、连接、安全会话、Wi-Fi 配网、状态读取和诊断日志。

当前已完成 BLE、BluFi 协议、安全协商、Wi-Fi 配网、自定义数据、诊断日志和自签名构建流程。已确认的硬件基线为：ESP32-S3、ESP-IDF 5.5.2、BluFi 1.3、Security V1、Station 配网。

BluFi 处于乐鑫维护模式。本项目面向现有 BluFi 固件的调试和互操作，不代表乐鑫官方客户端或生产环境安全工具。请使用已更新的设备固件，并自行验证目标设备的安全行为。

### 许可证、商标与发布边界

- EspBluFiNext 自有源代码使用 [`MIT License`](LICENSE)。
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) 包含 BigInt 的 MIT 许可证和 Espressif BluFi 参考项目的许可证来源说明。
- 当前应用未捆绑 Espressif Android/Objective-C 参考源代码、OpenSSL 头文件/库或 ESP-IDF 源码。未来加入第三方文件时，必须保留其准确的文件级许可证和声明。
- `ESP32` 和 `BluFi` 仅用于描述兼容性。EspBluFiNext 是独立项目，与 Espressif Systems (Shanghai) Co., Ltd. 无隶属、赞助或背书关系。
- App 图标、截图和宣传素材使用自有资产；[`docs/BRANDING.md`](docs/BRANDING.md) 规定了可用措辞和素材边界。
- GitHub 发布源代码和可复现的自签名步骤；每位使用者使用自己的 Apple Development Team 签名 IPA。

协议参考：[乐鑫 BluFi 文档](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c2/api-guides/ble/blufi.html)。安全背景：[ESP-IDF BluFi 安全公告](https://github.com/espressif/esp-idf/security/advisories/GHSA-9w88-r2vm-qfc4)。

### 主要功能

- 发现附近 ESP BluFi 设备并查看名称、标识符、RSSI、BluFi 版本和安全状态。
- 连接、重连、断开设备并观察 BLE/GATT 状态。
- 建立 BluFi 安全会话并读取设备 Wi-Fi 状态。
- 从设备扫描 Wi-Fi 网络并查看 SSID/RSSI。
- 使用手动输入、当前 iPhone Wi-Fi SSID 或设备扫描结果完成 Station 配网。
- 显示设备上报的 Station Connected 和 IP Available 状态。
- 以 UTF-8、Hex、Base64 格式收发自定义数据。
- 保存脱敏会话历史和诊断事件，支持删除、清空、筛选、复制和通过系统分享面板导出。
- 支持英文、简体中文和系统语言。

Siri、Shortcuts、Spotlight 和 App Intents 入口暂未实现，属于后续规划范围。

### 环境要求

- 包含 iOS 26 SDK 的 macOS 和 Xcode beta。
- XcodeGen：`brew install xcodegen`。
- 用于蓝牙和 ESP 测试的真实 iPhone 或 iPad。
- 用于真机签名和 sideload 的 Apple Development Team、证书、Bundle ID 和 provisioning profile。
- 与测试场景兼容的 ESP BluFi 固件。

模拟器用于验证 UI、导航、状态、诊断、语言和测试；BLE、GATT、配网和固件兼容性需要真实 iPhone/iPad 与 ESP。

### 构建与签名

```bash
sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
brew install xcodegen

cp Config/Local.xcconfig.example Config/Local.xcconfig
# 在 Config/Local.xcconfig 中填写 DEVELOPMENT_TEAM

xcodegen generate
./scripts/build-ios.sh
```

生成自签名 IPA：

```bash
cp Config/ExportOptions.plist.example Config/ExportOptions.plist
# 填写 teamID 和 com.espblufi.next 对应的 provisioning profile

MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=1 ./scripts/archive-ios.sh
./scripts/export-ios.sh
```

archive 位于 `build/archive/`，IPA 位于 `build/export/`。每位使用者使用自己的 Apple Team 完成签名和 sideload；TestFlight 与 App Store 暂不在当前范围内。

### 测试

```bash
swift test --package-path Packages/BluFiKit

xcodebuild \
  -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

协议测试覆盖帧、CRC、分片、ACK、传输取消、V1/V2 安全向量、Wi-Fi 状态/扫描解析、配网载荷和故障恢复。App 测试覆盖导航、数据格式、诊断持久化、脱敏和会话历史。BLE 和固件结论需要真机测试。

### 代码结构

- `project.yml`：XcodeGen 工程源文件。
- `Sources/EspBlufiNext`：SwiftUI、App 协调、CoreBluetooth、配网、自定义数据、本地化、设置和诊断。
- `Packages/BluFiKit`：协议帧、安全、会话、配网和 fake transport。
- `Tests/EspBlufiNextTests`：App 测试。
- `Packages/BluFiKit/Tests`：协议、安全、配网和故障恢复测试。
- `scripts/build-ios.sh`：构建。
- `scripts/archive-ios.sh`：生成 Release archive。
- `scripts/export-ios.sh`：导出签名 IPA。

更多开发边界、验证要求和插件工作流见 [`AGENTS.md`](AGENTS.md)；完整阶段规划见 [`../EspBluFiNextPlans`](../EspBluFiNextPlans/)。

### 隐私规则

- Wi-Fi 密码只发送一次，不保存到会话状态或日志。
- 诊断导出默认脱敏，排除凭据、密钥、证书和敏感原始数据。
- 自定义数据会显示在当前会话控制台中，分享前请检查内容。
- Logs 页面支持删除本地会话历史。
