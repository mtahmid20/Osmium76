#!/usr/bin/env bash
#
# Draws Resources/AppIcon.icns for Osmium.
#
# The mark is an osmium crystal: a hexagonal atomic-lattice motif over a deep
# graphite tile, with a downward compression arrow cutting through the centre.
# Osmium is the densest naturally occurring element, which is the joke the name
# is built on, and the arrow keeps it reading as a compressor at 16 px.
#
# Requires macOS (uses Core Graphics through a small Swift script).
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

    // All geometry below is authored in a 1024-unit square and scaled, so the
    // small sizes in the set are the same drawing rather than a separate one.
    let scale = CGFloat(pixels) / 1024.0
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    func u(_ v: CGFloat) -> CGFloat { v * scale }

    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)

    let tileInset: CGFloat = 96
    let tile = canvas.insetBy(dx: tileInset, dy: tileInset)
    let radius = tile.width * 0.2237

    // Tile body: a near-black graphite that lets the lattice glow.
    context.setFillColor(CGColor(red: 0.055, green: 0.063, blue: 0.086, alpha: 1))
    context.fill(canvas)

    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Vertical gradient: cool slate at the top falling to almost black.
    let bodyColors = [
        CGColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1),
        CGColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: bodyColors,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }

    // One bold hexagonal crystal rather than a honeycomb: a glyph has to
    // survive being drawn 16 px wide, and a lattice of 20 hexagons turned to
    // mush there. A single outline stays readable at every size.
    let hexRadius = u(330)
    let hexPath = CGMutablePath()
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3 + .pi / 6
        let point = CGPoint(x: tile.midX + hexRadius * cos(angle),
                            y: tile.midY + hexRadius * sin(angle))
        if i == 0 { hexPath.move(to: point) } else { hexPath.addLine(to: point) }
    }
    hexPath.closeSubpath()

    context.saveGState()
    // Glow behind the stroke reads as the metal catching light, and keeps the
    // outline from disappearing against the dark tile when scaled down.
    context.setShadow(offset: .zero, blur: u(54), color: CGColor(red: 0.40, green: 0.66, blue: 1.0, alpha: 0.9))
    context.addPath(hexPath)
    context.setStrokeColor(CGColor(red: 0.62, green: 0.85, blue: 1.0, alpha: 1))
    context.setLineWidth(u(36))
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // Compression arrow inside the crystal, one tapered shape so the joins are
    // seamless. Sized to fill roughly two thirds of the hexagon's height.
    context.saveGState()
    context.setShadow(offset: .zero, blur: u(44), color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8))

    let arrow = CGMutablePath()
    let top = tile.midY + u(184)
    let tip = tile.midY - u(158)
    let halfShaft = u(58)
    let halfShoulder = u(190)
    let shoulderY = tip + u(120)

    arrow.move(to: CGPoint(x: tile.midX - halfShaft, y: top))
    arrow.addLine(to: CGPoint(x: tile.midX + halfShaft, y: top))
    arrow.addLine(to: CGPoint(x: tile.midX + halfShaft, y: shoulderY))
    arrow.addLine(to: CGPoint(x: tile.midX + halfShoulder, y: shoulderY))
    arrow.addLine(to: CGPoint(x: tile.midX, y: tip))
    arrow.addLine(to: CGPoint(x: tile.midX - halfShoulder, y: shoulderY))
    arrow.addLine(to: CGPoint(x: tile.midX - halfShaft, y: shoulderY))
    arrow.closeSubpath()

    context.addPath(arrow)
    context.setFillColor(CGColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Top highlight, the standard way to keep a tile from looking flat.
    let sheenColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.20),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    if let sheen = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: sheenColors,
        locations: [0, 1]
    ) {
        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.midY),
            options: []
        )
        context.restoreGState()
    }

    // Inner hairline for edge definition on light backgrounds.
    context.addPath(tilePath)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    context.setLineWidth(u(4))
    context.strokePath()

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

# Also leave a 512px PNG next to the bundle so the mark is easy to reuse.
cp "$WORK/AppIcon.iconset/icon_512x512@2x.png" Resources/OsmiumIcon.png
echo "Wrote Resources/OsmiumIcon.png"
