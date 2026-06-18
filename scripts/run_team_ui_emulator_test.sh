#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-D2D Advancer.xcodeproj}"
SCHEME="${SCHEME:-D2D Advancer}"
TEAM_UI_TEST="${TEAM_UI_TEST:-D2D AdvancerUITests/D2D_AdvancerUITests/testTeamWorkspaceFirebaseAccountInviteJoinLeadAndOwnerAlert}"

if [[ -n "${TEAM_UI_TEST_SIMULATOR_ID:-}" ]]; then
  DESTINATION="platform=iOS Simulator,id=${TEAM_UI_TEST_SIMULATOR_ID}"
else
  TEAM_UI_TEST_SIMULATOR_ID="$(
    xcrun simctl list devices available \
      | sed -n 's/.*D2D-Team-Owner-Test (\([A-F0-9-]*\)) (.*/\1/p' \
      | head -n 1
  )"
  if [[ -n "${TEAM_UI_TEST_SIMULATOR_ID}" ]]; then
    DESTINATION="platform=iOS Simulator,id=${TEAM_UI_TEST_SIMULATOR_ID}"
  else
    DESTINATION="${TEAM_UI_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
  fi
fi

xcodebuild test \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -parallel-testing-enabled NO \
  -only-testing:"${TEAM_UI_TEST}"
