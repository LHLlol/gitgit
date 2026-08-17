#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-macosx/release"
APP_DIR="$PROJECT_ROOT/PushDock.app"

cd "$PROJECT_ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/PushDock" "$APP_DIR/Contents/MacOS/PushDock"
chmod +x "$APP_DIR/Contents/MacOS/PushDock"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
