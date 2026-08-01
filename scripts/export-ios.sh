#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

ARCHIVE_PATH="${ARCHIVE_PATH:-build/archive/EspBlufiNext.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-Config/ExportOptions.plist}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"

[[ -d "$ARCHIVE_PATH" ]] || {
    printf 'Archive not found: %s\nRun ./scripts/archive-ios.sh first.\n' "$ARCHIVE_PATH" >&2
    exit 1
}

[[ -f "$EXPORT_OPTIONS_PATH" ]] || {
    printf 'Export options not found: %s\nCopy Config/ExportOptions.plist.example and configure your Team ID and profile.\n' "$EXPORT_OPTIONS_PATH" >&2
    exit 1
}

plutil -lint "$EXPORT_OPTIONS_PATH" >/dev/null || {
    printf 'Invalid export options plist: %s\n' "$EXPORT_OPTIONS_PATH" >&2
    exit 1
}

if grep -Eq 'YOUR_(TEAM_ID|PROFILE_NAME)' "$EXPORT_OPTIONS_PATH"; then
    printf 'Export options still contain placeholders: %s\n' "$EXPORT_OPTIONS_PATH" >&2
    exit 1
fi

mkdir -p "$EXPORT_PATH"

XCODEBUILD_ARGS=(
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH"
)

if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
    XCODEBUILD_ARGS+=(-allowProvisioningUpdates)
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"

printf 'Exported artifacts:\n'
find "$EXPORT_PATH" -maxdepth 1 -type f \( -name '*.ipa' -o -name '*.dSYM.zip' \) -print
