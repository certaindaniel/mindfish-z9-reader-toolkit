#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$ROOT_DIR/opencc.koplugin"
REMOTE_DATA_DIR="/storage/emulated/0/koreader"
REMOTE_PLUGIN_DIR="$REMOTE_DATA_DIR/plugins/opencc.koplugin"
REMOTE_PRIVATE_DIR="/data/data/org.koreader.launcher/files/opencc"
ADB=(adb)

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    ADB+=( -s "$ANDROID_SERIAL" )
fi

adb_push() {
    local source_file="$1"
    local destination="$2"
    local attempt=1
    while [[ "$attempt" -le 3 ]]; do
        if "${ADB[@]}" push "$source_file" "$destination" >/dev/null; then
            return 0
        fi
        printf 'ADB push attempt %s failed; reconnecting before retry.\n' "$attempt" >&2
        "${ADB[@]}" reconnect device >/dev/null 2>&1 || true
        "${ADB[@]}" wait-for-device
        attempt=$((attempt + 1))
    done
    printf 'Could not copy %s to the Z9.\n' "$source_file" >&2
    return 1
}

"${ADB[@]}" get-state >/dev/null
"${ADB[@]}" shell mkdir -p \
    "$REMOTE_PLUGIN_DIR" \
    "$REMOTE_PLUGIN_DIR/licenses" \
    "$REMOTE_PLUGIN_DIR/data" \
    "$REMOTE_PRIVATE_DIR/data" </dev/null

while IFS= read -r source_file; do
    relative_path="${source_file#"$PLUGIN_DIR"/}"
    adb_push "$source_file" "$REMOTE_PLUGIN_DIR/$relative_path"
done < <(find "$PLUGIN_DIR" -type f ! -path "$PLUGIN_DIR/native/*" -print)

adb_push "$PLUGIN_DIR/native/armv7/opencc" "$REMOTE_PRIVATE_DIR/opencc"
"${ADB[@]}" shell chmod 755 "$REMOTE_PRIVATE_DIR/opencc" </dev/null

while IFS= read -r source_file; do
    file_name="${source_file##*/}"
    adb_push "$source_file" "$REMOTE_PRIVATE_DIR/data/$file_name"
done < <(find "$PLUGIN_DIR/data" -type f -print)

"${ADB[@]}" shell "$REMOTE_PRIVATE_DIR/opencc" --version </dev/null
printf 'Installed KOReader OpenCC plugin to %s\n' "$REMOTE_PLUGIN_DIR"
printf 'Restart KOReader once to load the plugin.\n'
