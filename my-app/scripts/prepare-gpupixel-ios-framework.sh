#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/native/ThirdParty/GPUPixel"
DEST_DIR="$THIRD_PARTY_DIR/ios"
DEST_FRAMEWORK="$DEST_DIR/gpupixel.framework"

GPUPIXEL_REPO="${GPUPIXEL_REPO:-https://github.com/pixpark/gpupixel.git}"
GPUPIXEL_REF="${GPUPIXEL_REF:-main}"
WORK_DIR="${GPUPIXEL_WORK_DIR:-$THIRD_PARTY_DIR/_build/gpupixel-src}"
BUILD_DIR="${GPUPIXEL_BUILD_DIR:-$THIRD_PARTY_DIR/_build/ios-os64}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required; run this script on macOS with Xcode installed" >&2
  exit 1
fi

mkdir -p "$(dirname "$WORK_DIR")" "$BUILD_DIR" "$DEST_DIR"

if [ ! -d "$WORK_DIR/.git" ]; then
  rm -rf "$WORK_DIR"
  git clone --depth 1 --branch "$GPUPIXEL_REF" "$GPUPIXEL_REPO" "$WORK_DIR"
else
  git -C "$WORK_DIR" fetch --depth 1 origin "$GPUPIXEL_REF"
  git -C "$WORK_DIR" checkout FETCH_HEAD
fi

cmake -S "$WORK_DIR" -B "$BUILD_DIR" -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$WORK_DIR/cmake/ios.toolchain.cmake" \
  -DPLATFORM=OS64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DGPUPIXEL_AAPL_FMWK=ON \
  -DGPUPIXEL_BUILD_SHARED_LIBS=ON \
  -DGPUPIXEL_ENABLE_FACE_DETECTOR=OFF \
  -DGPUPIXEL_BUILD_DESKTOP_DEMO=OFF

cmake --build "$BUILD_DIR" --config Release --target gpupixel

FOUND_FRAMEWORK="$(find "$BUILD_DIR" -path "*/Release-iphoneos/gpupixel.framework" -type d -print -quit)"
if [ -z "$FOUND_FRAMEWORK" ]; then
  FOUND_FRAMEWORK="$(find "$BUILD_DIR" -path "*/gpupixel.framework" -type d -print -quit)"
fi

if [ -z "$FOUND_FRAMEWORK" ]; then
  echo "gpupixel.framework was not produced under $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$DEST_FRAMEWORK"
cp -R "$FOUND_FRAMEWORK" "$DEST_FRAMEWORK"

echo "Installed $DEST_FRAMEWORK"
