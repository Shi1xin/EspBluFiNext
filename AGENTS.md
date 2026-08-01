# EspBlufiNext

## Scope

EspBlufiNext is a modern native iOS 26 diagnostic client for ESP BluFi devices. The app uses SwiftUI for the interface, CoreBluetooth for the BLE link, and BluFiKit for transport-independent protocol and security behavior.

The app is distributed from GitHub source code. Each user supplies their own Apple Development team, signing certificate, bundle ID registration, and provisioning profile for a physical-device build or sideloaded IPA.

## Source of truth and repository hygiene

- `project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after changing it or adding project resources.
- `EspBlufiNext.xcodeproj` is generated and ignored. Do not edit or commit it manually.
- `Config/Local.xcconfig` and `Config/ExportOptions.plist` contain user-specific signing data. Keep both local and never commit them.
- `build/`, `DerivedData/`, package build products, archives, exported IPAs, and local SwiftPM caches are generated artifacts.
- Version defaults live in `Config/Debug.xcconfig` and `Config/Release.xcconfig`. Release scripts can override them with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Keep protocol behavior, signing configuration, and user credentials separate from UI-only changes.

## Release, licensing, and branding

- `LICENSE` covers original EspBluFiNext source code. The current project uses the MIT License.
- `THIRD-PARTY-NOTICES.md` records BigInt's MIT license and Espressif BluFi reference-project provenance. Keep it synchronized when package dependencies or copied source change.
- The app target bundles `Sources/EspBlufiNext/Resources/THIRD-PARTY-NOTICES.md` so a self-signed IPA exposes the same notices as the GitHub source release. Keep it aligned with the repository-level `THIRD-PARTY-NOTICES.md`, and run `xcodegen generate` after changing resource paths.
- Keep Espressif's Java/Objective-C reference source, OpenSSL headers/libraries, and ESP-IDF files out of the app unless their exact file-level license and notice are reviewed first.
- Use `ESP32` and `BluFi` to describe compatibility. Do not present EspBluFiNext as an official Espressif product, and do not add Espressif logos, wordmarks, official screenshots, or official app assets.
- Keep the independent-project statement in `README.md`, `docs/BRANDING.md`, the About screen, and release descriptions. The approved wording is documented in `docs/BRANDING.md`.
- The project name, app icon, screenshots, and marketing artwork must remain visually distinct from Espressif branding.

## Module boundaries

| Area | Responsibility |
|---|---|
| `Sources/EspBlufiNext` | SwiftUI screens, app coordinator, CoreBluetooth scanner/transport, session state, provisioning UI, custom-data console, diagnostics, localization, and local settings |
| `Packages/BluFiKit` | BluFi frame/CRC codec, fragmentation, V1/V2 security negotiation, transport-independent session actors, provisioning payloads/parsers, Wi-Fi status and scan models, and fake transport tests |
| `Tests/EspBlufiNextTests` | App coordinator, payload codec, diagnostics persistence/redaction, and app-state tests |
| `Packages/BluFiKit/Tests` | Protocol vectors, security, ACK/fragmentation, transport cancellation, provisioning, and parser tests |
| `project.yml` | Targets, package dependency, resources, Info.plist properties, signing-related build settings, and schemes |

Keep command orchestration in `BluFiSessionController` and transport details in the transport implementations. Keep `BluFiKit` independent of SwiftUI and CoreBluetooth.

## Toolchain and one-time setup

Use Xcode 26 or later with the iOS 26 SDK:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
brew install xcodegen
xcodebuild -version
```

For a physical iPhone or iPad, create the local signing file and set the Apple Development team:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Set DEVELOPMENT_TEAM in Config/Local.xcconfig.
```

The local file is intentionally ignored. Do not put a Team ID, certificate, profile name, Wi-Fi password, or private key in tracked files.

## Build and test commands

Run commands from the repository root:

```bash
xcodegen generate
swift test --package-path Packages/BluFiKit
./scripts/build-ios.sh
xcodebuild -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run App tests on a concrete simulator destination. A generic simulator destination can build, but it cannot execute tests:

```bash
xcodebuild -project EspBlufiNext.xcodeproj \
  -scheme EspBlufiNext \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO test
```

Run a physical-device build with the local signing team:

```bash
DESTINATION='generic/platform=iOS' ./scripts/build-ios.sh
```

## Release archive and self-signing

