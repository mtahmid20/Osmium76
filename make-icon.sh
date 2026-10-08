#!/usr/bin/env bash
#
# Draws Resources/AppIcon.icns — a rounded gradient tile with a "C".
# Requires macOS (uses Core Graphics through a tiny Swift script).
#
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/icon.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

func makeIcon(size: Int) -> Data? {
    let pixels = size
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let inset = CGFloat(pixels) * 0.085
    let tile = rect.insetBy(dx: inset, dy: inset)
    let radius = tile.width * 0.2237

    context.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1))
    context.fill(rect)

    let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colors = [
        CGColor(red: 0.36, green: 0.72, blue: 1.00, alpha: 1),
        CGColor(red: 0.24, green: 0.42, blue: 0.98, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.minX, y: tile.maxY),
            end: CGPoint(x: tile.maxX, y: tile.minY),
            options: []
        )
    }

    // Chevrons suggesting compression.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    context.setLineWidth(CGFloat(pixels) * 0.052)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let unit = tile.width
    func chevron(_ yFactor: CGFloat, scale: CGFloat) {
        let width = unit * 0.30 * scale
        let height = unit * 0.15 * scale
        let cx = tile.midX
        let cy = tile.minY + unit * yFactor
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - width, y: cy + height))
        path.addLine(to: CGPoint(x: cx, y: cy - height * 0.4))
        path.addLine(to: CGPoint(x: cx + width, y: cy + height))
        context.addPath(path)
        context.strokePath()
    }
    chevron(0.70, scale: 1.0)
    chevron(0.45, scale: 0.72)

    context.restoreGState()

    guard let image = context.makeImage() else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = NSSize(width: size, height: size)
    return bitmap.representation(using: .png, properties: [:])
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
var written: [String] = []
for size in sizes {
    guard let data = makeIcon(size: size) else { continue }
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    let path = CommandLine.arguments[1] + "/" + name
    try? data.write(to: URL(fileURLWithPath: path))
    written.append(name)
}
print(written.joined(separator: "\n"))
SWIFT

swiftc -O "$WORK/icon.swift" -o "$WORK/makeicon"
mkdir -p "$WORK/AppIcon.iconset"
"$WORK/makeicon" "$WORK/AppIcon.iconset" > /dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
