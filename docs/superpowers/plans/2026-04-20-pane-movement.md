# Pane Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users rearrange terminal panes within a window via `Cmd+Shift+Arrow` (keyboard swap) and `Cmd+Shift+drag` (mouse drag-to-swap), with an animated transition.

**Architecture:** All changes are in the Swift/AppKit layer — libghostty is untouched. The existing `SplitNode` recursive tree in `hiterm/Views/SplitView.swift` gains a tree-swap operation and an animated relayout path. Both input modes (keyboard and drag) funnel into the same `swapSurfaces(_:_:)` function for consistency.

**Tech Stack:** Swift 5.10, AppKit (`NSView`, `NSEvent.nextEventMatching`, `NSAnimationContext`, `NSCursor`), XCTest for unit tests. Existing `hitermTests` target already configured in `project.yml`.

**Before you start:**
- `hiterm/Views/TerminalSurfaceView.swift` has uncommitted debug scroll logs that are unrelated to this work. Either commit them on a separate branch, stash them (`git stash`), or create a worktree for this feature before starting. Tasks below assume your working tree is clean apart from your own task edits.
- You will run `xcodegen generate` after any `project.yml` edit. You will run `xcodebuild -scheme hiterm build` and the `hitermTests` bundle to verify each step.

---

## File Plan

**New files:**
- `hiterm/Views/PaneDragOverlay.swift` — translucent overlay view rendered during drag (source + target highlights). Owns no logic; frames set from outside.

**Modified files:**
- `hiterm/Views/SplitView.swift` — adds `swapSurfaces`, `findNeighbor`, `hitTestSurface`, `runPaneDragLoop`, animated relayout, `isAnimatingSwap` gate.
- `hiterm/Views/TerminalSurfaceView.swift` — `mouseDown` modifier check to enter pane-drag mode.
- `hiterm/Views/MainWindowController.swift` — `moveSplit(_:)` action + menu validation for move + drag entry point.
- `hiterm/App/AppDelegate.swift` — Window menu "Move Split Up/Down/Left/Right" entries with `Cmd+Shift+Arrow` key equivalents.
- `hitermTests/SplitNodeTests.swift` — unit tests for the pure neighbor-finding function.

**Helpers to extract for testability:**
- `findNeighborByFrame(leaves:from:direction:) -> Int?` — pure function taking `[(id: ObjectIdentifier, frame: NSRect)]` and a direction, returning the index of the nearest neighbor. Tested without any UI. The view-level `findNeighbor(of:direction:)` is a thin wrapper.

---

## Task 1: Extract pure `findNeighborByFrame` + TDD tests

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — add file-private pure function near top.
- Modify: `hitermTests/SplitNodeTests.swift` — add tests.

- [ ] **Step 1.1: Write failing tests**

Append to `hitermTests/SplitNodeTests.swift` (inside the `SplitNodeTests` class, before the closing brace):

