#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_DIR="$ROOT_DIR/fonts"
REMOTE_KOREADER_FONTS="/storage/emulated/0/koreader/fonts"
REMOTE_SYSTEM_FONTS="/storage/emulated/0/Fonts"
REMOTE_DUOKAN_FONTS="/storage/emulated/0/DuoKan/Base/Fonts"
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
    "$REMOTE_KOREADER_FONTS" \
    "$REMOTE_SYSTEM_FONTS" \
    "$REMOTE_DUOKAN_FONTS" </dev/null

for font in "$FONTS_DIR"/*.ttf "$FONTS_DIR"/*.otf; do
    [[ -f "$font" ]] || continue
    font_name="${font##*/}"
    printf 'Installing %s ...\n' "$font_name"
    adb_push "$font" "$REMOTE_KOREADER_FONTS/$font_name"
    adb_push "$font" "$REMOTE_SYSTEM_FONTS/$font_name"
    adb_push "$font" "$REMOTE_DUOKAN_FONTS/$font_name"
done

printf 'Fonts installed successfully to KOReader, system Fonts, and DuoKan.\n'
