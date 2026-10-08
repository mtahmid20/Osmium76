#!/usr/bin/env bash
#
# One-command install: check prerequisites, clone Osmium, build it, and open it.
#
#   ./fetch.sh              clone (or update) into ./Osmium, then build
#   ./fetch.sh run          build and launch
#   ./fetch.sh debug        debug build
#   ./fetch.sh --dir ~/apps install somewhere else
#   ./fetch.sh --check      report prerequisites and exit without building
#
# Building locally is the recommended install. A prebuilt binary would be ad-hoc
# signed and macOS quarantine would block it on every Mac but the build machine,
# so there is nothing to download.
#
set -euo pipefail

REPO="${OSMIUM_REPO:-https://github.com/mtahmid20/Osmium76.git}"
MIN_MACOS=14

CONFIG="release"
LAUNCH=0
CHECK_ONLY=0
DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    debug)   CONFIG="debug" ;;
    release) CONFIG="release" ;;
    run)     LAUNCH=1 ;;
    --check) CHECK_ONLY=1 ;;
    --dir)   shift; DIR="${1:-}" ;;
    --repo)  shift; REPO="${1:-$REPO}" ;;
    -h|--help)
      sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

bold=$'\033[1m'; red=$'\033[31m'; yellow=$'\033[33m'; green=$'\033[32m'; off=$'\033[0m'
say()  { printf '%s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$yellow" "$off" "$*"; }
fail() { printf '%serror:%s %s\n' "$red" "$off" "$*" >&2; }
ok()   { printf '  %s✓%s %s\n' "$green" "$off" "$*"; }

problems=0
note_problem() { problems=$((problems + 1)); }

# ---------------------------------------------------------------- prerequisites
say ""
say "${bold}Checking prerequisites${off}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Osmium only builds on macOS."
  exit 1
fi
ok "macOS $(sw_vers -productVersion)"

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( os_major < MIN_MACOS )); then
  fail "needs macOS ${MIN_MACOS} or later (found $(sw_vers -productVersion))"
  exit 1
fi

# Apple silicon only: build.sh passes --arch arm64 unconditionally.
arch="$(uname -m)"
if [[ "$arch" != "arm64" ]]; then
  warn "this Mac is ${arch}; Osmium builds for arm64 (Apple silicon) only."
  note_problem
else
  ok "Apple silicon (arm64)"
fi

if ! command -v git > /dev/null; then
  fail "git is not installed. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi
ok "git $(git --version | awk '{print $3}')"

# The full Xcode app, not just the Command Line Tools. macOS 26+ implements
# @State/@Binding/@Environment as macros that live in Xcode's SwiftUIMacros
# plugin; a CLT-only setup cannot expand them and the build fails with dozens
# of "external macro implementation ... could not be found" errors.
dev_dir="$(xcode-select -p 2>/dev/null || true)"
plugin_ok=0
if [[ -n "$dev_dir" ]]; then
  for candidate in \
    "$dev_dir/usr/lib/swift/host/plugins" \
    "$dev_dir/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins"; do
    if compgen -G "$candidate/libSwiftUIMacros*" > /dev/null 2>&1; then
      plugin_ok=1
      break
    fi
  done
fi

if (( plugin_ok )); then
  ok "Xcode developer dir (${dev_dir})"
else
  fail "the full Xcode app is required, not just the Command Line Tools."
  say ""
  say "  The macOS 26+ SDK implements @State/@Environment as macros that ship in"
  say "  Xcode's SwiftUIMacros plugin. A CLT-only install cannot expand them."
  say ""
  say "  1. Download Xcode from https://developer.apple.com/xcode/ (or the App Store)"
  say "  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  say "  3. sudo xcodebuild -runFirstLaunch"
  exit 1
fi

# WebP output is the one thing outside Apple's frameworks: ImageIO has a WebP
# decoder but no encoder, so libwebp's cwebp does that work.
cwebp_path=""
for p in /opt/homebrew/bin/cwebp /usr/local/bin/cwebp /opt/local/bin/cwebp; do
  if [[ -x "$p" ]]; then cwebp_path="$p"; break; fi
done
if [[ -z "$cwebp_path" ]] && command -v cwebp > /dev/null; then
  cwebp_path="$(command -v cwebp)"
fi

if [[ -n "$cwebp_path" ]]; then
  ok "libwebp ($("$cwebp_path" -version 2>/dev/null | head -1))"
else
  warn "libwebp not found, so WebP output will be unavailable."
  warn "install it with:  brew install webp"
  note_problem
fi

if (( CHECK_ONLY )); then
  say ""
  if (( problems == 0 )); then
    say "All prerequisites satisfied."
  else
    say "${problems} optional dependency missing — see the warnings above."
  fi
  say ""
  exit 0
fi

# ------------------------------------------------------------------------ fetch
# When run from inside the checkout itself, build in place rather than nesting a
# clone inside itself.
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "$DIR" && -d "$script_dir/.git" ]]; then
  target="$script_dir"
else
  target="${DIR:-$PWD/Osmium}"
fi

if [[ -z "$DIR" && -d "$script_dir/.git" ]]; then
  say ""
  say "${bold}Already inside a checkout${off} — building in place."
elif [[ -d "$target/.git" ]]; then
  say ""
  say "${bold}Updating existing checkout${off} ${target}"
  git -C "$target" pull --ff-only
else
  if [[ -e "$target" ]]; then
    fail "$target already exists and is not a git checkout."
    exit 1
  fi
  say ""
  say "${bold}Cloning${off} $REPO"
  git clone "$REPO" "$target"
fi

# ------------------------------------------------------------------------- build
say ""
say "${bold}Building${off} ($CONFIG)"
# An empty array plus `set -u` is an unbound-variable error on older bash, so
# only expand it when there is something to pass.
BUILD_ARGS=()
[[ "$CONFIG" == "debug" ]] && BUILD_ARGS+=(debug)
(( LAUNCH )) && BUILD_ARGS+=(run)

if (( ${#BUILD_ARGS[@]} > 0 )); then
  "$target/build.sh" "${BUILD_ARGS[@]}"
else
  "$target/build.sh"
fi

APP="$target/build/Osmium.app"

say ""
if (( problems == 0 )); then
  say "${green}${bold}Ready.${off}  $APP"
else
  say "${bold}Ready, with caveats.${off}  $APP"
fi
say ""
say "A locally built app is never quarantined, so there is nothing to allow"
say "through Gatekeeper. To remove it later:  rm -rf \"$target\""
say ""