# AGENTS.md

Osmium — a macOS batch image compressor (formerly Caesium). SwiftUI + ImageIO, single executable target, no
dependencies. Apple silicon only.

## Build and verify

```sh
./build.sh                # release -> build/Osmium.app (ad-hoc signed)
./build.sh debug          # debug build
./build.sh run            # build, then launch
```

There is **no test target and no CI**. Verify with, in increasing cost:

```sh
# 1. Syntax-check everything, including the SwiftUI layer (fast, seconds)
swiftc -parse -swift-version 5 $(find Sources -name '*.swift' | sort)

# 2. Real compile — the only authority for the view layer
swift build

# 3. Non-Mac: typecheck engine+model against hand-written Apple stubs
sh Tools/LinuxTypecheck/typecheck-linux.sh
```

Notes on #3: the script is not executable (invoke with `sh`, not `./`), and it
currently **fails** — the `CoreImage` stub uses `CGRect(x:y:width:height:)`, which
the CoreGraphics stub does not provide. Fix the stub before relying on this path.
It also needs extending whenever you touch an Apple API surface, since a missing
stub member breaks the run. Stubs cover CoreGraphics, CoreImage, ImageIO,
UniformTypeIdentifiers, AppKit. SwiftUI cannot be stubbed, so
`Sources/Osmium/App/` is parse-checked only.

## Git

Repo on `main`, single commit so far, no remote. Commit from the repo root;
`build.sh` and the tools `cd` to their own directory, so path arguments are not
needed. Don't commit `build/`, `.build/`, or `Tools/LinuxTypecheck/build/` —
already in `.gitignore`.

## Toolchain

Needs the **full Xcode app**, not just Command Line Tools: macOS 26+ implements
`@State`/`@Environment` as macros requiring the `SwiftUIMacros` compiler plugin.
`build.sh` preflights this.

The plugin is **not** at `$DEV_DIR/usr/lib/swift/host/plugins` on modern Xcode —
it is under `Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins`.
`build.sh` probes all three locations; keep that list intact.

## Architecture

```
Sources/Osmium/Core/    engine: encode, metadata policy, batch runner
Sources/Osmium/Model/   @Observable queue/state (CompressionModel)
Sources/Osmium/App/     SwiftUI views
```

`CompressionModel` owns the queue; `BatchRunner.run(job:options:)` is the pure
per-file entry point and returns an `Outcome` rather than throwing, so it is the
easiest layer to exercise from a scratch `main.swift` (see below). Options are a
snapshot taken at `start()`, so mutating the UI mid-run cannot affect a batch.

## Traps that have already bitten

**`@Environment` in `Commands` traps at launch.** `AppCommands` reads the model
through `@Environment(CompressionModel.self)`; SwiftUI builds the menu-bar
command list during `applicationWillFinishLaunching`, before any scene installs
the environment, so it assertion-fails and dies with a bare `SIGTRAP`. Pass the
model in as a plain property instead.

**`onDrop` must declare only `UTType.fileURL`.** Adding `.image` to the list
makes SwiftUI hand over a provider narrowed to `public.jpeg` alone — the file
path is gone before your handler runs, and the image can only be staged to temp.
This cost three wrong diagnoses (path decoding, security-scoped bookmarks,
`loadObject` vs `loadDataRepresentation`) because the data was never offered.
Verify with `provider.registeredTypeIdentifiers` before theorising again.

Sources that offer image bytes with no file location (Photos, Safari) are
genuinely unresolvable. Those stage via `DropStaging`, and `start()` prompts for
a destination folder rather than picking one silently.

**ImageIO decodes WebP but cannot encode it.** No WebP entry appears in
`CGImageDestinationCopyTypeIdentifiers()`. `WebPEncoder` shells out to libwebp's
`cwebp` (`brew install webp`), handing it a lossless PNG intermediate. `cwebp`
rejects stdin, so temp files are required; the folder is UUID-per-encode to stay
parallel-safe. `OutputFormat.encodableFormats` must report WebP as available
whenever `WebPEncoder.isAvailable`, or it silently vanishes from the UI.

**`CFString` cannot be made from a Swift string literal.** Use the SDK constant
(`kCGImagePropertyTIFFOrientation`) or a real `CFString`; `= "Orientation"` fails
to compile. Related: `loadDataRepresentation` hands back `Data`, not a `URL`,
despite the parameter name in some call sites.

## Never delete a source file before the output exists

`BatchRunner` writes, *then* deletes the original. Cancellation is checked
before the write and never after it, so a cancelled job leaves the source
intact and returns `.pending`. If you add a cancellation check, do not put one
between the write and the delete — that window is what keeps the app from
leaving a user with neither file.

Related invariants worth preserving:

- `CompressionModel.start()` reserves every destination via
  `ImageCompressor.reserveDestinations` **before** any encoding. Resolving
  `avoidOverwrite` names inside `BatchRunner` races: two same-stem files in one
  output folder both see the name as free, both write it, and both originals
  can then be deleted.
- Only frame 0 is ever decoded, so `compress` throws `animatedSource` for
  multi-frame inputs rather than flattening them.
- `CompressionModel` claims paths synchronously in `addFiles` and releases them
  in `remove`/`clearFinished`/`clearAll`. A path whose scan fails must be
  released or it can never be queued again.
- `resetQueue` re-measures `originalSize`, because a prior run may have
  rewritten the file in place.
- In-place writes go through `replaceItemAt` plus an explicit copy of extended
  attributes: plain `.atomic` renames a fresh file over the top and drops
  permissions, ACLs and `com.apple.quarantine`.

## Scratch harness

There is no test suite, so engine changes get verified by copying
`Core/` + `Model/` into a throwaway SwiftPM package with a hand-written
`main.swift`, then exercising `BatchRunner`/`ImageCompressor` directly. This
compiles in seconds and is the only way to prove output paths, delete-original
behaviour, and resize maths without driving the UI. Delete the harness
afterwards — it must not land in `Sources/`.