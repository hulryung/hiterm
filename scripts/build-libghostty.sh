#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_DIR/ghostty"
LIB_DIR="$PROJECT_DIR/libs/GhosttyKit/lib"
INCLUDE_DIR="$PROJECT_DIR/libs/GhosttyKit/include"
SHARE_DIR="$PROJECT_DIR/libs/GhosttyKit/share"
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

# Copy resources (themes, terminfo) for app bundle.
# These are needed for theme resolution and terminal identification at runtime.
ZIG_SHARE="$GHOSTTY_DIR/zig-out/share"
if [ -d "$ZIG_SHARE/ghostty/themes" ]; then
    mkdir -p "$SHARE_DIR/ghostty"
    rm -rf "$SHARE_DIR/ghostty/themes"
    cp -R "$ZIG_SHARE/ghostty/themes" "$SHARE_DIR/ghostty/themes"
    THEME_COUNT=$(ls "$SHARE_DIR/ghostty/themes" | wc -l | tr -d ' ')
    echo "Copied $THEME_COUNT themes → libs/GhosttyKit/share/ghostty/themes/"
else
    echo "Warning: themes not found at $ZIG_SHARE/ghostty/themes"
fi

if [ -d "$ZIG_SHARE/terminfo" ]; then
    rm -rf "$SHARE_DIR/terminfo"
    cp -R "$ZIG_SHARE/terminfo" "$SHARE_DIR/terminfo"
    echo "Copied terminfo → libs/GhosttyKit/share/terminfo/"
else
    echo "Warning: terminfo not found at $ZIG_SHARE/terminfo"
fi

echo "Done: libghostty.a ($(du -h "$LIB_DIR/libghostty.a" | cut -f1)) → libs/GhosttyKit/"
