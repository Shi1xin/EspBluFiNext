#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/archive/EspBlufiNext.xcarchive}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/derived-release}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-YES}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-}"

command -v xcodegen >/dev/null || {
    printf 'xcodegen is required: brew install xcodegen\n' >&2
    exit 1
}

xcodegen generate

mkdir -p "$(dirname "$ARCHIVE_PATH")"

XCODEBUILD_ARGS=(
    -project EspBlufiNext.xcodeproj
    -scheme EspBlufiNext
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -archivePath "$ARCHIVE_PATH"
    -derivedDataPath "$DERIVED_DATA_PATH"
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED"
    CODE_SIGNING_REQUIRED="$CODE_SIGNING_REQUIRED"
)

if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
    XCODEBUILD_ARGS+=(-allowProvisioningUpdates)
fi

if [[ -n "$MARKETING_VERSION" ]]; then
    XCODEBUILD_ARGS+=(MARKETING_VERSION="$MARKETING_VERSION")
fi

if [[ -n "$CURRENT_PROJECT_VERSION" ]]; then
    XCODEBUILD_ARGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION")
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" archive

printf 'Archive created at %s\n' "$ARCHIVE_PATH"
