#!/usr/bin/env bash
#
# Builds Caesium.app for Apple silicon.
#
#   ./build.sh              release build
#   ./build.sh debug        debug build
#   ./build.sh run          build, then launch
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    debug)   CONFIG="debug" ;;
    release) CONFIG="release" ;;
    run)     LAUNCH=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Caesium only builds on macOS." >&2
  exit 1
fi

# Preflight: the macOS 26+ SDK implements @State/@Binding/@Environment as macros
# that live in the SwiftUIMacros compiler plugin. The Command Line Tools package
# does not ship that plugin, so a CLT-only setup fails with dozens of confusing
# "external macro implementation ... could not be found" errors. Catch it here.
DEV_DIR="$(xcode-select -p)"
PLUGIN_DIR=""
for candidate in \
  "$DEV_DIR/usr/lib/swift/host/plugins" \
  "$DEV_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
  "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins"; do
  if compgen -G "$candidate/libSwiftUIMacros*" > /dev/null 2>&1; then
    PLUGIN_DIR="$candidate"
    break
  fi
done
if [[ -z "$PLUGIN_DIR" ]]; then
  PLUGIN_DIR="$DEV_DIR/usr/lib/swift/host/plugins"
  cat >&2 <<EOF
error: the active developer directory has no SwiftUIMacros plugin.

  developer dir : $DEV_DIR
  plugin dir    : $PLUGIN_DIR

This build of the Command Line Tools cannot expand SwiftUI's @State/@Environment
macros. Install the full Xcode app and point xcode-select at it:

  1. Download Xcode from https://developer.apple.com/xcode/ (or the App Store)
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. sudo xcodebuild -runFirstLaunch
  4. rm -rf .build && ./build.sh

To check what you have:  ls "$PLUGIN_DIR"
EOF
  exit 1
fi

echo "==> Building (${CONFIG}, $(uname -m)) using $DEV_DIR"
swift build -c "$CONFIG" --arch arm64

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
APP="build/Caesium.app"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Caesium" "$APP/Contents/MacOS/Caesium"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "note: Resources/AppIcon.icns not found — the app will use the default icon."
fi

# Ad-hoc signature: enough for local use, replace with a Developer ID for distribution.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null \
  || echo "warning: ad-hoc signing failed; the app may need a Gatekeeper override."

echo "==> Done: $APP"

if [[ "$LAUNCH" -eq 1 ]]; then
  open "$APP"
fi
