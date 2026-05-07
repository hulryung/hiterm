# SwiftTerm Experiment — Design

**Date**: 2026-05-07
**Branch**: `experiment/swiftterm` (from `main`)
**Status**: design approved, awaiting implementation plan

## Goal

Validate, on an isolated branch, whether replacing libghostty with SwiftTerm gives hiterm the **pixel-level rendering/scroll control** that libghostty's Metal-rendered surface does not expose. The experiment is a Proof-of-Concept, not a production replacement.

## Motivation

The current terminal surface is rendered by libghostty into a Metal-backed `NSView`. Smooth-scroll and frame-resize animations have hit the limits of what we can do from outside that opaque surface — for example, our `SmoothScrollLayer` translates the whole layer but fights with libghostty's own redraw cadence, and pane-swap animations had to be reworked multiple times because the Metal-backed frames are not pixel-stable during transitions.

SwiftTerm renders via CoreGraphics into a normal `NSView`. That gives hiterm direct control over draw geometry, sub-row offsets, and layer compositing — at the cost of Metal performance and SwiftTerm's smaller feature set (notably IME parity and font rendering quality).

The user's primary motivation is **rendering/scroll pixel control**, not build simplification or feature parity. SwiftTerm is the correct tool for that motivation; the open question is whether its tradeoffs (CG performance, IME, etc.) are acceptable.

## Scope

**In scope (MVP)**:
- A second app entry path that opens a single-window, single-pane SwiftTerm experiment.
- Running `zsh` with basic ANSI support inside SwiftTerm.
- A sub-row smooth-scroll PoC that demonstrates pixel-level scroll control.
- Manual validation against the exit criteria below.

**Explicitly out of scope (deferred)**:
- Tabs, splits, search overlay, sidebar, drag-to-move panes.
- Settings sync (font, color, key bindings) — experiment uses hard-coded defaults.
- IME / Korean input parity. Breakage here is accepted as a known limitation.
- Sparkle, notarization, or release packaging changes.
- Migration of the production code path. If the PoC succeeds, the production migration is a **separate spec/plan**, not part of this work.

## Non-Goals

- Achieving feature parity with the current ghostty-backed hiterm.
- Performance benchmarking beyond "is it visibly usable for the PoC."
- Removing `GhosttyKit` / libghostty from the project.

## Approach

**A — Parallel experiment window.** Add SwiftTerm alongside libghostty. A new entry path, gated by an environment variable, opens an isolated experiment window. The existing ghostty path is untouched, so the production build keeps working on the same branch.

Alternatives considered and rejected:
- **B — Backend abstraction with toggle.** Introducing a `TerminalBackend` protocol now is premature abstraction; ghostty's `ghostty_action_s` model is too broad to abstract well in one pass.
- **C — Rip-and-replace.** High risk for an experiment. Breaks the production path for days, and forces touching tabs/splits/search/IME before we even know if the PoC concept works.

## Architecture

### Branch & dependency

- New branch: `experiment/swiftterm` from `main`.
- SwiftTerm added via Swift Package Manager. `project.yml` gets a package dependency on `https://github.com/migueldeicaza/SwiftTerm` pinned to a specific tag. Run `xcodegen generate` to materialize.
- `GhosttyKit` and `libghostty.a` remain in place, untouched.

### File layout

All new code lives under `hiterm/Experimental/SwiftTerm/`:

- `SwiftTermExperimentEntry.swift` — decides whether to enter the experiment path; opens the window.
- `SwiftTermExperimentWindowController.swift` — owns one `NSWindow`. No tab bar, no split view, no search overlay.
- `SwiftTermSurfaceView.swift` — `LocalProcessTerminalView` subclass. Starts `/bin/zsh -l`, handles process termination.
- `SwiftTermPixelScrollLayer.swift` — wrapper view that hosts the surface and intercepts wheel events for the sub-row scroll PoC.

### Modified files

Exactly one production file is modified:

- `hiterm/App/AppDelegate.swift` — at `applicationDidFinishLaunching`, if `ProcessInfo.environment["HITERM_BACKEND"] == "swiftterm"`, call `SwiftTermExperimentEntry.openWindow()` and **return** without invoking the ghostty path. Otherwise behavior is identical to today.

`Log.swift` gets a new `swiftterm` category. No other edits.

## Component Detail

### Entry & lifecycle

```
applicationDidFinishLaunching:
  if HITERM_BACKEND == "swiftterm":
      SwiftTermExperimentEntry.openWindow()
      return            // ghostty path is not invoked
  else:
      <existing GhosttyApp init + MainWindowController path>
```

