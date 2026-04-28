#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/ClipboardShelf.xcodeproj"
SCHEME="ClipboardShelf"
BUILD_DIR="$PROJECT_DIR/.xcode-build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/ClipboardShelf.app"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/ClipboardShelf-macOS.zip"

mkdir -p "$DIST_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build

rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

echo "Release archive created at: $ARCHIVE_PATH"
