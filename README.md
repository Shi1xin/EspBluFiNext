# EspBluFiNext

Modern iOS 26 BluFi diagnostic client. The Xcode project is generated from `project.yml`; the generated `.xcodeproj` stays out of version control.

## One-time machine setup

Run these commands in Terminal:

```bash
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
brew install xcodegen
```

Verify the selected toolchain:

```bash
xcode-select -p
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-version
```

The selected developer directory should be the Xcode beta bundle, rather than `/Library/Developer/CommandLineTools`.

## Project setup

Set the Apple Development team used for a physical iPhone build:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Edit Config/Local.xcconfig and replace YOUR_TEAM_ID.
```

Generate and build the iOS 26 simulator target:

```bash
./scripts/build-ios.sh
```

The script uses XcodeGen, `xcodebuild`, and an unsigned simulator build. A physical-device build uses the signing team from `Config/Local.xcconfig`:

```bash
DESTINATION='generic/platform=iOS' ./scripts/build-ios.sh
```

## GitHub build and self-signing

The project is distributed as source code. Each user creates the signed archive and IPA with their own Apple Development team, certificate, bundle ID, and provisioning profile.

Set the local signing team once:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Edit Config/Local.xcconfig and set DEVELOPMENT_TEAM to your Team ID.
```

Create the export profile configuration from the checked-in template:

```bash
cp Config/ExportOptions.plist.example Config/ExportOptions.plist
# Set teamID and the development provisioning profile name for com.espblufi.next.
```

Create a Release archive:

```bash
MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=1 ./scripts/archive-ios.sh
```

Export the signed IPA for sideloading:

```bash
./scripts/export-ios.sh
```

The archive is written to `build/archive/` and exported files are written to `build/export/`. `Config/Local.xcconfig`, `Config/ExportOptions.plist`, archives, and exported packages remain local and are ignored by Git. The generated IPA is signed for the Team ID and profile configured by the user; install it with the user's preferred sideloading tool.

For a local unsigned archive smoke test, use `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ./scripts/archive-ios.sh`. That archive is useful for build verification and requires signing and export with a valid profile before installation.

## Architecture

- `Sources/EspBlufiNext`: SwiftUI and iOS integration.
- `Packages/BluFiKit`: transport-independent BluFi protocol package.
- `Tests/EspBlufiNextTests`: app-level tests.
- `project.yml`: project source of truth.

The first UI scaffold contains Devices, Session, and Logs tabs. BluFi packet framing, security negotiation, and CoreBluetooth transport will be added inside `BluFiKit` and the iOS integration layer.

## Phase 0 baseline

The first hardware target is an ESP32-S3 running `xiaozhi v2.2.6` on ESP-IDF `v5.5.2`, connected at `/dev/cu.usbserial-110`. Protocol constants and the Android `lib-blufi` 2.5.1 security-version threshold are covered by `Packages/BluFiKit/Tests`; device-version and security-handshake fixtures remain hardware-validation work.
