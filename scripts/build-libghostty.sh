#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_DIR/ghostty"
LIB_DIR="$PROJECT_DIR/libs/GhosttyKit/lib"
INCLUDE_DIR="$PROJECT_DIR/libs/GhosttyKit/include"
XCFW="$GHOSTTY_DIR/macos/GhosttyKit.xcframework/macos-arm64_x86_64"

if [ ! -d "$GHOSTTY_DIR" ]; then
    echo "Error: ghostty submodule not found at $GHOSTTY_DIR"
    echo "Run: git submodule update --init"
    exit 1
fi

echo "Building libghostty from submodule ($(cd "$GHOSTTY_DIR" && git rev-parse --short HEAD))..."
cd "$GHOSTTY_DIR"
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false -Demit-xcframework=true

mkdir -p "$LIB_DIR" "$INCLUDE_DIR"
cp "$XCFW/libghostty.a" "$LIB_DIR/"
cp "$XCFW/Headers/ghostty.h" "$INCLUDE_DIR/"

echo "Done: libghostty.a ($(du -h "$LIB_DIR/libghostty.a" | cut -f1)) → libs/GhosttyKit/"
