#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-D2D Advancer.xcodeproj}"
SCHEME="${SCHEME:-D2D Advancer}"
OWNER_DEVICE_ID="${TEAM_OWNER_DEVICE_ID:-00008150-001C508C0C04401C}"
REP_DEVICE_ID="${TEAM_REP_DEVICE_ID:-00008130-000131D814BA001C}"
FLOW_MODE="${TEAM_PHYSICAL_FLOW_MODE:-full}"
RUN_ID="${D2D_TEAM_UI_RUN_ID:-phys$(date +%s)}"
PASSWORD="${D2D_TEAM_UI_PASSWORD:-testpass123}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/DerivedDataPhysicalTeamFullFlow}"
SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-/tmp/D2DPhysicalTeamSourcePackages-${RUN_ID}}"
DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID:-RF247ARQB7}"
XCODEBUILD_TIMEOUT_SECONDS="${XCODEBUILD_TIMEOUT_SECONDS:-900}"
SCRIPT_PATH="${BASH_SOURCE[0]}"

detect_emulator_host() {
  local host=""
  local interface=""

  for interface in en0 en1 en2; do
    host="$(ipconfig getifaddr "${interface}" 2>/dev/null || true)"
    if [[ -n "${host}" ]]; then
      printf '%s\n' "${host}"
      return 0
    fi
  done

  interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"
  if [[ -n "${interface}" ]]; then
    host="$(ipconfig getifaddr "${interface}" 2>/dev/null || true)"
    if [[ -n "${host}" ]]; then
      printf '%s\n' "${host}"
      return 0
    fi
  fi

  return 1
}

if [[ "${D2D_PHYSICAL_TEAM_INSIDE_EMULATORS:-0}" != "1" ]]; then
  export D2D_PHYSICAL_TEAM_INSIDE_EMULATORS=1
  export D2D_FIREBASE_EMULATOR_HOST="${D2D_FIREBASE_EMULATOR_HOST:-$(detect_emulator_host || true)}"
  if [[ -z "${D2D_FIREBASE_EMULATOR_HOST}" ]]; then
    echo "Could not determine D2D_FIREBASE_EMULATOR_HOST. Set it to this Mac's LAN IP reachable from both iPhones." >&2
    exit 1
  fi

  echo "Starting Firebase emulators for physical Team flow..."
  exec env JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" \
    /Users/dan1sland/.npm-global/bin/firebase emulators:exec \
      --only auth,firestore \
      --project d2d-advancer \
      "bash \"${SCRIPT_PATH}\""
fi

if [[ -z "${D2D_FIREBASE_EMULATOR_HOST:-}" ]]; then
  D2D_FIREBASE_EMULATOR_HOST="$(detect_emulator_host || true)"
fi

if [[ -z "${D2D_FIREBASE_EMULATOR_HOST}" ]]; then
  echo "Could not determine D2D_FIREBASE_EMULATOR_HOST. Set it to this Mac's LAN IP reachable from both iPhones." >&2
  exit 1
fi

if [[ "${FLOW_MODE}" != "full" && "${FLOW_MODE}" != "owner" ]]; then
  echo "Invalid TEAM_PHYSICAL_FLOW_MODE='${FLOW_MODE}'. Use 'full' or 'owner'." >&2
  exit 1
fi

DESTINATION_LIST="$(xcodebuild -showdestinations -project "${PROJECT_PATH}" -scheme "${SCHEME}" 2>/dev/null || true)"
DEVICE_LIST="$(xcrun xctrace list devices 2>/dev/null || true)"

require_online_device() {
  local device_id="$1"
  local label="$2"

  if ! printf '%s\n' "${DESTINATION_LIST}" | awk -v id="${device_id}" '
    /Available destinations/ { destinations = 1; next }
    destinations && index($0, "platform:iOS") && index($0, "id:" id) { found = 1 }
    END { exit(found ? 0 : 1) }
  '; then
    echo "${label} device is not online for Xcode UI testing: ${device_id}" >&2
    echo "Connect the phone by USB, unlock it, trust this Mac, and approve UI automation if prompted." >&2
    echo "Current xcodebuild destinations:" >&2
    printf '%s\n' "${DESTINATION_LIST}" >&2
    echo "Current xctrace device state, for comparison:" >&2
    printf '%s\n' "${DEVICE_LIST}" >&2
    exit 1
  fi
}

require_online_device "${OWNER_DEVICE_ID}" "Owner"
if [[ "${FLOW_MODE}" == "full" ]]; then
  require_online_device "${REP_DEVICE_ID}" "Rep"
fi

