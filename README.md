# hiterm

A macOS-native terminal emulator built on [libghostty](https://github.com/ghostty-org/ghostty).

> **Note**: This is a personal project. I build software for my own use when existing tools don't quite fit my preferences. hiterm is no different — it's built to scratch my own itch, not to be a general-purpose terminal for everyone. Use at your own risk.

## Why

I wanted a terminal emulator that:

- **Scrolls smoothly** — pixel-level, not line-by-line. Like scrolling a web page, not a 1980s VT100.
- **Treats tabs as desktops** — entering fullscreen should send each tab to its own macOS Space, navigable with three-finger swipe.
- **Supports two-finger swipe** for tab switching, like Safari.
- **Splits panes** without friction.

No existing terminal did all of these the way I wanted, so I'm building one.

## Architecture

```
┌──────────────────────────────────────────────┐
│  hiterm (Swift / AppKit)                     │
│                                              │
│  UI Layer                                    │
│  ├─ Tabs, split panes, gestures, fullscreen  │
│  ├─ Smooth scroll (pixel offset on CALayer)  │
│  └─ Window management                        │
│                                              │
│  ──── import GhosttyKit (C ABI) ────         │
│                                              │
│  libghostty (Zig)                            │
│  ├─ VT100/xterm terminal emulation           │
│  ├─ Metal GPU-accelerated rendering          │
│  ├─ Font handling (FreeType + HarfBuzz)      │
│  ├─ PTY management                           │
│  └─ Kitty keyboard protocol                  │
└──────────────────────────────────────────────┘
```

hiterm is a thin UI shell on top of libghostty. The terminal engine — escape sequence parsing, rendering, font shaping, PTY — is all handled by libghostty. hiterm provides the macOS chrome: tabs, split panes, smooth scrolling, gestures, and window management.

### Smooth Scrolling

libghostty scrolls line-by-line internally. hiterm adds pixel-level smooth scrolling at the UI layer:

1. Trackpad scroll events accumulate a pixel offset
2. The Metal render layer is shifted by that offset via `CALayer.bounds.origin.y`
3. When the offset exceeds one cell height, a line scroll is forwarded to libghostty
4. On scroll stop, a spring animation snaps to the nearest line boundary

### Fullscreen Tabs → Desktops

When entering fullscreen, hiterm detaches each tab into a separate `NSWindow` with `collectionBehavior = .fullScreenPrimary`. macOS places each window in its own Space. Exiting fullscreen merges them back.

## Features

### MVP

- [x] libghostty-powered terminal emulation
- [ ] Pixel-level smooth scrolling
- [ ] Tabs with custom tab bar
- [ ] Horizontal / vertical split panes
- [ ] Two-finger swipe tab switching
- [ ] Fullscreen: each tab becomes its own macOS Space

### Planned

- [ ] Session management (SSH, serial)
- [ ] SSH connection profiles
- [ ] Serial port support (baud rate, parity, etc.)

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift |
| UI | AppKit + SwiftUI |
| Terminal engine | [libghostty](https://github.com/ghostty-org/ghostty) (Zig, C ABI, MIT) |
| Rendering | Metal (via libghostty) |
| Build | Zig (libghostty) + xcodegen + Xcode (app) |

## Building

### Prerequisites

```bash
brew install zig cmake ninja xcodegen
xcodebuild -downloadComponent MetalToolchain
```

### Build libghostty

```bash
git clone --depth 1 https://github.com/ghostty-org/ghostty.git ../ghostty-src
cd ../ghostty-src
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false
```

Copy artifacts:

```bash
cp zig-out/lib/libghostty.a ../hiterm/libs/GhosttyKit/
cp include/ghostty.h ../hiterm/libs/GhosttyKit/include/
cp include/module.modulemap ../hiterm/libs/GhosttyKit/include/
```

### Build hiterm

```bash
cd hiterm
xcodegen generate
xcodebuild -scheme hiterm build
```

Or open `hiterm.xcodeproj` in Xcode.

## Documentation

- [Requirements](docs/REQUIREMENTS.md) — what hiterm should do
- [Architecture](docs/ARCHITECTURE.md) — how it's structured
- [Build Guide](docs/BUILD.md) — detailed build instructions and troubleshooting
- [Implementation Plan](docs/PLAN.md) — phased development roadmap

## License

This project is for personal use. libghostty is [MIT licensed](https://github.com/ghostty-org/ghostty/blob/main/LICENSE).
