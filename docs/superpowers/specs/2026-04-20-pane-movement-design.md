# Pane Movement (Move/Swap) — Design

Date: 2026-04-20
Status: Approved, ready for implementation planning

## Goal

Let users rearrange the position of terminal panes within a window, by keyboard and by mouse drag. Inspired by tiling window managers (Omarchy/Hyprland). The semantics is a simple **swap** between the source pane and a target pane; the split tree structure (containers, directions, ratios) is preserved.

## Context

- Ghostty's C ABI provides `NEW_SPLIT`, `GOTO_SPLIT` (focus), and `RESIZE_SPLIT`. It does **not** expose any move/swap action — this feature is implemented entirely at the Swift/AppKit layer with no libghostty changes.
- hiterm's `SplitView.swift` already models splits as a recursive `SplitNode` tree (`leaf(TerminalSurfaceView)` / `split(SplitContainer)`), and has tree-manipulation helpers (`replaceLeaf`, `findSibling`, `replaceParentSplit`, `navigateToSplit`). This feature extends that layer.

## UX

### Keyboard

- Shortcut: `Cmd+Shift+←/→/↑/↓` → move focused pane in direction (swap with nearest directional neighbor).
- Menu: `Window → Move Split {Up, Down, Left, Right}` (added to the existing Splits section in Window menu).
- Focus follows the moved pane (the originally focused pane remains focused after swap).
- No-op when no neighbor exists in that direction, or only one pane in the window.

### Mouse

- Trigger: hold `Cmd+Shift` and press inside a pane — pane-move drag begins after a small movement threshold (avoid false triggers on plain modified clicks).
- During drag:
  - Cursor switches to `closedHand`.
  - Source pane shows a translucent blue tint overlay ("picked up").
  - Pane currently under the pointer shows a darker blue overlay ("drop target").
- Release (`mouseUp`):
  - Over a different valid pane → swap (same animation path as keyboard).
  - Over source pane, outside any pane, or on a divider → cancel (no swap, overlays removed).
- Cancel conditions: `Cmd+Shift` released mid-drag, `Esc`, window loses focus.

### Swap semantics

Exchange the two leaves' positions within the existing tree. Container structure, directions, and ratios are preserved. Example (horizontal split with ratio 0.3):

```
Before: container(0.3, leaf A, leaf B)   →   A=left 30%, B=right 70%
After:  container(0.3, leaf B, leaf A)   →   B=left 30%, A=right 70%
```

Both translation and resize can occur (asymmetric ratios). The animation handles both via frame interpolation.

## Architecture

All state and operations live in the existing Swift layer. Two entry points (keyboard / mouse) converge on one tree-manipulation function.

```
Keyboard event  ─┐
                  ├─►  findNeighbor(of:direction:)  ─►  SplitView.swapSurfaces(_:_:)  ─►  layoutSplits()
Mouse drag drop ─┘                                              │
                                                                └─► animate frames (NSAnimationContext)
```

### Component changes

**`Views/SplitView.swift`** — extended:
- `swapSurfaces(_ a: TerminalSurfaceView, _ b: TerminalSurfaceView)` — tree swap + animated relayout. Guards: `a === b` → no-op.
- `findNeighbor(of focused: TerminalSurfaceView, direction: ghostty_action_goto_split_e) -> TerminalSurfaceView?` — factored out of the existing `navigateToSplit` body so both keyboard-move and drag-hit-test can reuse the logic.
- `hitTestSurface(at point: NSPoint) -> TerminalSurfaceView?` — returns the leaf surface at a given point in split-view coordinates, ignoring dividers and overlays.

**`Views/PaneDragOverlay.swift`** (new) — single responsibility: render the source tint + target tint during drag. A plain `NSView` with two sublayers (source rect, target rect); container/SplitView sets frames as drag state evolves. No input handling.

**`Views/TerminalSurfaceView.swift`** — `mouseDown(with:)` inspects `event.modifierFlags`. If `[.command, .shift]` is set, instead of starting selection, enter a **custom drag loop** (see below) owned by the enclosing `TerminalSplitView`.

**`Views/MainWindowController.swift`** — new `@objc func moveSplit(_ sender: NSMenuItem)` action. Reads the menu item `tag` (same tag scheme as `gotoSplit`: 2=Up, 3=Left, 4=Down, 5=Right), calls `SplitView.findNeighbor` + `swapSurfaces`.

**`App/AppDelegate.swift`** — Window menu: append four "Move Split Up/Down/Left/Right" items after the existing `gotoSplit` items, with `Cmd+Shift+Arrow` key equivalents.

### Custom drag loop

