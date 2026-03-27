# hiterm

A macOS-native terminal emulator built on [libghostty](https://github.com/ghostty-org/ghostty).

## The Story

I'm a terminal power user. I spend most of my day staring at a terminal. And I got tired of terminals that *work fine* but don't *feel right*.

You know that feeling when you scroll a terminal and it jumps line by line? Or when you copy a wrapped line and it pastes with random newlines? Or when you swipe between tabs and nothing happens because terminals don't believe in gestures?

I wanted a terminal that feels as polished as the apps around it. Smooth pixel-level scrolling. Fluid tab switching with trackpad gestures. Satisfying close animations. A settings UI that doesn't require editing a config file.

This is not a terminal for everyone. This is a terminal for someone who obsesses over how things *feel*. Built for personal satisfaction — the kind of project where you spend an afternoon getting the pane close animation direction just right, because a pane on the left should slide left, not right.

Call it terminal otaku. I'm okay with that.

## Features

- **Smooth pixel scrolling** — GPU shader-based, not line-by-line jumps (via [patched libghostty](https://github.com/hulryung/ghostty))
- **Fluid tab switching** — two-finger trackpad swipe with continuous panning, or Cmd+Arrow with interruptible animation
- **Split panes** — horizontal/vertical with per-pane focus and polished close animations
- **Smart copy** — wrapped lines copy as a single line (libghostty handles soft-wrap detection)
- **Korean/CJK IME** — full support for composing input with correct cursor positioning
- **Dynamic tab titles** — shows current directory or running process name
- **Settings UI** — font picker, 463 theme browser, opacity slider (Cmd+,)
- **Fullscreen** — with logo and tab bar visible

## Architecture

```
┌──────────────────────────────────────────────┐
│  hiterm (Swift / AppKit)                     │
│  ├─ Tabs, splits, gestures, animations       │
│  ├─ Smooth scroll overlay                    │
│  ├─ Settings UI (SwiftUI)                    │
│  └─ Window management                        │
│                                              │
│  ──── import GhosttyKit (C ABI) ────         │
│                                              │
│  libghostty (Zig)                            │
│  ├─ VT100/xterm terminal emulation           │
│  ├─ Metal GPU-accelerated rendering          │
│  ├─ Font handling (FreeType + HarfBuzz)      │
│  ├─ PTY management                           │
│  └─ Smooth scroll (shader-level pixel offset)│
└──────────────────────────────────────────────┘
```

hiterm is a UI shell on top of libghostty. The terminal engine handles parsing, rendering, fonts, and PTY. hiterm provides the macOS experience: tabs, panes, gestures, animations, and settings.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift |
| UI | AppKit + SwiftUI |
| Terminal engine | [libghostty](https://github.com/hulryung/ghostty) fork (Zig, C ABI, MIT) |
| Rendering | Metal (via libghostty) |
| Build | Zig (libghostty) + xcodegen + Xcode (app) |

## Building

### Prerequisites

```bash
brew install zig cmake ninja xcodegen
xcodebuild -downloadComponent MetalToolchain
```

### Build libghostty

> **Important**: hiterm requires a [forked version of libghostty](https://github.com/hulryung/ghostty) that adds smooth pixel-level scrolling support at the GPU shader level. The upstream Ghostty does not yet include this feature. Once the Ghostty team ships native smooth scrolling ([Discussion #3206](https://github.com/ghostty-org/ghostty/discussions/3206)), hiterm will switch back to upstream.

```bash
git clone https://github.com/hulryung/ghostty.git ../ghostty-src
cd ../ghostty-src
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false -Dtarget=aarch64-macos
```

Copy the built library:

```bash
./scripts/build-libghostty.sh
```

### Build hiterm

```bash
xcodegen generate
xcodebuild -scheme hiterm build
```

### Run tests

```bash
xcodebuild -scheme hiterm test
```

## Download

Pre-built signed and notarized DMGs are available on the [Releases](https://github.com/hulryung/hiterm/releases) page. Apple Silicon (arm64) only.

## Acknowledgments

hiterm wouldn't exist without [Ghostty](https://ghostty.org) and [libghostty](https://github.com/ghostty-org/ghostty) by [Mitchell Hashimoto](https://mitchellh.com) and the Ghostty contributors. They built an incredible terminal engine — fast, correct, and beautifully designed — and made it available for anyone to build on. The terminal emulation, Metal rendering, font shaping, and PTY handling that power hiterm are all libghostty. I just added the chrome on top.

Massive respect to the Ghostty team for proving that terminals can be both technically excellent and a joy to use.

This entire project was vibe-coded with [Claude Code](https://claude.ai/code) by Anthropic. Every single line — from the initial architecture to the final animation polish. Designing the smooth scroll approach, debugging IOSurfaceLayer quirks, rewriting the swipe tracker based on iTerm2 patterns, patching libghostty's shader pipeline, and everything in between. I don't write Swift. I don't write Zig. I couldn't have built any of this without Claude Code. It turned "I want a terminal that feels nice" into a working, signed, notarized macOS app.

## License

This project is for personal use. libghostty is [MIT licensed](https://github.com/ghostty-org/ghostty/blob/main/LICENSE).
