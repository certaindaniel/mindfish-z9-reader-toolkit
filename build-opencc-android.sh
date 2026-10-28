#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$ROOT_DIR/opencc.koplugin"
NDK_DIR="${ANDROID_NDK_HOME:-}"
OPENCC_DATA_DIR="${OPENCC_DATA_DIR:-}"
OPENCC_VERSION="1.4.2"
OPENCC_URL="https://github.com/BYVoid/OpenCC/archive/refs/tags/ver.1.4.2.tar.gz"
OPENCC_SHA256="8e5f5cf7fe195bd9b9be851adc9738c1ef7dc5c24441dd5878a56db4087a9a70"

if [[ -z "$NDK_DIR" || ! -f "$NDK_DIR/source.properties" ]]; then
    echo "Set ANDROID_NDK_HOME to Android NDK r24 (API 19 support is required)." >&2
    exit 2
fi
if ! grep -q 'Pkg.Revision = 24\.' "$NDK_DIR/source.properties"; then
    echo "This device needs an NDK that supports API 19; use NDK r24." >&2
    exit 2
fi

if [[ -z "$OPENCC_DATA_DIR" ]]; then
    OPENCC_DATA_DIR="$(brew --prefix opencc)/share/opencc"
fi
if [[ ! -f "$OPENCC_DATA_DIR/s2twp.json" ]]; then
    echo "OpenCC 1.4.2 data was not found at: $OPENCC_DATA_DIR" >&2
    exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/z9-opencc-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
ARCHIVE="$WORK_DIR/opencc.tar.gz"
SOURCE_DIR="$WORK_DIR/source"
BUILD_DIR="$WORK_DIR/build"

curl --fail --location --silent --show-error "$OPENCC_URL" -o "$ARCHIVE"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$OPENCC_SHA256" ]]; then
    echo "OpenCC source archive checksum mismatch." >&2
    exit 2
fi
mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_DIR/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=armeabi-v7a \
    -DANDROID_PLATFORM=android-19 \
    -DANDROID_STL=c++_static \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_DOCUMENTATION=OFF \
    -DENABLE_GTEST=OFF \
    -DENABLE_BENCHMARK=OFF \
    -DBUILD_PYTHON=OFF \
    -DBUILD_OPENCC_JIEBA_PLUGIN=OFF \
    -DOPENCC_ENABLE_INSTALL=OFF \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --target opencc --parallel

STRIP="$NDK_DIR/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip"
"$STRIP" --strip-all -o "$PLUGIN_DIR/native/armv7/opencc" "$BUILD_DIR/src/tools/opencc"
chmod 755 "$PLUGIN_DIR/native/armv7/opencc"

mkdir -p "$PLUGIN_DIR/data" "$PLUGIN_DIR/licenses"
cp "$SOURCE_DIR/data/config/s2twp.json" "$PLUGIN_DIR/data/"
for name in \
    CJK_Compatibility_Ideographs \
    STPhrases_GeneratedFromRegionalPhrases \
    STPhrases STCharacters TWPhrases TWVariantsPhrases TWVariants; do
    cp "$OPENCC_DATA_DIR/$name.ocd2" "$PLUGIN_DIR/data/"
done
cp "$SOURCE_DIR/LICENSE" "$PLUGIN_DIR/licenses/OpenCC-LICENSE.txt"
cp "$SOURCE_DIR/deps/marisa-0.3.1/COPYING.md" "$PLUGIN_DIR/licenses/Marisa-COPYING.md"
cp "$SOURCE_DIR/deps/darts-clone-0.32h/COPYING.md" "$PLUGIN_DIR/licenses/Darts-COPYING.md"

echo "Built OpenCC $OPENCC_VERSION for Android armeabi-v7a/API 19."