```swift
// MARK: - findNeighborByFrame (pane movement neighbor detection)

/// Helper: build `[(id, frame)]` from labeled frames for readability.
private func leaves(_ entries: (String, NSRect)...) -> [(id: String, frame: NSRect)] {
    entries.map { (id: $0.0, frame: $0.1) }
}

func testFindNeighborRightInTwoPaneHorizontal() {
    // A | B, focused on A
    let all = leaves(
        ("A", NSRect(x: 0,   y: 0, width: 400, height: 400)),
        ("B", NSRect(x: 400, y: 0, width: 400, height: 400))
    )
    let idx = findNeighborByFrame(leaves: all, fromIndex: 0, direction: .right)
    XCTAssertEqual(idx, 1)
}

func testFindNeighborLeftHasNoNeighbor() {
    let all = leaves(
        ("A", NSRect(x: 0,   y: 0, width: 400, height: 400)),
        ("B", NSRect(x: 400, y: 0, width: 400, height: 400))
    )
    // Focused on A; nothing is to its left.
    XCTAssertNil(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .left))
}

func testFindNeighborUpInTwoPaneVertical() {
    // Top A, bottom B — AppKit coords: top has higher y.
    let all = leaves(
        ("A", NSRect(x: 0, y: 400, width: 400, height: 400)),
        ("B", NSRect(x: 0, y: 0,   width: 400, height: 400))
    )
    // Focused on B, go up — expect A.
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 1, direction: .up), 0)
}

func testFindNeighborFourPaneGridRight() {
    // 2x2 grid:
    //   TL | TR      (y=400)
    //   ---+---
    //   BL | BR      (y=0)
    let all = leaves(
        ("TL", NSRect(x: 0,   y: 400, width: 400, height: 400)),
        ("TR", NSRect(x: 400, y: 400, width: 400, height: 400)),
        ("BL", NSRect(x: 0,   y: 0,   width: 400, height: 400)),
        ("BR", NSRect(x: 400, y: 0,   width: 400, height: 400))
    )
    // From TL, right → TR (same row, closest).
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .right), 1)
    // From TL, down → BL (same column, closest).
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .down), 2)
    // From BR, up → TR.
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 3, direction: .up), 1)
    // From BR, left → BL.
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 3, direction: .left), 2)
}

func testFindNeighborPrefersNearerWhenMultipleCandidates() {
    // Three panes horizontal: A | B | C (all 200 wide).
    let all = leaves(
        ("A", NSRect(x: 0,   y: 0, width: 200, height: 400)),
        ("B", NSRect(x: 200, y: 0, width: 200, height: 400)),
        ("C", NSRect(x: 400, y: 0, width: 200, height: 400))
    )
    // From A, right — two candidates (B, C). Expect B (nearer).
    XCTAssertEqual(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .right), 1)
}

func testFindNeighborSinglePane() {
    let all = leaves(("A", NSRect(x: 0, y: 0, width: 400, height: 400)))
    XCTAssertNil(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .right))
    XCTAssertNil(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .left))
    XCTAssertNil(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .up))
    XCTAssertNil(findNeighborByFrame(leaves: all, fromIndex: 0, direction: .down))
}
```

Also add the direction enum used by the tests (put it near the other enum usage at the top of the same test file, below `import`):

```swift
enum PaneDirection { case up, down, left, right }
```

- [ ] **Step 1.2: Run tests to verify they fail to compile**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodegen generate && xcodebuild -scheme hiterm -destination 'platform=macOS' test 2>&1 | tail -40
```
Expected: compile error — `findNeighborByFrame` not defined.

- [ ] **Step 1.3: Implement the pure function**

Add to `hiterm/Views/SplitView.swift`, right after the `import` statements at the top of the file:

```swift
/// Direction for pane neighbor lookup. Mirrors `ghostty_action_goto_split_e`
/// directional values but is independent of the C enum for testability.
enum PaneDirection { case up, down, left, right }

/// Find the nearest neighbor leaf in a given direction, using frame midpoints.
/// Pure function — takes identifiers and frames. Returns the index into the
/// input array, or nil if no neighbor exists in that direction.
///
/// "Nearest" = smallest squared distance between midpoints, among candidates
/// that lie strictly in the requested direction from the source midpoint.
/// AppKit convention: y increases upward, so "up" means greater y.
func findNeighborByFrame<ID: Equatable>(
    leaves: [(id: ID, frame: NSRect)],
    fromIndex: Int,
    direction: PaneDirection
) -> Int? {
    guard fromIndex >= 0, fromIndex < leaves.count, leaves.count > 1 else { return nil }
    let origin = leaves[fromIndex].frame
    let cx = origin.midX
    let cy = origin.midY

    var bestIdx: Int? = nil
    var bestDist = CGFloat.greatestFiniteMagnitude

    for (i, entry) in leaves.enumerated() where i != fromIndex {
        let sx = entry.frame.midX
        let sy = entry.frame.midY

        let isCandidate: Bool
        switch direction {
        case .left:  isCandidate = sx < cx
        case .right: isCandidate = sx > cx
        case .up:    isCandidate = sy > cy
        case .down:  isCandidate = sy < cy
        }
        guard isCandidate else { continue }

        let dx = sx - cx, dy = sy - cy
        let dist = dx * dx + dy * dy
        if dist < bestDist {
            bestDist = dist
            bestIdx = i
        }
    }
    return bestIdx
}
```

- [ ] **Step 1.4: Run tests to verify they pass**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodegen generate && xcodebuild -scheme hiterm -destination 'platform=macOS' test 2>&1 | tail -40
```
Expected: all new tests pass, existing tests still pass.

