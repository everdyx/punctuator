#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/Release"
APP_DIR="$OUTPUT_DIR/Punctuator.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/Punctuator" "$MACOS_DIR/Punctuator"
cp "Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Assets/Punctuator.icns" "$RESOURCES_DIR/Punctuator.icns"

chmod +x "$MACOS_DIR/Punctuator"

echo "$APP_DIR"