The experiment window:
- Title: "hiterm — SwiftTerm Experiment".
- Single `NSWindow`, content view is a `SwiftTermPixelScrollLayer` containing one `SwiftTermSurfaceView`.
- Closing the window terminates the app.
- Menu bar: macOS defaults only. Custom hiterm menus (Split, Move, Swap, Search, etc.) are not wired into this path.
- `SettingsManager`, Sparkle, and the keyboard shortcut manager are **not** initialized in this path.

### SwiftTermSurfaceView

- Subclass of SwiftTerm's `LocalProcessTerminalView` (AppKit `NSView` subclass).
- On init: `startProcess(executable: "/bin/zsh", args: ["-l"], environment: nil)`.
- Font: `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)`. Hard-coded.
- Colors: SwiftTerm defaults. No theme application.
- Key input, mouse selection, default wheel scroll: SwiftTerm defaults.
- IME / preedit: not implemented. Korean input may be broken — accepted.
- Resize: handled implicitly through `NSView` `layout()` and SwiftTerm's grid recompute.
- `LocalProcessTerminalViewDelegate.processTerminated` closes the window.

### Pixel-scroll PoC (the central experiment)

**Claim being tested**: on top of SwiftTerm we can render scroll movement at sub-row pixel resolution, which we could not do with the libghostty-backed surface.

**Demo**: sub-row smooth scroll. When the user trackpad-scrolls, the content moves by exact pixel deltas. When accumulated delta crosses one row height, SwiftTerm's scrollback advances by one line and the pixel offset is taken modulo row height.

**Implementation**:
- `SwiftTermPixelScrollLayer` is layer-backed (`wantsLayer = true`) and contains one child `SwiftTermSurfaceView`.
- Wheel events are intercepted at the wrapper. The wrapper keeps an `accumulatedPixelOffset: CGFloat`.
- Each frame (driven by `CVDisplayLink` or `CADisplayLink`), the wrapper sets `surfaceView.layer.bounds.origin.y = -accumulatedPixelOffset`.
- When `|accumulatedPixelOffset| >= rowHeight`, send `scroll(linesUp/Down: 1)` to the underlying SwiftTerm `Terminal` and subtract `rowHeight` from the accumulator. Keep going until `|accumulator| < rowHeight`.
- Inertia is integrated in pixel space directly (no reliance on `NSScrollView` momentum).

**Pass criteria**:
- Slow trackpad swipe produces visibly smooth motion that does **not** snap to row boundaries.
- No flicker, no tearing, no rows disappearing during the sub-row state.
- Fast swipes feel naturally inertial.

**Out of scope inside the PoC itself**: production-quality acceleration curves, bounce at scrollback edges, keyboard PgUp/PgDn consistency.

## Validation Plan

Manual checks (no automated tests at PoC stage):

1. `HITERM_BACKEND=swiftterm open hiterm.app` → experiment window opens, zsh prompt is visible.
2. `ls`, `vim`, `htop` work with normal ANSI behavior.
3. Launch without the env var → existing ghostty path runs unchanged (regression check).
4. Trackpad-scroll → content visibly stops between row boundaries (sub-row offset is observable).
5. Resize the window → grid updates, no text corruption or layout artifacts.

## Risks & Known Limitations

- **Korean / IME input**: SwiftTerm's IME pipeline differs from ghostty's `ghostty_surface_preedit`. Likely broken in the PoC; accepted.
- **Performance**: CoreGraphics rendering is slower than Metal. Heavy output streams (e.g., `find /`) may drop frames. If clearly unusable, that itself is a result.
- **SwiftTerm version drift**: pin to a specific tag. Verify on macOS 14+.
- **Build time**: first build slower due to SPM dependency fetch. Not a blocker.

## Exit Criteria

- ✅ **Success**: all pass criteria in the PoC (§ Pixel-scroll PoC) and validation plan are met. The branch is worth bringing toward `main`. A separate spec/plan will cover the production migration.
- ❌ **Failure**: PoC pass criteria are not met, or SwiftTerm itself fails hiterm's needs at the experiment level. Branch is preserved (not deleted) for reference, libghostty stays, and we look at alternative approaches (e.g., patching ghostty directly).

In either case, append a short result memo to the bottom of this file under a `## Result` heading and preserve the branch.

## Out of This Spec

The production migration plan (replacing the ghostty path on `main`, handling tabs/splits/search/IME/settings sync) is intentionally not designed here. It will be drafted as a separate spec only if this experiment succeeds.