- [ ] **Step 1.5: Refactor `navigateToSplit` to use the new helper**

In `hiterm/Views/SplitView.swift`, replace the body of `navigateToSplit(direction:)` (currently around line 203) with:

```swift
func navigateToSplit(direction: ghostty_action_goto_split_e) {
    guard let focused = focusedSurface else { return }

    var leaves: [(surface: TerminalSurfaceView, frame: NSRect)] = []
    collectLeaves(rootNode, into: &leaves)
    guard leaves.count > 1 else { return }

    // Sequential navigation unchanged.
    if direction == GHOSTTY_GOTO_SPLIT_PREVIOUS || direction == GHOSTTY_GOTO_SPLIT_NEXT {
        guard let idx = leaves.firstIndex(where: { $0.surface === focused }) else { return }
        let nextIdx: Int
        if direction == GHOSTTY_GOTO_SPLIT_NEXT {
            nextIdx = (idx + 1) % leaves.count
        } else {
            nextIdx = (idx - 1 + leaves.count) % leaves.count
        }
        focusedSurface = leaves[nextIdx].surface
        return
    }

    // Directional: delegate to pure helper.
    guard let paneDir = Self.paneDirection(from: direction),
          let focusedIdx = leaves.firstIndex(where: { $0.surface === focused }) else { return }
    let entries = leaves.map { (id: ObjectIdentifier($0.surface), frame: $0.frame) }
    if let targetIdx = findNeighborByFrame(leaves: entries, fromIndex: focusedIdx, direction: paneDir) {
        focusedSurface = leaves[targetIdx].surface
    }
}

private static func paneDirection(from ghostty: ghostty_action_goto_split_e) -> PaneDirection? {
    switch ghostty {
    case GHOSTTY_GOTO_SPLIT_UP:    return .up
    case GHOSTTY_GOTO_SPLIT_DOWN:  return .down
    case GHOSTTY_GOTO_SPLIT_LEFT:  return .left
    case GHOSTTY_GOTO_SPLIT_RIGHT: return .right
    default: return nil
    }
}
```

- [ ] **Step 1.6: Build, run the app manually, verify focus navigation still works**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
open /Users/dkkang/Library/Developer/Xcode/DerivedData/hiterm-*/Build/Products/Debug/hiterm.app
```
Manual: split a pane with `Cmd+D`, navigate with `Cmd+Opt+Arrow`, confirm focus moves as before.

- [ ] **Step 1.7: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift hitermTests/SplitNodeTests.swift
git commit -m "Extract findNeighborByFrame as pure, tested helper"
```

---

## Task 2: `swapSurfaces` — tree-level swap without animation

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — add `swapSurfaces(_:_:)`.

- [ ] **Step 2.1: Implement `swapSurfaces` in `TerminalSplitView`**

Add inside `TerminalSplitView`, in the "Split Operations" MARK section (around where `navigateToSplit` lives):

```swift
/// Swap two leaf surfaces' positions in the tree. The split structure and
/// ratios are preserved; only the leaves exchange locations. No-op if
/// `a === b` or either surface is not present. Caller is responsible for
/// focus management and (optionally) animation — this function performs
/// the tree mutation and a synchronous `layoutSplits()`.
func swapSurfaces(_ a: TerminalSurfaceView, _ b: TerminalSurfaceView) {
    guard a !== b else { return }
    swapLeaves(in: rootNode, a: a, b: b)
    layoutSplits()
}

/// Recursively swap leaves by identity. Mutates `SplitContainer` nodes in
/// place (they are reference types with var fields).
private func swapLeaves(in node: SplitNode, a: TerminalSurfaceView, b: TerminalSurfaceView) {
    guard case .split(let container) = node else { return }

    // Handle first-level replacement.
    if case .leaf(let s) = container.first, s === a {
        container.first = .leaf(b)
    } else if case .leaf(let s) = container.first, s === b {
        container.first = .leaf(a)
    } else {
        swapLeaves(in: container.first, a: a, b: b)
    }

    if case .leaf(let s) = container.second, s === a {
        container.second = .leaf(b)
    } else if case .leaf(let s) = container.second, s === b {
        container.second = .leaf(a)
    } else {
        swapLeaves(in: container.second, a: a, b: b)
    }
}
```

