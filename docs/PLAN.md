# hiterm - Implementation Plan

## Roadmap

```
Phase 1-A  Project setup + single terminal
    ↓
Phase 1-B  Smooth scrolling
    ↓
Phase 1-C  Tabs
    ↓
Phase 1-D  Split panes
    ↓
Phase 1-E  Swipe tab switching
    ↓
Phase 2    Session management (SSH, Serial)
```

## Phase 1-A: Project Setup + Single Terminal

### Goal
Link libghostty and create a minimal app with a single terminal in one window.

### Tasks

1. **Build libghostty**
   - Run `zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false` from the Ghostty source
   - Copy artifacts (libghostty.a, ghostty.h) to libs/GhosttyKit/
   - Write module.modulemap

2. **Create Xcode project**
   - Write project.yml (xcodegen)
   - Create source directory structure
   - Configure framework linking

3. **App entry point**
   - HitermApp.swift: @main, NSApplication setup
   - AppDelegate.swift: Initialize GhosttyBridge, create main window

4. **Implement GhosttyBridge**
   - Call ghostty_init()
   - Create and finalize config
   - Create app (runtime_config + callbacks)
   - wakeup_cb: call ghostty_app_tick via DispatchQueue.main.async
   - action_cb: dispatch actions (handle at least RENDER)

5. **Implement TerminalSurface**
   - NSView subclass
   - Call ghostty_surface_new() in viewDidMoveToWindow
   - keyDown/keyUp → ghostty_surface_key()
   - mouseDown/mouseUp → ghostty_surface_mouse_button()
   - scrollWheel → ghostty_surface_mouse_scroll()
   - flagsChanged → modifier handling
   - setFrameSize → ghostty_surface_set_size()

6. **MainWindowController**
   - Create NSWindowController + NSWindow
   - Set TerminalSurface as contentView

### Done Criteria
- App launches and shows a terminal window
- Shell prompt is displayed
- Keyboard input works
- Basic commands (ls, vim, etc.) work correctly

---

## Phase 1-B: Smooth Scrolling

### Goal
Scroll at pixel granularity instead of line-by-line.

### Tasks

1. **Implement SmoothScrollLayer**
   - Intercept scroll events and accumulate pixel offset (pixelOffset)
   - When |pixelOffset| >= cellHeight, forward line scroll to libghostty
   - Apply remaining offset via CALayer.bounds.origin.y

2. **Over-rendering**
   - Pass viewport size + extra rows to ghostty_surface_set_size()
   - Or extend the layer above and below after rendering

3. **Frame synchronization**
   - Update layer offset in CVDisplayLink callback
   - Synchronize rendering with scroll offset

4. **Snap and momentum**
   - Detect scroll stop (momentum phase ended)
   - Spring animation snap to nearest line boundary
   - Natural momentum scrolling deceleration

### Done Criteria
- `cat large_file.txt` scrolls smoothly
- Trackpad scrolling feels natural
- Text aligns to line boundaries after scroll stops

---

## Phase 1-C: Tabs

### Goal
Create and switch between multiple tabs.

### Tasks

1. **Implement TabManager**
   - Tab struct: id, title, SplitTree (or single Surface)
   - Methods for create, delete, switch
   - Track active tab

2. **Implement TabBarView**
   - Custom NSView tab bar
   - Tab buttons, close button, + button
   - Drag-to-reorder

3. **Extend MainWindowController**
   - Integrate TabManager
   - Swap contentView on tab switch
   - Handle GHOSTTY_ACTION_NEW_TAB in action_cb

4. **Register shortcuts**
   - Cmd+T: New tab
   - Cmd+W: Close current tab
   - Cmd+Shift+[: Previous tab
   - Cmd+Shift+]: Next tab
   - Cmd+1~9: Jump to tab

### Done Criteria
- Cmd+T creates a new tab
- Tab switching works
- Each tab has an independent shell session
- Tab closing works

---

## Phase 1-D: Split Panes

### Goal
Split the view horizontally or vertically within a single tab.

### Tasks

1. **Implement SplitTree**
   - SplitNode enum (leaf | split)
   - split/close/focus methods
   - Manage split ratios

2. **Implement SplitView**
   - Recursively render SplitTree as NSViews
   - Draggable dividers for ratio adjustment
   - Focus indicator (highlight active surface)

3. **Extend action_cb**
   - Handle GHOSTTY_ACTION_NEW_SPLIT
   - Handle GHOSTTY_ACTION_GOTO_SPLIT
   - Handle GHOSTTY_ACTION_RESIZE_SPLIT
   - Handle GHOSTTY_ACTION_EQUALIZE_SPLITS

4. **Register shortcuts**
   - Cmd+D: Vertical split
   - Cmd+Shift+D: Horizontal split
   - Cmd+Option+Arrow: Move focus
   - Cmd+Shift+Enter: Toggle split zoom

### Done Criteria
- Vertical and horizontal splits work
- Each split pane has an independent shell
- Focus navigation works
- Split ratio adjustment works

---

## Phase 1-E: Swipe Tab Switching

### Goal
Switch tabs using two-finger horizontal swipe.

### Tasks

1. **Implement GestureHandler**
   - Register NSPanGestureRecognizer (2-finger)
   - Calculate swipe direction and progress
   - Disable gesture when terminal has mouse capture

2. **Transition animation**
   - Slide current/next tab view horizontally as swipe progresses
   - Commit switch when threshold exceeded (30%+)
   - Spring animation back to original position if below threshold

3. **Integrate with MainWindowController**
   - Connect GestureHandler → TabManager.switchTab()

### Done Criteria
- Two-finger swipe left → next tab
- Two-finger swipe right → previous tab
- Both tabs are visible during swipe
- Releasing mid-swipe snaps back to original tab

---

## Phase 2: Session Management

### Goal
Support multiple connection types: SSH, serial, etc.

### Tasks (Outline)

1. **Define SessionProtocol**
   - Common interface: connect(), disconnect(), write(), onRead()
   - LocalSession: existing PTY (libghostty default)
   - SSHSession: libssh2 or Process("ssh"...)
   - SerialSession: IOKit / ORSSerialPort

2. **SSH implementation**
   - Host/port/user/key profile UI
   - Password and key authentication
   - Auto-reconnect
   - Port forwarding

3. **Serial implementation**
   - Port scanning and selection UI
   - Configuration: baud rate, parity, stop bits, flow control
   - Connect / disconnect

4. **Session management UI**
   - New session dialog
   - Saved profiles list
   - Quick connect
