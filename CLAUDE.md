# hiterm

A macOS-native terminal emulator built on libghostty.

## Project Structure

```
hiterm/
├── hiterm/
│   ├── App/           # App entry point, AppDelegate
│   ├── Core/          # GhosttyBridge, TerminalSurface, Config
│   ├── Views/         # TabBarView, SplitView, SmoothScrollLayer, MainWindowController
│   └── Input/         # KeyboardHandler, MouseHandler, GestureHandler
├── libs/
│   └── GhosttyKit/    # libghostty static library + headers
│       ├── include/
│       │   ├── ghostty.h
│       │   └── module.modulemap
│       └── libghostty.a
├── docs/              # Requirements, architecture, build guide, implementation plan
├── project.yml        # xcodegen project spec
└── CLAUDE.md
```

## Tech Stack

- **Language**: Swift
- **UI**: AppKit + SwiftUI
- **Terminal engine**: libghostty (C ABI, MIT licensed)
- **Rendering**: Metal (built into libghostty)
- **Build**: xcodegen → Xcode

## Building

### Prerequisites

```bash
brew install zig cmake ninja xcodegen
xcodebuild -downloadComponent MetalToolchain
```

### Build libghostty

```bash
cd ../ghostty-src
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false
```

Copy artifacts to `libs/GhosttyKit/`.

### Build hiterm

```bash
xcodegen generate
xcodebuild -scheme hiterm build
```

## Key Architecture Decisions

- libghostty handles terminal emulation, Metal rendering, PTY, and font management
- Swift/AppKit handles UI shell: tabs, splits, gestures, window management
- Swift imports libghostty via `import GhosttyKit` (module.modulemap)
- Smooth scrolling is implemented at the UI layer (pixel offset on CALayer) since libghostty only supports line-level scrolling
- Fullscreen mode detaches tabs into separate NSWindows so macOS maps each to its own Space

## Required Frameworks

AppKit, Metal, CoreFoundation, CoreGraphics, CoreText, CoreVideo, QuartzCore, IOSurface, Carbon

## Coding Conventions

- Swift source files use standard Swift naming conventions
- One type per file where practical
- libghostty C types are wrapped in Swift classes/structs in Core/
- Callbacks from libghostty use `Unmanaged<T>` for userdata pointer bridging

## Ghostty Source Reference

The Ghostty source at `../ghostty-src` is used as a reference. Key files:
- `include/ghostty.h` — C API definition
- `macos/Sources/Ghostty/Ghostty.App.swift` — App initialization pattern
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — Surface/input handling pattern
- `macos/Sources/Ghostty/Ghostty.Input.swift` — Modifier translation