run_team_test() {
  local device_id="$1"
  local test_name="$2"
  local log_dir="/tmp/d2d_physical_team_logs"
  local log_file="${log_dir}/${RUN_ID}_${test_name}.log"

  mkdir -p "${log_dir}"

  set +e
  CLANG_MODULE_CACHE_PATH=/tmp/D2DPhysicalTeamClangModuleCache \
  SWIFTPM_MODULECACHE_PATH=/tmp/D2DPhysicalTeamSwiftPMModuleCache \
  D2D_FIREBASE_EMULATOR_HOST="${D2D_FIREBASE_EMULATOR_HOST}" \
  D2D_RUN_TEAM_PHYSICAL_UI_TESTS=1 \
  D2D_TEAM_UI_RUN_ID="${RUN_ID}" \
  D2D_TEAM_UI_PASSWORD="${PASSWORD}" \
  D2D_TEAM_INVITE_CODE="${D2D_TEAM_INVITE_CODE:-}" \
  /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec failed: $!"' "${XCODEBUILD_TIMEOUT_SECONDS}" \
    xcodebuild test \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS,id=${device_id}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    D2D_DEFAULT_FIREBASE_EMULATOR_HOST="${D2D_FIREBASE_EMULATOR_HOST}" \
    D2D_TEAM_UI_RUN_ID="${RUN_ID}" \
    D2D_TEAM_UI_PASSWORD="${PASSWORD}" \
    D2D_TEAM_INVITE_CODE="${D2D_TEAM_INVITE_CODE:-}" \
    -parallel-testing-enabled NO \
    -only-testing:"D2D AdvancerUITests/D2D_AdvancerUITests/${test_name}" 2>&1 | tee "${log_file}"
  local status="${PIPESTATUS[0]}"
  set -e

  if [[ "${status}" -ne 0 ]]; then
    echo "Physical Team test '${test_name}' failed. Log: ${log_file}" >&2
    if [[ "${status}" -eq 142 || "${status}" -eq 14 ]]; then
      echo "xcodebuild timed out after ${XCODEBUILD_TIMEOUT_SECONDS}s." >&2
    fi
    if grep -E -q "Unlock .* to Continue|because the device is locked|Waiting for the destination to become ready" "${log_file}"; then
      echo "Xcode is waiting on a locked or unavailable physical device." >&2
      echo "Unlock the iPhone, keep it on the home screen, trust this Mac, and rerun the script." >&2
    fi
    if grep -q "Timed out while enabling automation mode" "${log_file}"; then
      echo "Xcode could not enable UI automation on the device." >&2
      echo "Unlock the iPhone, keep it on the home screen, accept any Developer Mode/UI Automation prompt, then rerun this script." >&2
    fi
    exit "${status}"
  fi
}

read_invite_code_from_owner_log() {
  local log_file="/tmp/d2d_physical_team_logs/${RUN_ID}_testTeamPhysicalOwnerCreatesTeamAndInvite.log"
  local invite_code

  invite_code="$(
    awk -F= '/TEAM_PHYSICAL_INVITE_CODE=/ { code = $2 } END { print code }' "${log_file}" 2>/dev/null \
      | tr -d '[:space:]'
  )"

  if [[ "${invite_code}" =~ ^[A-Z0-9]{8}$ ]]; then
    printf '%s\n' "${invite_code}"
    return 0
  fi

  return 1
}

echo "Using Firebase emulator host: ${D2D_FIREBASE_EMULATOR_HOST}"
echo "Using Team UI run id: ${RUN_ID}"
echo "Using physical flow mode: ${FLOW_MODE}"

run_team_test "${OWNER_DEVICE_ID}" "testTeamPhysicalOwnerCreatesTeamAndInvite"

if [[ "${FLOW_MODE}" == "owner" ]]; then
  echo "Owner-only physical Team smoke completed. Skipping rep join and owner sync verification."
  exit 0
fi

if ! D2D_TEAM_INVITE_CODE="$(read_invite_code_from_owner_log)"; then
  echo "Could not read TEAM_PHYSICAL_INVITE_CODE from the owner test log." >&2
  echo "Do not fall back to a generic latest invite; that can join the rep to the wrong stale team." >&2
  echo "Owner log: /tmp/d2d_physical_team_logs/${RUN_ID}_testTeamPhysicalOwnerCreatesTeamAndInvite.log" >&2
  exit 1
fi
export D2D_TEAM_INVITE_CODE
echo "Using invite code for rep join: ${D2D_TEAM_INVITE_CODE}"

run_team_test "${REP_DEVICE_ID}" "testTeamPhysicalRepJoinsAndCreatesInterestedLead"
run_team_test "${OWNER_DEVICE_ID}" "testTeamPhysicalOwnerSeesRepWork"
