# EspBlufiNext

## Project source of truth

- `project.yml` is the source of truth for the Xcode project.
- Regenerate `EspBlufiNext.xcodeproj` with `xcodegen generate` after changing the project definition or adding source files.
- Keep signing identifiers in `Config/Local.xcconfig`; never commit the local file.
- `Packages/BluFiKit` owns protocol framing, transport-independent state, and BluFi security.
- `Sources/EspBlufiNext` owns SwiftUI and CoreBluetooth integration.

## Commands

```bash
xcodegen generate
swift test --package-path Packages/BluFiKit
./scripts/build-ios.sh
xcodebuild -project EspBlufiNext.xcodeproj -scheme EspBlufiNext -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EspBlufiNext.xcodeproj -scheme EspBlufiNext -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO test
```

Use the full Xcode beta toolchain through `xcode-select` before invoking `xcodebuild`.

## Build iOS Apps Plugin workflow

- Use `swiftui-ui-patterns` for App Shell, navigation, state ownership, screen composition, and previews.
- Use `swiftui-liquid-glass` for every Liquid Glass implementation or review.
- Use `ios-debugger-agent` to build, launch, inspect UI, interact with Simulator, and capture logs after a simulator is already booted.
- Use `ios-simulator-browser` when browser-visible Simulator proof or package-backed preview hot reload is useful.
- Use `swiftui-view-refactor` when a SwiftUI view mixes business logic, owns broad state, or approaches 300 lines.
- Start performance investigations with `swiftui-performance-audit`; use `ios-ettrace-performance` for one trace-backed flow and `ios-memgraph-leaks` for ownership-path leak evidence.
- Use `ios-app-intents` when approved scope includes Shortcuts, Siri, Spotlight, app entities, or external routing. Keep intent types thin and route app-opening actions through the App Coordinator.
- Treat Simulator automation, ETTrace, and memgraph as UI/runtime evidence. Validate CoreBluetooth scanning, writes, notifications, security negotiation, and protocol compatibility on a real iPhone or iPad connected to an ESP device.

The planning map and first App Intents boundary live in `../EspBluFiNextPlans/build-ios-apps-plugin-workflow.md`.
