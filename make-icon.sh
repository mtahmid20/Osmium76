#!/usr/bin/env bash
#
# Draws Resources/AppIcon.icns for Osmium.
#
# The mark is the element itself: "Os" with its atomic number, 76, glowing on a
# deep graphite tile. Osmium is the densest naturally occurring element, which
# is the joke the name is built on, and a periodic-table lockup gives the app an
# identity no generic "down arrow in a box" could.
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

    // "Os" over "76". Drawn with AppKit text rather than paths so the letterforms
    // are the real system face, which stays crisp at every size in the set.
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext

    // Sized off the tile so the lockup keeps its proportions at any resolution.
    let symbolSize = tile.width * 0.40
    let symbol = NSAttributedString(
        string: "Os",
        attributes: [
            .font: NSFont.systemFont(ofSize: symbolSize, weight: .heavy),
            .foregroundColor: NSColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        ]
    )
    let symbolBox = symbol.size()

    // The number sits below with a gap, tight enough to read as one lockup.
    let numberSize = symbolSize * 0.34
    let number = NSAttributedString(
        string: "76",
        attributes: [
            .font: NSFont.systemFont(ofSize: numberSize, weight: .semibold),
            .foregroundColor: NSColor(red: 0.60, green: 0.79, blue: 1.0, alpha: 0.95)
        ]
    )
    let numberBox = number.size()
    let gap = tile.width * 0.05
    let lockupHeight = symbolBox.height + gap + numberBox.height

    // In an unflipped AppKit context a text origin is the bottom of the line, so
    // the lockup is laid out downward from its top edge. Centring on the tile's
    // midpoint without this put the atomic number below the tile entirely.
    let symbolOrigin = NSPoint(
        x: tile.midX - symbolBox.width / 2,
        y: tile.midY + lockupHeight / 2 - symbolBox.height
    )
    let numberOrigin = NSPoint(
        x: tile.midX - numberBox.width / 2,
        y: symbolOrigin.y - gap - numberBox.height
    )

    // One glow pass behind the symbol, then a tighter one for the number, so the
    // pair reads as lit from a single source.
    context.saveGState()
    context.setShadow(offset: .zero, blur: u(46), color: CGColor(red: 0.35, green: 0.62, blue: 1.0, alpha: 0.9))
    symbol.draw(at: symbolOrigin)
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: .zero, blur: u(30), color: CGColor(red: 0.30, green: 0.55, blue: 1.0, alpha: 0.8))
    number.draw(at: numberOrigin)
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

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
