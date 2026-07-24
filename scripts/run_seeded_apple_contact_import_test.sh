#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/D2D Advancer.xcodeproj"
FIXTURE_PATH="$ROOT_DIR/D2D AdvancerUITests/Fixtures/AppleContactImportFixture.vcf"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
BUNDLE_ID="dan1sland.D2D-Advancer"
TEST_NAME="D2D AdvancerUITests/D2D_AdvancerUITests/testAppleContactImportSeededStoreFlow"
SIMULATOR_ID=""
DERIVED_DATA_PATH=""

cleanup() {
    if [[ -n "$SIMULATOR_ID" ]]; then
        xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
        xcrun simctl delete "$SIMULATOR_ID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$DERIVED_DATA_PATH" ]]; then
        rm -rf "$DERIVED_DATA_PATH"
    fi
}
trap cleanup EXIT INT TERM

SIMULATOR_ID="$(
    xcrun simctl create \
        "D2D Contacts Import QA $$" \
        "$DEVICE_TYPE"
)"
DERIVED_DATA_PATH="${TMPDIR:-/tmp}/D2DContactsImportUITest-$SIMULATOR_ID"

xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl addmedia "$SIMULATOR_ID" "$FIXTURE_PATH"
xcrun simctl privacy "$SIMULATOR_ID" grant contacts "$BUNDLE_ID"

xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "D2D Advancer" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -only-testing:"$TEST_NAME" \
    -skipMacroValidation \
    -collect-test-diagnostics never \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    ONLY_ACTIVE_ARCH=YES \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) D2D_SEEDED_CONTACT_IMPORT_TEST' \
    test

echo "Seeded Apple Contacts import test passed."