- [ ] **Step 2.2: Build to confirm it compiles**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 2.3: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift
git commit -m "Add SplitView.swapSurfaces tree swap (no animation yet)"
```

---

## Task 3: Keyboard entry point — menu + `moveSplit` action

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — public method to trigger move by direction.
- Modify: `hiterm/Views/MainWindowController.swift` — `moveSplit(_:)` action.
- Modify: `hiterm/App/AppDelegate.swift` — Window menu entries.

- [ ] **Step 3.1: Add `moveFocusedSplit(direction:)` to `TerminalSplitView`**

Add inside `TerminalSplitView`, near `swapSurfaces`:

```swift
/// Move the focused pane in a direction by swapping with its nearest neighbor.
/// No-op if there is no neighbor, only one pane, or zoom is active.
func moveFocusedSplit(direction: PaneDirection) {
    guard preZoomRootNode == nil else { return }          // disabled while zoomed
    guard let focused = focusedSurface else { return }

    var leaves: [(surface: TerminalSurfaceView, frame: NSRect)] = []
    collectLeaves(rootNode, into: &leaves)
    guard leaves.count > 1 else { return }

    guard let focusedIdx = leaves.firstIndex(where: { $0.surface === focused }) else { return }
    let entries = leaves.map { (id: ObjectIdentifier($0.surface), frame: $0.frame) }
    guard let targetIdx = findNeighborByFrame(leaves: entries, fromIndex: focusedIdx, direction: direction) else { return }

    swapSurfaces(focused, leaves[targetIdx].surface)
    // Focus follows the moved pane.
    focusedSurface = focused
}
```

- [ ] **Step 3.2: Add `moveSplit(_:)` action in `MainWindowController`**

In `hiterm/Views/MainWindowController.swift`, after the existing `gotoSplit(_:)` method (around line 772):

```swift
@objc func moveSplit(_ sender: NSMenuItem) {
    let direction: PaneDirection
    switch sender.tag {
    case 2: direction = .up
    case 3: direction = .left
    case 4: direction = .down
    case 5: direction = .right
    default: return
    }
    currentTab?.splitView.moveFocusedSplit(direction: direction)
}
```

- [ ] **Step 3.3: Add menu items in `AppDelegate`**

In `hiterm/App/AppDelegate.swift`, immediately after the loop that adds the split-select items (around line 145, after `windowMenu.addItem(item)` closing brace), insert:

```swift
// Move splits section
windowMenu.addItem(.separator())
let moveSplitItems: [(String, String, Int)] = [
    ("Move Split Up",    "\u{F700}", 2),
    ("Move Split Left",  "\u{F702}", 3),
    ("Move Split Down",  "\u{F701}", 4),
    ("Move Split Right", "\u{F703}", 5)
]
for (title, key, tag) in moveSplitItems {
    let item = NSMenuItem(
        title: title,
        action: #selector(MainWindowController.moveSplit(_:)),
        keyEquivalent: key)
    item.keyEquivalentModifierMask = [.command, .shift]
    item.tag = tag
    windowMenu.addItem(item)
}
```

- [ ] **Step 3.4: Build and manually test**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodegen generate && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
open /Users/dkkang/Library/Developer/Xcode/DerivedData/hiterm-*/Build/Products/Debug/hiterm.app
```

Manual test:
- Split the window horizontally (`Cmd+D`) → two panes A|B, focus on B.
- Press `Cmd+Shift+Left` → panes swap instantly (no animation yet). Focus remains on the originally focused pane.
- Split again and repeat with different directions in a 4-pane layout.
- Confirm that a single-pane window does nothing.

