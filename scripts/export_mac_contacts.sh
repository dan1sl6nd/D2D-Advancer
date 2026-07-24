#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
OUTPUT_PATH="${1:-$HOME/Desktop/D2D-Contacts-$STAMP.json}"
OUTPUT_DIR="$(dirname -- "$OUTPUT_PATH")"
TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/d2d-contacts.XXXXXX")"

cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
/usr/bin/osascript -l JavaScript "$SCRIPT_DIR/export_mac_contacts.js" > "$TEMP_FILE"
if [[ -x /usr/bin/jq ]]; then
    /usr/bin/jq -e '
        .schemaVersion == 1 and
        (.source == "macOS Contacts") and
        (.contacts | type == "array")
    ' "$TEMP_FILE" > /dev/null
elif [[ ! -s "$TEMP_FILE" ]]; then
    printf 'The Contacts export was empty.\n' >&2
    exit 1
fi
chmod 600 "$TEMP_FILE"
mv "$TEMP_FILE" "$OUTPUT_PATH"
trap - EXIT

printf 'D2D Advancer contact package created:\n%s\n' "$OUTPUT_PATH"
