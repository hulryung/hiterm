# hiterm - Architecture Document

## High-Level Structure

```
┌─────────────────────────────────────────────────────┐
│  hiterm (macOS App)                                 │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  UI Layer (Swift / AppKit / SwiftUI)          │  │
│  │                                               │  │
│  │  ┌─────────────┐ ┌──────────┐ ┌───────────┐  │  │
│  │  │ TabManager  │ │SplitTree │ │ Gestures  │  │  │
│  │  │             │ │          │ │ (Swipe)   │  │  │
│  │  └──────┬──────┘ └────┬─────┘ └─────┬─────┘  │  │
│  │         │             │              │        │  │
│  │  ┌──────▼─────────────▼──────────────▼─────┐  │  │
│  │  │        MainWindowController             │  │  │
│  │  │  (tabs, splits, fullscreen, gestures)   │  │  │
│  │  └──────────────────┬──────────────────────┘  │  │
│  └─────────────────────┼─────────────────────────┘  │
│                        │                             │
│  ┌─────────────────────▼─────────────────────────┐  │
│  │  Bridge Layer                                 │  │
│  │                                               │  │
│  │  ┌──────────────┐  ┌────────────────────────┐ │  │
│  │  │GhosttyBridge │  │  SmoothScrollLayer     │ │  │
│  │  │(App/Config)  │  │  (pixel scroll offset) │ │  │
│  │  └──────┬───────┘  └────────────┬───────────┘ │  │
│  │         │                       │             │  │
│  │  ┌──────▼───────────────────────▼───────────┐ │  │
│  │  │        TerminalSurface (NSView)          │ │  │
│  │  │  (input handling, rendering host)        │ │  │
│  │  └──────────────────┬───────────────────────┘ │  │
│  └─────────────────────┼─────────────────────────┘  │
│                        │ import GhosttyKit           │
│  ┌─────────────────────▼─────────────────────────┐  │
│  │  libghostty (C ABI, Static Library)           │  │
│  │                                               │  │
│  │  - VT100/xterm escape sequence parsing        │  │
│  │  - Metal GPU rendering                        │  │
│  │  - Font handling (FreeType + HarfBuzz)        │  │
│  │  - PTY management                             │  │
│  │  - Input encoding (Kitty keyboard protocol)   │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Swift-to-libghostty Bridge

libghostty exposes a C ABI. Swift accesses it via a module.modulemap using `import GhosttyKit`.

```
include/
├── ghostty.h          # libghostty C API header
└── module.modulemap   # Swift module map
```

```
module GhosttyKit {
    umbrella header "ghostty.h"
    export *
}
```

## Core Types

### Opaque Types (libghostty)

| Type | Description |
|------|-------------|
| `ghostty_app_t` | App instance. Holds config and runtime callbacks |
| `ghostty_config_t` | Configuration object |
| `ghostty_surface_t` | Terminal surface (PTY + renderer) |

### Swift Types (hiterm)

| Type | Description |
|------|-------------|
| `GhosttyBridge` | Wrapper for ghostty_app_t. Manages app lifecycle and callbacks |
| `TerminalSurface` | Wrapper for ghostty_surface_t. NSView subclass, handles input |
| `TabManager` | Manages tab collection: create, delete, switch |
| `SplitTree` | Recursive split tree (leaf or split) |
| `MainWindowController` | Manages window, tab bar, and fullscreen |

## Initialization Flow

```
1. HitermApp.swift (@main)
   └─ Create AppDelegate

2. AppDelegate.init()
   └─ Create GhosttyBridge
      ├─ ghostty_init(argc, argv)
      ├─ ghostty_config_new()
      ├─ ghostty_config_load_default_files()
      ├─ ghostty_config_finalize()
      └─ ghostty_app_new(runtime_config, config)
           Register callbacks in runtime_config:
           ├─ wakeup_cb      → Wake up main thread
           ├─ action_cb      → Handle actions (tab/split/title etc.)
           ├─ read_clipboard  → Read from clipboard
           ├─ write_clipboard → Write to clipboard
           └─ close_surface   → Close surface

