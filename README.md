# Osmium76

A native macOS batch image compressor for Apple silicon. SwiftUI + ImageIO, no
dependencies, nothing leaves the machine.

Named after osmium — element 76, the densest naturally occurring element.

## Build

```sh
./make-icon.sh      # optional: generates Resources/AppIcon.icns
./build.sh          # release build -> build/Osmium.app
./build.sh run      # build and launch
./build.sh debug    # debug build
```

Git repo on `main`, no remote. There is no test target or CI. Verification is
`swift build` plus the parse check below.

Then either `open build/Osmium.app`, or during development just:

```sh
swift run Osmium
```

Requires macOS 14+ and **the full Xcode app**, not just the Command Line Tools.
The macOS 26+ SDK implements `@State`/`@Binding`/`@Environment` as macros that
ship in Xcode's `SwiftUIMacros` compiler plugin; a CLT-only setup cannot expand
them. `build.sh` checks for this and prints instructions if it is missing.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

## Checking without a Mac

Most of the project can be verified on Linux, which is useful for CI or a
non-Mac dev box.

```sh
# 1. Syntax-check every file, including the SwiftUI layer
swiftc -parse -swift-version 5 $(find Sources -name '*.swift' | sort)

# 2. Fully typecheck the engine and model against hand-written Apple stubs
./Tools/LinuxTypecheck/typecheck-linux.sh          # uses `swiftc` from PATH
SWIFTC=/path/to/swiftc ./Tools/LinuxTypecheck/typecheck-linux.sh

# 3. Strict-concurrency pass over the same layer
swiftc -swift-version 6 -typecheck -I Tools/LinuxTypecheck/build \
    Sources/Osmium/Core/*.swift Sources/Osmium/Model/*.swift
```

`Tools/LinuxTypecheck/Modules/` holds minimal stand-ins for CoreGraphics,
CoreImage, ImageIO, UniformTypeIdentifiers and AppKit, so the compiler can
resolve the engine's imports. This catches syntax errors, type errors, bad
optional handling, wrong closures and concurrency mistakes.

It does **not** validate Apple's real SDK signatures, and there is no realistic
Linux stub for SwiftUI — `Sources/Osmium/App/` is parse-checked only. A real
`swift build` on a Mac remains the authority for the view layer.

## What it does

- Drag in images, folders, or whole directory trees. Files dropped from Photos
  or a browser are staged to temp files automatically.
- Re-compress JPEG / PNG / HEIC / WebP with a quality slider and a longest-edge cap.
- Strips EXIF, TIFF, IPTC, 8BIM and GPS payloads, or keeps everything but the
  location tags. Orientation is baked into the pixels, so images stay upright
  and nothing is double-rotated.
- Handles alpha correctly: PNG/HEIC/WebP keep transparency, JPEG is flattened on
  white.
- Wide-gamut sources (Display P3) stay in P3 instead of being crushed to sRGB.
- Skip-if-larger, so already-optimised files are never degraded.
- Writes in place when the format is unchanged, otherwise next to the original
  with a suffix, or into a folder you pick. Collision-safe.
- Before/after comparison pane with a draggable divider, zoom and a
  transparency checkerboard.
- Parallel jobs (1–12), cancellable, with live totals for bytes saved.

## Keyboard

| Shortcut | Action |
| --- | --- |
| `⌘O` | Add files |
| `⇧⌘O` | Add folder |
| `⌘↩` | Start compressing |
| `⌘.` | Stop |
| `⌫` | Remove selected from the list |

## Layout

```
Sources/Osmium/Core/     engine — ImageIO encode, metadata policy, batch runner
Sources/Osmium/Model/    observable app state and the queue
Sources/Osmium/App/      SwiftUI views
```

## Notes

- WebP is encoded by libwebp's `cwebp` (`brew install webp`), not ImageIO — the
  macOS SDK has a WebP *decoder* but no encoder. Settings → Formats shows which
  encoder backs each format on the current machine.
- PNG output is lossless: only resizing and metadata removal apply.
- `build.sh` signs ad-hoc, which is enough for local use. For distribution you
  need a Developer ID certificate and a notarised bundle.
- "Remove location data" drops the GPS dictionary and any geographic EXIF/TIFF
  tag. Individual EXIF/TIFF keys are matched by their literal string values
  because the SDK does not expose the `kCGImagePropertyExif…` constants to Swift.
  A plain `file` listing won't show those tags either way; check the payload
  dictionary rather than trusting the filename.
- Animated GIF/WebP, APNG and multi-page TIFF are **skipped**, not flattened:
  only frame 0 is ever decoded, so compressing them would silently discard the
  rest of the animation.
- HEIC alpha is written automatically by ImageIO from the source `CGImage`; the
  HEIC dictionary keys that control it are private API.
