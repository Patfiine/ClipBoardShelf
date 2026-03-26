#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/ClipboardShelf.xcodeproj"
SCHEME="ClipboardShelf"
BUILD_DIR="$PROJECT_DIR/.xcode-build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/ClipboardShelf.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP_PATH="$TARGET_DIR/ClipboardShelf.app"

mkdir -p "$TARGET_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build

rm -rf "$TARGET_APP_PATH"
cp -R "$APP_PATH" "$TARGET_APP_PATH"

echo "Installed to: $TARGET_APP_PATH"
