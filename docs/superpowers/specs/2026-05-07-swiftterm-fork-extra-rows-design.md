# SwiftTerm Fork — Extra Rows + Output Slide-In PoC — Design

**Date**: 2026-05-07
**Branches**:
- hiterm: continues on `experiment/swiftterm`
- SwiftTerm fork: `github.com/hulryung/SwiftTerm`, work on `hiterm/extra-rows`
**Status**: design approved, awaiting implementation plan
**Parent spec**: `docs/superpowers/specs/2026-05-07-swiftterm-experiment-design.md`

## Goal

Validate the headline value claim of the SwiftTerm experiment: that we can render rows beyond the live viewport so a row newly appended by terminal output **slides into view** rather than appearing instantly. This is the capability libghostty's Metal-backed surface did not give us.

If this PoC succeeds, it becomes the centerpiece of the production migration. If it fails, the migration's value claim is significantly weaker and we re-evaluate.

## Motivation

The first SwiftTerm experiment proved sub-row pixel-resolution scrolling works on user gesture. During Task 12 manual validation the user identified the remaining gap: rows newly created at the bottom (and rows leaving at the top) appear/disappear instantly because SwiftTerm draws exactly the visible viewport. The "row slides in from below" behavior — the visible payoff of pixel-level rendering control — was not demonstrated.

This PoC closes that gap by patching SwiftTerm to draw N+2 rows (one above, one below the viewport) and animating the transition on output advance.

## Scope

**In scope (PoC)**:
- A SwiftTerm fork on `github.com/hulryung/SwiftTerm` with a feature branch `hiterm/extra-rows`.
- A patch that adds two opt-in properties (`extraRowsAbove`, `extraRowsBelow`) and draws those rows from the buffer.
- A new delegate callback `didAdvanceViewport(source:by:)` so hiterm knows when to start the slide-in animation.
- hiterm-side wiring in `SwiftTermSurfaceView` and `SwiftTermPixelScrollLayer` to enable extra rows, clip the wrapper, and play the slide-in animation.
- Manual validation against the criteria below.

**Explicitly out of scope (deferred)**:
- User-driven sub-row scroll improvements (the existing PoC is enough for now).
- IME / preedit handling inside extra rows.
- Cursor or text selection rendering inside extra rows — extra rows are visual overdraw only.
- Mouse hit-testing inside extra rows — clamp to viewport.
- iOS / non-Mac SwiftTerm targets — patch ships across platforms but only macOS is validated.
- Animations longer/more elaborate than the 80ms ease-out transform.
- Burst output animation — bursts skip animation by design.

## Non-Goals

