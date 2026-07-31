#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/derived}"

command -v xcodegen >/dev/null || {
    printf 'xcodegen is required: brew install xcodegen\n' >&2
    exit 1
}

xcodegen generate

XCODEBUILD_ARGS=(
    -project EspBlufiNext.xcodeproj
    -scheme EspBlufiNext
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ "$DESTINATION" == *Simulator* ]]; then
    XCODEBUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO)
else
    XCODEBUILD_ARGS+=(-allowProvisioningUpdates)
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build
