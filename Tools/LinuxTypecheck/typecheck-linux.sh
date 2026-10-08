#!/usr/bin/env bash
#
# Typechecks Osmium's engine and model layer on Linux.
#
# Apple frameworks (CoreGraphics, CoreImage, ImageIO, UniformTypeIdentifiers,
# AppKit) do not exist off macOS, so this builds a hand-written stub of the
# surface we use and runs the compiler over Sources/Osmium/{Core,Model}.
#
# What this catches: syntax, type errors, bad optional handling, wrong closures,
# Sendable/conformance mistakes, arithmetic mistakes.
# What this does NOT catch: mismatches against Apple's real SDK signatures, and
# anything in Sources/Osmium/App (SwiftUI has no realistic Linux stub).
#
# On a Mac, prefer:  swift build
#
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFTC="${SWIFTC:-swiftc}"
MODULES="Tools/LinuxTypecheck/Modules"
OUT="Tools/LinuxTypecheck/build"
APP="Sources/Osmium"

rm -rf "$OUT"
mkdir -p "$OUT"

# Stubs are throwaway shims: Swift 5 + -suppress-warnings keeps them free of
# diagnostics that say nothing about the app code.
echo "==> Building stub modules"
"$SWIFTC" -swift-version 5 -suppress-warnings -emit-module -module-name CoreGraphics \
    -emit-module-path "$OUT/CoreGraphics.swiftmodule" "$MODULES/CoreGraphics.swift"
"$SWIFTC" -swift-version 5 -suppress-warnings -emit-module -module-name CoreImage -I "$OUT" \
    -emit-module-path "$OUT/CoreImage.swiftmodule" "$MODULES/CoreImage.swift"
"$SWIFTC" -swift-version 5 -suppress-warnings -emit-module -module-name ImageIO -I "$OUT" \
    -emit-module-path "$OUT/ImageIO.swiftmodule" "$MODULES/ImageIO.swift"
"$SWIFTC" -swift-version 5 -suppress-warnings -emit-module -module-name UniformTypeIdentifiers \
    -emit-module-path "$OUT/UniformTypeIdentifiers.swiftmodule" "$MODULES/UniformTypeIdentifiers.swift"
"$SWIFTC" -swift-version 5 -suppress-warnings -emit-module -module-name AppKit -I "$OUT" \
    -emit-module-path "$OUT/AppKit.swiftmodule" "$MODULES/AppKit.swift"

echo "==> Typechecking engine + model"
"$SWIFTC" -swift-version 5 -typecheck -I "$OUT" \
    "$APP"/Core/*.swift "$APP"/Model/*.swift

echo "==> OK"