- Production parity with the existing ghostty path (still the migration spec's job).
- Performance optimization beyond "doesn't visibly drop frames at PoC use levels."
- Upstreaming the SwiftTerm patch — we keep our fork.

## Approach

**Fork SwiftTerm and patch its draw loop.** This is the architecturally clean path. Alternatives considered:

- **Snapshot overlay (no fork)** — capture CGImage of the view, animate the snapshot. Rejected as "too tweaky" by the user; per-frame snapshot capture is fragile and has timing edge cases.
- **Hold-and-redraw (no fork)** — block SwiftTerm's redraw while animating. SwiftTerm doesn't expose a hook for this without modifying it anyway.
- **Fork** — modify the draw loop to render extra rows, expose a delegate hook for advance events. Wins because the same primitive (extra-row rendering) also enables future user-driven sub-row scroll without the empty-edge artifact, with no additional changes.

## Architecture

### Repos and dependency wiring

- SwiftTerm fork on `github.com/hulryung/SwiftTerm`.
- `main` of the fork tracks upstream.
- All patches go to a feature branch `hiterm/extra-rows` and merge into `main` after validation.
- hiterm `project.yml` `packages:` block changes URL to the fork and pins by commit SHA:
  ```yaml
  packages:
    SwiftTerm:
      url: https://github.com/hulryung/SwiftTerm
      revision: <commit-sha>
  ```
- hiterm continues on `experiment/swiftterm` — no new branch for this PoC.

### Fork patch: extra-rows feature

**Location**: `Sources/SwiftTerm/Apple/AppleTerminalView.swift` is the cross-platform shared draw logic. Drawing happens inside a row loop that iterates `0..<terminal.rows`. The patch generalizes the bounds.

**Public API added** (on `TerminalView` / `AppleTerminalView`):

```swift
/// Number of rows to render above the live viewport, sourced from scrollback.
/// Default 0 preserves existing behavior. Cursor and selection are not drawn
/// in this region; mouse hit-testing clamps to the viewport.
public var extraRowsAbove: Int = 0

/// Number of rows to render below the live viewport, sourced from buffer
/// lines past the live tail (e.g. lines just appended by output but not yet
/// promoted into the viewport).
public var extraRowsBelow: Int = 0
```

**Draw loop change**:

- Before: `for row in 0..<terminal.rows`.
- After: `for row in -extraRowsAbove ..< (terminal.rows + extraRowsBelow)`.
- Negative `row` reads from `buffer.lines[buffer.yDisp - 1 - (-(row+1))]` (older scrollback). Out-of-range → blank.
- `row >= terminal.rows` reads from `buffer.lines[buffer.yBase + row]` (or whatever the buffer's "next row past live tail" accessor is). Out-of-range → blank.

**Y coordinate mapping**: shift everything down so y=0 corresponds to the top of the *extended* drawing area, not the viewport.

- Before: row r → y = r * cellHeight.
- After: row r → y = (r + extraRowsAbove) * cellHeight.

The view's intrinsic content height effectively becomes `(extraRowsAbove + terminal.rows + extraRowsBelow) * cellHeight`. The view's frame as set by hiterm reflects this; the wrapper clips back to the viewport-only region (see hiterm wiring).

**Cursor**: drawn only when the row is within `0..<terminal.rows`. Skip in extra rows.

**Selection**: drawn only within `0..<terminal.rows`. Selection in extra rows is impossible at PoC stage.

**Mouse hit-testing**: when converting click coordinates to row/col, clamp `row` to `0..<terminal.rows` (clip to viewport).

**Out-of-fork-scope**: IME positioning, scrollbar, and any other code that touches y=0 boundary needs to be reviewed for the new "y=0 is one row above viewport" model. The patch must update each consumer or document why no change is needed.

### Fork patch: viewport-advance delegate hook

**Why**: hiterm needs to know when the viewport just advanced (typically due to terminal output appending a new line) so it can start the slide-in animation.

**Patch**: add to `TerminalViewDelegate`:

```swift
/// Called immediately after the viewport advances by N rows due to output.
/// `lines` is positive (1 for a typical line feed). Not called for
/// programmatic scroll, IME, or user-driven scrollback navigation.
public func didAdvanceViewport(source: TerminalView, by lines: Int) {}
```

A default empty implementation in a protocol extension keeps existing delegate adopters unaffected.

The fork calls this at the point where the terminal model has finished processing the line feed and the view is about to redraw — i.e., the new state is already in the buffer; this is a *post-fact* notification (matches Option B from the design discussion). hiterm uses this to apply a one-time `+rowHeight` transform and animate it back to 0.

### hiterm-side wiring

**`SwiftTermSurfaceView.configure()` adds**:

```swift
extraRowsAbove = 1
extraRowsBelow = 1
```

**`SwiftTermPixelScrollLayer`** updates:

- `wrapper.layer.masksToBounds = true` (clip extra rows to wrapper bounds).
- Override `layout()`:
  - `surface.frame.size.height = wrapper.bounds.height + 2 * rowHeight`
  - `surface.frame.size.width = wrapper.bounds.width`
  - `surface.frame.origin.y = -rowHeight`
  - `surface.frame.origin.x = 0`
- This positions the surface so the live viewport (N rows in the middle of the surface's drawing area) aligns exactly with the wrapper's bounds. Extra row above and extra row below sit just outside the wrapper and are clipped.

**`SwiftTermSurfaceView` adopts** `didAdvanceViewport(source:by:)` and forwards to the wrapper:

```swift
func didAdvanceViewport(source: TerminalView, by lines: Int) {
    (superview as? SwiftTermPixelScrollLayer)?.handleViewportAdvance(lines: lines)
}
```

**Animation in `SwiftTermPixelScrollLayer.handleViewportAdvance(lines:)`**:

```swift
func handleViewportAdvance(lines: Int) {
    // Burst skip: only animate single-row advances when no animation is in flight.
    guard lines == 1, !isAnimatingAdvance else { return }
    let h = rowHeight

    // Initial state: jump the surface layer down by rowHeight (visually shows
    // the prior viewport position with the new tail row drawn in extraRowsBelow).
    surface.layer?.transform = CATransform3DMakeTranslation(0, h, 0)

    // Animate to identity over 80ms ease-out.
    let anim = CABasicAnimation(keyPath: "transform")
    anim.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, h, 0))
    anim.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    anim.duration = 0.08
    anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    anim.delegate = self  // for didStop callback to clear isAnimatingAdvance
    surface.layer?.add(anim, forKey: "advanceSlide")
    surface.layer?.transform = CATransform3DIdentity   // model value at end of animation
    isAnimatingAdvance = true
}
```

**Interaction with the existing user-scroll transform**: the user-driven `accumulatedPixelOffset` translation and the advance animation both write to `surface.layer.transform`. They must not stomp on each other.

- During `isAnimatingAdvance` the user-scroll handler holds off applying its own transform updates (events still consumed and accumulator updated, but no `applyLayerTranslation` call). Once the advance animation completes, the user-scroll handler resumes and rewrites the transform to reflect the current accumulator.
- This is acceptable for PoC: the user is unlikely to scroll during an 80ms output animation; if they do, their movement is delayed by ≤80ms.

## Validation Plan

**Fork-side verification (SwiftTerm fork repo)**:

1. After applying the patch, `swift build` from the fork repo succeeds.
2. Run any existing SwiftTerm tests in the fork — they pass.

**hiterm-side manual checks**:

1. `xcodegen generate && xcodebuild -scheme hiterm -configuration Debug build` — succeeds, SPM resolves the fork URL, the fork's commit SHA is fetched.
2. Launch with `HITERM_BACKEND=swiftterm`. Window opens with zsh prompt.
3. Run `seq 1 200`; scroll back manually. Visually inspect: at any sub-row offset during user scroll, the previously-empty top edge now shows part of an additional row (the one above the viewport). If you can see an extra partial row peeking from the top during slow scroll, the fork patch is wired correctly.
4. Type `echo hi` and press Return. The new prompt+output line should slide into view from below over ~80ms instead of appearing instantly.
5. Type `seq 1 5` quickly. The first line animates; subsequent lines should appear without visible artifact (animation skipped).
6. Type `cat /usr/share/dict/words | head -200`. Burst output should appear at full speed without stuttering or dropped lines.
7. Regression: launch without env var → existing ghostty path runs unchanged.
8. Cursor and selection: confirm the cursor is never visible in the extra-row regions and that text selection cannot extend into them.

## Risks & Known Limitations

- **SwiftTerm draw code complexity**: the draw loop in `AppleTerminalView` may be more tangled than the spec assumes. If the patch turns out to require touching many subsystems (font caching, dirty-rect tracking, attributed string runs), reassess scope before deepening.
- **iOS regression**: the patch changes shared cross-platform code. We do not test iOS. Consequence: SwiftTerm iOS clients of our fork might break. Acceptable since the fork is internal.
- **Selection at extra-row boundary**: a drag selection that ends exactly at the extra-row gutter may behave oddly. We accept the visual edge case.
- **Buffer access for "row past live tail"**: SwiftTerm's buffer may not expose lines past `yBase + rows - 1` directly. If those lines aren't accessible without internal API hacks, the extraRowsBelow patch becomes harder. Verify during implementation.
- **Animation interrupt**: rapid output during user gesture can produce a moment where the user-scroll transform is briefly suspended. PoC tolerable.

## Exit Criteria

- ✅ **Success**: validation checks 1–8 all pass. The headline capability is real on SwiftTerm. Spec migration goes ahead with this as the central feature.
- ❌ **Failure**: the fork patch turns out to be much larger than expected, or the rendered result has artifacts we can't fix without deeper SwiftTerm rework, or the slide-in animation visibly competes with output throughput. Record the findings, preserve the fork branch, and re-evaluate whether the migration is worth its cost.

In either case, append a short result memo under a `## Result` heading and preserve `hiterm/extra-rows` in the fork.

## Out of This Spec

The full production migration (replacing the ghostty path with the SwiftTerm path including tabs, splits, search, IME, settings sync, themes) remains its own future spec. This PoC is a prerequisite that de-risks the migration's headline value claim.