3. MainWindowController
   └─ Create initial tab
      └─ Create TerminalSurface
         ├─ ghostty_surface_config_new()
         ├─ platform_tag = GHOSTTY_PLATFORM_MACOS
         ├─ platform.macos.nsview = self (NSView)
         └─ ghostty_surface_new(app, &config)
```

## Event Flow

### Keyboard Input

```
NSEvent.keyDown
  → TerminalSurface.keyDown(with:)
    → Convert modifiers (NSEvent.ModifierFlags → ghostty_input_mods_e)
    → Build ghostty_input_key_s
    → ghostty_surface_key(surface, key_event)
```

### Mouse / Scroll

```
NSEvent.scrollWheel
  → TerminalSurface.scrollWheel(with:)
    → SmoothScrollLayer accumulates pixel offset
    → On line boundary reached: ghostty_surface_mouse_scroll()
    → Sub-pixel offset applied via CALayer.bounds.origin.y
```

### Action Callbacks (libghostty → hiterm)

```
libghostty calls action_cb
  → GhosttyBridge.handleAction(target, action)
    → switch action.tag:
       GHOSTTY_ACTION_NEW_TAB    → TabManager.newTab()
       GHOSTTY_ACTION_NEW_SPLIT  → SplitTree.split()
       GHOSTTY_ACTION_SET_TITLE  → Update tab title
       GHOSTTY_ACTION_RENDER     → TerminalSurface.needsDisplay = true
       ...
```

## Tab Structure

```
MainWindowController
  └─ TabManager
      ├─ Tab 0: SplitTree
      │         └─ .leaf(TerminalSurface)
      ├─ Tab 1: SplitTree
      │         └─ .split(.vertical, 0.5,
      │              .leaf(TerminalSurface),
      │              .leaf(TerminalSurface))
      └─ Tab 2: SplitTree
                └─ .leaf(TerminalSurface)
```

## Split Tree

```swift
enum SplitNode {
    case leaf(TerminalSurface)
    case split(
        direction: SplitDirection,  // .horizontal | .vertical
        ratio: CGFloat,             // 0.0 ~ 1.0
        first: SplitNode,
        second: SplitNode
    )
}
```

## Smooth Scrolling Implementation

```
┌─ ClipView (viewport size) ────────────────┐
│                                           │
│  ┌─ Metal Layer (over-rendered) ────────┐  │
│  │  row -1  (top padding)               │  │
│  │  row 0  ← visible ────────────────  │  │
│  │  row 1                               │  │
│  │  ...                                 │  │
│  │  row N  ← visible ────────────────  │  │
│  │  row N+1 (bottom padding)            │  │
│  └──────────────────────────────────────┘  │
│         ↕ pixelOffset (sub-pixel shift)    │
└────────────────────────────────────────────┘

- Trackpad scroll event → accumulate pixelOffset
- CVDisplayLink callback applies pixelOffset to layer offset
- When |pixelOffset| >= cellHeight → forward line scroll to libghostty
- On scroll stop → spring animation snap to nearest line boundary
```

## Fullscreen Tabs-to-Desktops

```
Normal mode:
  NSWindow (tab bar + tabs)
    ├─ Tab 0 content
    ├─ Tab 1 content
    └─ Tab 2 content

Fullscreen transition:
  NSWindow A (Space 1) ← Tab 0 content
  NSWindow B (Space 2) ← Tab 1 content
  NSWindow C (Space 3) ← Tab 2 content

  Each window gets .fullScreenPrimary / .fullScreenAuxiliary
  macOS automatically places each in a separate Space

Fullscreen exit:
  Merge all windows back into a single tabbed window
```

## Build

### Build libghostty

```bash
cd ghostty-src
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false
```

Artifacts:
- `zig-out/lib/libghostty.a` (or xcframework)
- `include/ghostty.h`

### Build hiterm

```bash
cd hiterm
xcodegen generate
xcodebuild -scheme hiterm -configuration Release build
```

## Required Frameworks

- AppKit
- Metal
- CoreFoundation
- CoreGraphics
- CoreText
- CoreVideo
- QuartzCore
- IOSurface
- Carbon