- [ ] **Step 3.5: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift hiterm/Views/MainWindowController.swift hiterm/App/AppDelegate.swift
git commit -m "Add keyboard pane swap (Cmd+Shift+Arrow) with Window menu entries"
```

---

## Task 4: Animate swap

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — wrap swap in animation, add `isAnimatingSwap` gate.

- [ ] **Step 4.1: Add `isAnimatingSwap` flag and animation wrapper**

In `TerminalSplitView`, add a stored property near the top (below `focusedSurface`):

```swift
private var isAnimatingSwap: Bool = false
```

Replace the body of `swapSurfaces(_:_:)` with:

```swift
func swapSurfaces(_ a: TerminalSurfaceView, _ b: TerminalSurfaceView) {
    guard a !== b, !isAnimatingSwap else { return }

    // Capture current frames.
    let fromA = a.frame
    let fromB = b.frame

    // Swap in the tree and lay out to compute target frames.
    swapLeaves(in: rootNode, a: a, b: b)
    layoutSplits()
    let toA = a.frame
    let toB = b.frame

    // Reset to the "from" frames instantaneously, then animate to the targets.
    a.frame = fromA
    b.frame = fromB

    isAnimatingSwap = true
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.22
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ctx.allowsImplicitAnimation = true
        a.animator().frame = toA
        b.animator().frame = toB
    }, completionHandler: { [weak self] in
        self?.isAnimatingSwap = false
    })
}
```

- [ ] **Step 4.2: Build and manually test animation**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
open /Users/dkkang/Library/Developer/Xcode/DerivedData/hiterm-*/Build/Products/Debug/hiterm.app
```

Manual test:
- Split into 2 panes. `Cmd+Shift+Left/Right` — panes should slide across each other for ~0.22s.
- Split into 4 panes. Move in each direction; verify both target panes animate simultaneously.
- Press `Cmd+Shift+Arrow` rapidly — second move arriving during an in-progress animation should be ignored (no visual glitches).
- Observe Metal rendering during the animation. If panes appear stretched or flicker visibly mid-flight, note this for Task 4.3 (fallback).

- [ ] **Step 4.3: If Metal artifacts appear, add snapshot fallback**

Only do this step if manual testing in 4.2 shows visual artifacts.

Replace the body of `swapSurfaces(_:_:)` with the snapshot-based variant:

```swift
func swapSurfaces(_ a: TerminalSurfaceView, _ b: TerminalSurfaceView) {
    guard a !== b, !isAnimatingSwap else { return }

    let fromA = a.frame
    let fromB = b.frame

    // Snapshot each surface into a bitmap image.
    func snapshot(_ view: NSView) -> NSImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
    let imgA = snapshot(a)
    let imgB = snapshot(b)

    // Do the tree swap and layout.
    swapLeaves(in: rootNode, a: a, b: b)
    layoutSplits()
    let toA = a.frame
    let toB = b.frame

    // Hide live surfaces; show animating image proxies.
    a.isHidden = true
    b.isHidden = true
    let proxyA = NSImageView(frame: fromA)
    proxyA.image = imgA
    proxyA.imageScaling = .scaleAxesIndependently
    let proxyB = NSImageView(frame: fromB)
    proxyB.image = imgB
    proxyB.imageScaling = .scaleAxesIndependently
    addSubview(proxyA)
    addSubview(proxyB)

    isAnimatingSwap = true
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.22
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ctx.allowsImplicitAnimation = true
        proxyA.animator().frame = toA
        proxyB.animator().frame = toB
    }, completionHandler: { [weak self] in
        proxyA.removeFromSuperview()
        proxyB.removeFromSuperview()
        a.isHidden = false
        b.isHidden = false
        self?.isAnimatingSwap = false
    })
}
```

Rebuild and retest. If visuals are clean, proceed; if not, debug the snapshot sizing.

- [ ] **Step 4.4: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift
git commit -m "Animate pane swap with isAnimatingSwap guard"
```

---

## Task 5: `hitTestSurface(at:)` for drag target detection

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — add public helper.

- [ ] **Step 5.1: Add `hitTestSurface(at:)` method**

Add inside `TerminalSplitView`:

```swift
/// Return the leaf surface at a point in split-view coordinates, ignoring
/// dividers and overlays. Returns nil if the point is outside any pane or
/// the tree contains no leaves.
func hitTestSurface(at point: NSPoint) -> TerminalSurfaceView? {
    var leaves: [(surface: TerminalSurfaceView, frame: NSRect)] = []
    collectLeaves(rootNode, into: &leaves)
    for entry in leaves where entry.frame.contains(point) {
        return entry.surface
    }
    return nil
}
```

- [ ] **Step 5.2: Build**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5.3: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift
git commit -m "Add TerminalSplitView.hitTestSurface(at:) for drag target lookup"
```

