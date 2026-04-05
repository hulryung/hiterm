# Terminal Search Feature Design

## Overview

Add find-in-terminal (Cmd+F) search to hiterm. libghostty provides the search engine, matching, and highlighting. hiterm provides the UI overlay and state management.

## Architecture

Follows hiterm's existing pattern:

```
libghostty (C action) → GhosttyApp.handleAction() → NotificationCenter → UI
```

## Components

### 1. SearchState (Model)

Observable model holding search state per surface.

```swift
class SearchState: ObservableObject {
    @Published var needle: String = ""
    @Published var selected: UInt?
    @Published var total: UInt?
}
```

Owned by `TerminalSurfaceView`. Created on search start, nilled on search end.

### 2. GhosttyApp Action Handlers

Four new actions in `handleAction()`:

| C Action | Notification | UserInfo |
|----------|-------------|----------|
| `GHOSTTY_ACTION_START_SEARCH` | `.hitermStartSearch` | `"needle": String, "userdata": ptr` |
| `GHOSTTY_ACTION_END_SEARCH` | `.hitermEndSearch` | `"userdata": ptr` |
| `GHOSTTY_ACTION_SEARCH_TOTAL` | `.hitermSearchTotal` | `"total": ssize_t, "userdata": ptr` |
| `GHOSTTY_ACTION_SEARCH_SELECTED` | `.hitermSearchSelected` | `"selected": ssize_t, "userdata": ptr` |

All use existing `"userdata"` key pattern for surface identification.

### 3. SearchOverlayView (AppKit NSView)

Floating overlay anchored to top-right of the terminal surface.

```
┌──────────────────────────────────────┐
│  [search field____]  2/15   < >  x  │
└──────────────────────────────────────┘
```

Components:
- **NSTextField**: search input, auto-focused on appear
- **Match counter label**: "selected/total" or "-/total" or empty
- **Previous button** (chevron up): navigate to previous match
- **Next button** (chevron down): navigate to next match
- **Close button** (x): end search

### Debounce Strategy

Following Ghostty's pattern:
- Needle length >= 3 chars: search immediately
- Needle length < 3 chars: 300ms debounce
- Empty needle: search immediately (clears results)

Uses Combine `$needle` publisher with `switchToLatest()`.

### Key Bindings

| Key | Action |
|-----|--------|
| `Cmd+F` | Start search (triggers `GHOSTTY_ACTION_START_SEARCH`) |
| `Enter` | Next match (`ghostty_surface_binding_action("navigate_search:next")`) |
| `Shift+Enter` | Previous match (`ghostty_surface_binding_action("navigate_search:previous")`) |
| `Esc` | End search (`ghostty_surface_binding_action("end_search")`) |

## Data Flow

### Start Search
1. User presses Cmd+F
2. libghostty fires `GHOSTTY_ACTION_START_SEARCH` with optional needle
3. `GhosttyApp` posts `.hitermStartSearch` notification
4. `TerminalSurfaceView` creates `SearchState`, adds `SearchOverlayView` as subview
5. Text field gets focus

### Search Input
1. User types in text field
2. `SearchState.needle` updates (with debounce)
3. Combine subscriber calls `ghostty_surface_binding_action("search:\(needle)")`
4. libghostty performs matching and highlighting
5. libghostty fires `SEARCH_TOTAL` and `SEARCH_SELECTED` callbacks
6. `GhosttyApp` posts notifications
7. `TerminalSurfaceView` updates `SearchState.total` and `SearchState.selected`
8. `SearchOverlayView` counter label updates reactively

### Navigation
1. User presses Enter or clicks next/previous button
2. Call `ghostty_surface_binding_action("navigate_search:next")` or `"navigate_search:previous"`
3. libghostty updates selection and scrolls to match
4. `SEARCH_SELECTED` callback updates UI

### End Search
1. User presses Esc or clicks close button
2. Call `ghostty_surface_binding_action("end_search")`
3. libghostty fires `GHOSTTY_ACTION_END_SEARCH`
4. `GhosttyApp` posts `.hitermEndSearch` notification
5. `TerminalSurfaceView` sets `searchState = nil`, removes `SearchOverlayView`

## File Changes

| File | Change |
|------|--------|
| `hiterm/Core/GhosttyApp.swift` | Add 4 search action handlers |
| `hiterm/Views/TerminalSurfaceView.swift` | Add SearchState property, notification observers, overlay management |
| `hiterm/Views/SearchOverlayView.swift` | **New file** - search UI overlay |

## Out of Scope

- Draggable overlay positioning
- Regex search (libghostty does not support it)
- Search selected text (can be added later)
- Search history