The GitHub workflow produces source and repeatable local build steps. A signed IPA is created by the person who owns the target Apple team:

```bash
cp Config/ExportOptions.plist.example Config/ExportOptions.plist
# Set teamID and the development provisioning profile for com.espblufi.next.

MARKETING_VERSION=0.1.0 \
CURRENT_PROJECT_VERSION=1 \
./scripts/archive-ios.sh

./scripts/export-ios.sh
```

The archive is written to `build/archive/` and the IPA to `build/export/`. The export profile uses manual development signing. The user may replace it with an equivalent profile generated by their own Xcode account and team. TestFlight and App Store Connect are outside the current distribution scope.

For build-only archive verification:

```bash
CODE_SIGNING_ALLOWED=NO \
CODE_SIGNING_REQUIRED=NO \
./scripts/archive-ios.sh
```

That archive is suitable for verifying build output and requires a valid user signature before installation.

## Development workflow

1. Read the relevant plan and constraints in `../EspBluFiNextPlans`.
2. Change the smallest owning module.
3. Run `xcodegen generate` after project-definition changes.
4. Run package tests for protocol or security changes.
5. Run App tests and a simulator build for UI, coordinator, diagnostics, or localization changes.
6. Use a real iPhone/iPad and ESP hardware for CoreBluetooth scanning, connection, GATT writes, notifications, security negotiation, Wi-Fi provisioning, and disconnect behavior.
7. Review `git diff --check`, inspect generated artifacts, and commit only the intended tracked files.

Use fake transport tests for deterministic protocol failures. Treat simulator results as UI and state evidence. Treat real-device results as BLE and firmware compatibility evidence.

## Change scope and Git workflow

- Substantive implementation changes use an `agent/<description>` branch and a PR after the work is complete. This includes runtime behavior, navigation or state ownership, protocol/security logic, data handling, dependencies, build or release configuration, tests, and performance work.
- Non-substantive presentation changes may be committed and pushed directly to `main` when they are limited to screenshots, promotional compositions, marketing artwork, copy, README/docs wording, or visual asset placement. Review the rendered result and run `git diff --check` before pushing.
- When a change combines presentation work with runtime behavior or has an unclear boundary, use the branch-and-PR workflow.

## Build iOS Apps plugin workflow

Use the smallest relevant skill for the task:

- `swiftui-ui-patterns`: app shell, navigation, state ownership, screen composition, and previews.
- `swiftui-liquid-glass`: every Liquid Glass implementation or review on iOS 26.
- `swiftui-view-refactor`: large SwiftUI views, mixed business logic, or broad state ownership.
- `ios-debugger-agent`: build, launch, inspect, interact with, and capture logs from a booted simulator.
- `ios-simulator-browser`: browser-visible simulator evidence or SwiftUI Preview hot reload.
- `swiftui-performance-audit`: initial code review for refresh, layout, list identity, and main-thread costs.
- `ios-ettrace-performance`: one trace-backed flow after a reproducible performance symptom.
- `ios-memgraph-leaks`: ownership-path evidence after reproducible memory growth.
- `ios-app-intents`: only after the system-entry scope is approved; keep intents thin and route through `AppCoordinator`.

Simulator automation, ETTrace, and memgraph provide runtime evidence. CoreBluetooth and BluFi protocol compatibility conclusions require real-device validation.

## Security and diagnostics rules

- Wi-Fi passwords are sent once for provisioning and are not retained in session state or diagnostics.
- Diagnostic exports are redacted by default. Preserve byte counts and protocol metadata while excluding credentials, keys, certificates, and raw sensitive payloads.
- Do not log private keys, session keys, Wi-Fi passwords, or unredacted custom data.
- Keep custom-data format conversion in `BluFiPayloadCodec`; keep wire-format details in BluFiKit.
- Preserve explicit user actions for sharing or exporting diagnostics.

## Current compatibility boundary

The confirmed hardware baseline is ESP32-S3, ESP-IDF 5.5.2, BluFi 1.3, Security V1, and Station provisioning. Additional chips, ESP-IDF 6.x/V2, SoftAP/APSTA behavior, and broader firmware matrices require separate real-device validation.

App Intents, Siri, Shortcuts, and Spotlight entry points remain deferred. Performance work follows measurement-first evidence; use a fixed scan → connect → secure session → status → Wi-Fi scan → provisioning → disconnect flow for comparisons.