---

## Task 6: `PaneDragOverlay` view

**Files:**
- Create: `hiterm/Views/PaneDragOverlay.swift`.

- [ ] **Step 6.1: Create the overlay view file**

Write `hiterm/Views/PaneDragOverlay.swift`:

```swift
import AppKit

/// Translucent overlay drawn on top of `TerminalSplitView` during a pane
/// drag. Shows a tinted rect on the source pane ("picked up") and a stronger
/// tint on the drop-target pane. Owns no logic — frames are set from outside.
class PaneDragOverlay: NSView {
    private let sourceLayer = CALayer()
    private let targetLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Overlay is input-transparent: the drag loop consumes events directly.
        layer?.masksToBounds = true

        sourceLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        sourceLayer.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        sourceLayer.borderWidth = 1
        sourceLayer.cornerRadius = 4
        sourceLayer.isHidden = true

        targetLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.30).cgColor
        targetLayer.borderColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        targetLayer.borderWidth = 2
        targetLayer.cornerRadius = 4
        targetLayer.isHidden = true

        layer?.addSublayer(sourceLayer)
        layer?.addSublayer(targetLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Non-interactive: events pass through to underlying views.
        return nil
    }

    func setSourceFrame(_ rect: NSRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            sourceLayer.frame = rect
            sourceLayer.isHidden = false
        } else {
            sourceLayer.isHidden = true
        }
        CATransaction.commit()
    }

    func setTargetFrame(_ rect: NSRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            targetLayer.frame = rect
            targetLayer.isHidden = false
        } else {
            targetLayer.isHidden = true
        }
        CATransaction.commit()
    }
}
```

- [ ] **Step 6.2: Build to verify it compiles and is included by xcodegen**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodegen generate && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6.3: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/PaneDragOverlay.swift
git commit -m "Add PaneDragOverlay view for drag visual feedback"
```

---

## Task 7: Custom drag loop in `TerminalSplitView`

**Files:**
- Modify: `hiterm/Views/SplitView.swift` — add `runPaneDragLoop`.

- [ ] **Step 7.1: Add the drag loop method**

Add inside `TerminalSplitView`, in a new `// MARK: - Pane Drag` section after the swap methods:

```swift
// MARK: - Pane Drag

/// Run a modal drag loop for moving a pane. Called by `TerminalSurfaceView`
/// when it detects `Cmd+Shift+mouseDown`. Blocks until the drag ends
/// (mouseUp, modifier released, Esc, or loop exit). On a valid drop,
/// performs a swap with the pane under the cursor.
func runPaneDragLoop(source: TerminalSurfaceView) {
    guard preZoomRootNode == nil else { return }     // zoom disables drag
    // Need at least two panes.
    var leavesCheck: [(surface: TerminalSurfaceView, frame: NSRect)] = []
    collectLeaves(rootNode, into: &leavesCheck)
    guard leavesCheck.count > 1 else { return }

    let overlay = PaneDragOverlay(frame: bounds)
    overlay.autoresizingMask = [.width, .height]
    overlay.setSourceFrame(source.frame)
    addSubview(overlay)

    let previousCursor = NSCursor.current
    NSCursor.closedHand.push()

    var target: TerminalSurfaceView? = nil

    loop: while let event = window?.nextEvent(matching: [
        .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown
    ]) {
        switch event.type {
        case .leftMouseDragged:
            // Cancel if modifier released.
            guard event.modifierFlags.contains([.command, .shift]) else {
                target = nil
                break loop
            }
            let point = convert(event.locationInWindow, from: nil)
            if let hit = hitTestSurface(at: point), hit !== source {
                target = hit
                overlay.setTargetFrame(hit.frame)
            } else {
                target = nil
                overlay.setTargetFrame(nil)
            }

        case .leftMouseUp:
            break loop

        case .flagsChanged:
            if !event.modifierFlags.contains([.command, .shift]) {
                target = nil
                break loop
            }

        case .keyDown:
            if event.keyCode == 53 {  // Esc
                target = nil
                break loop
            }

        default:
            break
        }
    }

    NSCursor.pop()
    _ = previousCursor  // silence unused warning; pop restores prior cursor
    overlay.removeFromSuperview()

    // Validate target is still in the tree and different from source.
    if let target, target !== source {
        var leavesNow: [(surface: TerminalSurfaceView, frame: NSRect)] = []
        collectLeaves(rootNode, into: &leavesNow)
        if leavesNow.contains(where: { $0.surface === target }) &&
           leavesNow.contains(where: { $0.surface === source }) {
            swapSurfaces(source, target)
            focusedSurface = source
        }
    }
}
```

