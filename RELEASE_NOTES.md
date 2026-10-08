# Osmium v1.0.0

First tagged release. A native macOS batch image compressor — SwiftUI and
ImageIO, no dependencies, nothing leaves the machine.

**Apple silicon only** (arm64). Requires macOS 14 or later.

## What it does

- Drag in images, folders, or whole directory trees.
- Re-encode to JPEG, PNG, HEIC, or WebP with a quality slider, a pixel cap, or
  a percentage of each image's own longest edge.
- Before/after comparison with a draggable divider, zoom, and a transparency
  checkerboard.
- Strip EXIF, TIFF, IPTC, 8BIM and GPS payloads, or keep everything but the
  location tags.
- Parallel jobs (1–12), cancellable, with live totals.
- Runs entirely on your Mac. No network calls.

## Requirements

The **full Xcode app** is needed to build, not just the Command Line Tools.
macOS 26+ implements `@State`/`@Environment` as macros that require Xcode's
`SwiftUIMacros` compiler plugin; a CLT-only setup cannot expand them.

WebP output requires libwebp (`brew install webp`). ImageIO has a WebP decoder
but no encoder, so `cwebp` does that work. Settings → Formats shows which
encoder backs each format on your machine.

## Install

```sh
git clone https://github.com/mtahmid20/Osmium76.git
cd Osmium76
./fetch.sh
```

`fetch.sh` verifies the prerequisites, builds `Osmium.app`, and tells you where
it is. Then:

```sh
open build/Osmium.app
```

A locally built app is never quarantined, so there is nothing to allow through
Gatekeeper — which is the whole reason there is no binary attached here.

## Building

```sh
./build.sh            # release -> build/Osmium.app
./build.sh run        # build, then launch
./fetch.sh --check    # report prerequisites only
./make-icon.sh        # regenerate the app icon
```

## No binary attached — deliberately

This release ships **source only**. There is no `.app` in the assets.

`build.sh` signs ad-hoc, and macOS quarantine rejects any app that is not
Developer ID signed and notarised. A binary attached here would download and
then fail to open on every other Mac, showing Gatekeeper's "damaged and can't be
opened" message. That is a bad first impression and reads like malware, so it
is better to ship nothing than something that cannot run.

To produce a distributable build you need an Apple Developer ID certificate and
App Store Connect notarisation credentials. Once those exist, change the
`codesign` invocation in `build.sh` from `--sign -` to your identity, run
`xcrun notarytool submit` with `--wait`, and staple the ticket.

## Notable behaviour

- Animated GIF/WebP, APNG and multi-page TIFF are **skipped**, not flattened —
  only the first frame is ever decoded, so compressing them would silently drop
  the rest of the animation.
- Dropping images from Photos or Safari offers no file location, so those are
  staged to a temporary file and you are asked where to save the result. Dragging
  from Finder keeps its real path.
- "Delete originals" is off by default. The summary bar reports **reduction**,
  not bytes freed, because the originals are still on disk unless you ask for
  them to be removed.