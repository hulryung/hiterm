#!/bin/bash
set -euo pipefail

GHOSTTY_SRC="${GHOSTTY_SRC:-$HOME/dev/ghostty-src}"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/libs/GhosttyKit/lib"

if [ ! -d "$GHOSTTY_SRC" ]; then
    echo "Error: Ghostty source not found at $GHOSTTY_SRC"
    echo "Set GHOSTTY_SRC to point to your ghostty checkout."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Building libghostty from $GHOSTTY_SRC ..."
cd "$GHOSTTY_SRC"
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false -Dtarget=aarch64-macos

# Find the most recent arm64 fat library (sort by modification time, newest first)
FAT_LIB=$(find .zig-cache -name "libghostty-fat.a" -newer build.zig -print0 2>/dev/null \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -rn \
    | while read _ts path; do
        if lipo -info "$path" 2>/dev/null | grep -q arm64; then echo "$path"; break; fi
    done)

if [ -z "$FAT_LIB" ]; then
    echo "Error: Could not find arm64 libghostty-fat.a"
    exit 1
fi

cp "$FAT_LIB" "$OUTPUT_DIR/libghostty.a"
cp "$GHOSTTY_SRC/include/ghostty.h" "$(dirname "$OUTPUT_DIR")/include/ghostty.h"

echo "Done: $OUTPUT_DIR/libghostty.a ($(du -h "$OUTPUT_DIR/libghostty.a" | cut -f1))"