Preferred over `NSDraggingSession` because:
- No pasteboard item / out-of-window drop needed.
- Lower overhead, fewer moving parts.
- Matches iTerm2 pattern (already used by hiterm's `SwipeTracker` for a similar reason).

Loop sketch (on `TerminalSplitView`):
```swift
func runPaneDragLoop(source: TerminalSurfaceView, initial: NSEvent) {
    let overlay = PaneDragOverlay(...); addSubview(overlay)
    var target: TerminalSurfaceView? = nil
    trackingLoop: while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]) {
        switch ev.type {
        case .leftMouseDragged:
            guard ev.modifierFlags.contains([.command, .shift]) else { break trackingLoop } // cancel
            target = hitTestSurface(at: convert(ev.locationInWindow, from: nil))
            overlay.update(source: source.frame, target: target?.frame)
        case .leftMouseUp:
            break trackingLoop
        case .flagsChanged where !ev.modifierFlags.contains([.command, .shift]):
            target = nil; break trackingLoop
        case .keyDown where ev.keyCode == 53 /* esc */:
            target = nil; break trackingLoop
        default: break
        }
    }
    overlay.removeFromSuperview()
    if let target, target !== source { swapSurfaces(source, target) }
}
```

## Animation

Both keyboard and drag paths converge here.

1. Capture current frames: `fromA = a.frame`, `fromB = b.frame`.
2. Swap leaves in the tree; call `layoutSplits()` to compute new target frames (`toA`, `toB`).
3. Immediately reset `a.frame = fromA`, `b.frame = fromB`.
4. Animate to `toA`, `toB` via `NSAnimationContext`:
   - Duration 220 ms
   - Timing function `.easeInEaseOut` (`CAMediaTimingFunction(name: .easeInEaseOut)`)
   - Set `allowsImplicitAnimation = true` inside the animation block
5. On completion: restore first-responder to the originally focused surface; clear the `isAnimatingSwap` flag that blocks new move operations during animation.

### Metal-layer risk

`TerminalSurfaceView` is `CAMetalLayer`-backed. Animating `frame` directly can cause stretching/artifacts mid-animation because the Metal drawable size may not interpolate cleanly.

- **First pass:** animate frame directly. Ship if visual quality is acceptable.
- **Fallback (if artifacts appear):** capture `NSBitmapImageRep` snapshots of both panes before the swap, place them in temporary `NSImageView` proxies, animate the proxies, remove them on completion and reveal the live surfaces at their new frames. More code, zero rendering artifacts.

Choose first pass unless manual testing shows issues.

## Edge cases

| Situation | Behavior |
|---|---|
| Only one pane in window | Menu items disabled; keyboard shortcut no-op; `mouseDown` with Cmd+Shift does not enter drag loop |
| Source == target | No-op |
| Drop on divider / outside pane / on overlay | Cancel |
| Zoom active (`preZoomRootNode != nil`) | Menu disabled, drag refused — swap would be meaningless when other panes are hidden |
| Cmd+Shift released mid-drag | Cancel |
| Esc pressed mid-drag | Cancel |
| Swap animation in progress | New move requests ignored (`isAnimatingSwap` flag) until completion |
| Drag loop exits for any reason with target still set but tree changed externally | Pre-swap validation: both surfaces still present in tree, else cancel |

## Testing

No XCTest target exists in the project today. We will add `hitermTests` as part of this feature.

### Unit tests (pure logic)

Refactor tree operations into pure functions on `SplitNode` for testability:
- `swapLeaves(in node: SplitNode, a: TerminalSurfaceView, b: TerminalSurfaceView) -> SplitNode`
- `findNeighborByFrame(leaves: [(TerminalSurfaceView, NSRect)], from: TerminalSurfaceView, direction: …) -> TerminalSurfaceView?`

Test cases:
- 2-pane horizontal, 2-pane vertical — swap in all four directions
- 4-pane grid — swap preserves other panes
- Asymmetric ratio (0.3) — swap preserves ratio, panes exchange visible sizes
- Nested split (L-shape) — neighbor detection correct across nesting
- Single pane — neighbor lookup returns nil
- `a === b` — swap is no-op

### Manual test checklist

- [ ] 2/3/4/L layouts — all four keyboard directions
- [ ] Cmd+Shift drag: pickup overlay appears, target overlay tracks cursor
- [ ] Drop on different pane → swap + animation; focus on moved pane
- [ ] Drop on self/outside → cancel
- [ ] Release Cmd+Shift mid-drag → cancel
- [ ] Press Esc mid-drag → cancel
- [ ] Zoom active → menu items disabled, Cmd+Shift drag does not start
- [ ] Rapid keyboard moves — no overlap between animations, final state correct
- [ ] Metal-layer artifacts during animation (evaluate first-pass; escalate to snapshot fallback if needed)

## Out of scope

- Tree restructuring moves (e.g., "push into neighbor's subtree") — only simple swap.
- Drag-to-resplit (dropping on an edge to convert a pane into a new split) — possible future extension but not in v1.
- Moving panes across tabs or windows — not in v1.