- [ ] **Step 7.2: Build to verify it compiles**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED (drag loop is not yet triggered — Task 8).

- [ ] **Step 7.3: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/SplitView.swift
git commit -m "Add runPaneDragLoop modal drag handler in TerminalSplitView"
```

---

## Task 8: Hook drag into `TerminalSurfaceView.mouseDown`

**Files:**
- Modify: `hiterm/Views/TerminalSurfaceView.swift` — detect `Cmd+Shift` and defer to enclosing split view.

- [ ] **Step 8.1: Locate `mouseDown(with:)` in `TerminalSurfaceView.swift`**

Read the file and find the existing `override func mouseDown(with event: NSEvent)` method. Read its current body so you can preserve behavior for non-modified clicks.

- [ ] **Step 8.2: Add modifier check at the top of `mouseDown`**

Insert at the very beginning of `mouseDown(with event: NSEvent)`, before any other logic:

```swift
// Pane-move drag: Cmd+Shift+mouseDown delegates to the enclosing split view.
if event.modifierFlags.contains([.command, .shift]) {
    // Walk up the view hierarchy to find the TerminalSplitView.
    var view: NSView? = self.superview
    while let v = view {
        if let splitView = v as? TerminalSplitView {
            splitView.runPaneDragLoop(source: self)
            return
        }
        view = v.superview
    }
    // Fall through if no split view ancestor — shouldn't happen in practice.
}
```

- [ ] **Step 8.3: Build and manually test drag**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
open /Users/dkkang/Library/Developer/Xcode/DerivedData/hiterm-*/Build/Products/Debug/hiterm.app
```

Manual test:
- Create a 2-pane split. Hold `Cmd+Shift` and drag from pane A into pane B. Source tint appears on A, target tint on B; cursor is `closedHand`.
- Release over B → panes swap with animation. Focus remains on the originally dragged pane.
- Repeat but release over A (self) → no swap.
- Drag, release modifier mid-way → drag cancels.
- Drag, press Esc → drag cancels.
- 4-pane grid: drag any pane into any other, verify swap is correct.

- [ ] **Step 8.4: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/TerminalSurfaceView.swift
git commit -m "Wire Cmd+Shift+drag to TerminalSplitView pane-drag loop"
```

---

## Task 9: Menu validation (disable when no-op)

**Files:**
- Modify: `hiterm/Views/MainWindowController.swift` — `validateMenuItem` handling for Move Split items.

- [ ] **Step 9.1: Check existing `validateMenuItem` in `MainWindowController`**

Grep for `validateMenuItem` in `hiterm/Views/MainWindowController.swift`. If it exists, you'll extend it; if not, you'll add a new override.

- [ ] **Step 9.2: Add or extend `validateMenuItem`**

If `validateMenuItem` does not exist, add this override to `MainWindowController`:

```swift
override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(moveSplit(_:)) {
        guard let splitView = currentTab?.splitView else { return false }
        // Count leaves.
        var count = 0
        func countLeaves(_ node: SplitNode) {
            switch node {
            case .leaf: count += 1
            case .split(let c): countLeaves(c.first); countLeaves(c.second)
            }
        }
        countLeaves(splitView.rootNode)
        return count > 1
    }
    return super.validateMenuItem(menuItem)
}
```

If `validateMenuItem` already exists, merge the `moveSplit` check into it (return `count > 1` for moveSplit items; fall through otherwise).

Note: `rootNode` is currently `private(set) var`, which is accessible from `MainWindowController` because they're in the same module. If access-level errors occur, change the validator to call a new helper `splitView.paneCount` instead — add to `TerminalSplitView`:

```swift
var paneCount: Int {
    var n = 0
    func walk(_ node: SplitNode) {
        switch node {
        case .leaf: n += 1
        case .split(let c): walk(c.first); walk(c.second)
        }
    }
    walk(rootNode)
    return n
}
```

And use `return splitView.paneCount > 1` in the validator.

- [ ] **Step 9.3: Build and verify**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
open /Users/dkkang/Library/Developer/Xcode/DerivedData/hiterm-*/Build/Products/Debug/hiterm.app
```

Manual: with a single pane, open the Window menu — "Move Split Up/Down/Left/Right" should be greyed out. Split the window, reopen the menu — now enabled.

- [ ] **Step 9.4: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add hiterm/Views/MainWindowController.swift hiterm/Views/SplitView.swift
git commit -m "Disable Move Split menu items when fewer than 2 panes"
```

---

## Task 10: Final manual verification against spec checklist

**Files:** none — verification only.

- [ ] **Step 10.1: Walk the spec's manual test checklist**

Open `docs/superpowers/specs/2026-04-20-pane-movement-design.md` and run every item in the Manual test checklist section:

- [ ] 2/3/4/L layouts — all four keyboard directions
- [ ] Cmd+Shift drag: pickup overlay appears, target overlay tracks cursor
- [ ] Drop on different pane → swap + animation; focus on moved pane
- [ ] Drop on self/outside → cancel
- [ ] Release Cmd+Shift mid-drag → cancel
- [ ] Press Esc mid-drag → cancel
- [ ] Zoom active → menu items disabled, Cmd+Shift drag does not start
- [ ] Rapid keyboard moves — no overlap between animations, final state correct
- [ ] Metal-layer artifacts during animation (evaluate; Task 4.3 fallback applied if needed)

For any failure, return to the task that owns that concern, fix it, and re-verify.

- [ ] **Step 10.2: Run full test bundle one more time**

Run:
```bash
cd /Users/dkkang/dev/hiterm && xcodebuild -scheme hiterm -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: all `SplitNodeTests` pass.

- [ ] **Step 10.3: If all green, merge the branch / mark feature done**

```bash
cd /Users/dkkang/dev/hiterm && git log --oneline main..HEAD
```
Review the commit history, confirm each task is one focused commit, then merge per your project's workflow.

---

## Notes for the implementer

- The keyboard shortcut `Cmd+Shift+Arrow` nominally conflicts with macOS text-selection-to-line-start/end, but `TerminalSurfaceView` does not implement those bindings, so there is no real conflict today. If you later add line-based selection to the terminal surface, the menu key equivalent will still take precedence (NSMenu handles the key equivalent before it reaches the view).
- `NSAnimationContext.runAnimationGroup` with `allowsImplicitAnimation = true` animates `frame` changes on `NSView`'s animator proxy. For `CAMetalLayer`-backed views, the layer position animates cleanly but drawable size can lag. The snapshot fallback in Task 4.3 exists for that case — only switch to it if you observe a real issue.
- The drag loop uses `window?.nextEvent(matching:)`, which is a modal pull. This blocks the main run loop's normal event dispatch but keeps the app responsive to system events (display refresh, window close via Cmd+W is filtered out because we only pull `.leftMouseDragged/.leftMouseUp/.flagsChanged/.keyDown`). If the user hits Cmd+W during a drag, the close event queues and fires after the loop exits — acceptable behavior.
- Tests in `hitermTests` are built against the app bundle (BUNDLE_LOADER), so you can `@testable import hiterm` and call internal symbols. The pure `findNeighborByFrame` is file-private in `SplitView.swift` by default — change `func findNeighborByFrame` to `internal func findNeighborByFrame` (i.e., remove any `fileprivate`/`private`) if it is not already internal. The plan's Step 1.3 uses `func` (defaults to internal) — keep it so.
