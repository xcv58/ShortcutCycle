# Tap-to-Cycle Mode Exploration

## Context

A user reported that a shortcut mapped to a mouse gesture, such as right-click
and swipe down, does not keep the switching HUD open long enough to choose an
app. This matches the current interaction model: ShortcutCycle is designed
around keyboard shortcuts where one or more modifier keys remain physically held
while the user cycles.

This planning note tracks whether and how ShortcutCycle should support
one-shot shortcut sources before we decide whether to document mouse gestures as
unsupported.

## Current Behavior

ShortcutCycle currently treats group shortcuts as press-and-hold interactions:

- `ShortcutManager` registers group shortcuts with `KeyboardShortcuts.onKeyDown`.
- `AppSwitcher` resolves the next app and calls `HUDManager.scheduleShow`.
- `HUDManager` prepares an invisible HUD, reveals it after a short delay, and
  monitors the configured modifier keys.
- Releasing any required modifier finalizes the pending selection and hides the
  HUD.
- Holding the active shortcut key can start the repeating cycle loop.

This works well for keyboard usage, but a mouse gesture tool often sends a fast
key-down/key-up sequence. By the time the HUD tries to reveal, the required
modifiers may already be released, so the session finalizes immediately.

Relevant files:

- `ShortcutCycle/ShortcutCycle/Services/ShortcutManager.swift`
- `ShortcutCycle/ShortcutCycle/Services/AppSwitcher.swift`
- `ShortcutCycle/ShortcutCycle/Services/HUD/HUDManager.swift`
- `ShortcutCycle/ShortcutCycleTests/PressAndHoldTests.swift`
- `ShortcutCycle/ShortcutCycle/Models/AppGroup.swift`

## Product Goal

Support shortcuts that cannot be held continuously, including mouse gestures,
Stream Deck buttons, macro tools, accessibility switches, and URL/automation
style triggers that behave like a tap instead of a physical hold.

The feature should be framed as a shortcut interaction mode, not as mouse
support. The input source is less important than whether the trigger can keep
modifiers held.

## Proposed Mode

Add a new optional group shortcut interaction mode:

- `pressAndHold`: current behavior and default for existing users.
- `tapToCycle`: each shortcut activation advances the HUD selection and keeps
  the HUD visible without requiring modifier keys to remain held.

In `tapToCycle` mode:

- First tap starts a HUD session and selects the next app.
- Additional taps while the HUD is visible advance the selected app.
- Clicking a HUD item selects and activates it.
- Return confirms the current selection.
- Escape cancels without activating a new app.
- A short inactivity timeout finalizes the current selection.
- The existing press-and-hold loop remains unchanged for groups using the
  default mode.

## Implementation Sketch

1. Add a core enum, likely `ShortcutInteractionMode`, with a backward-compatible
   default of `.pressAndHold`.
2. Add an optional stored property to `AppGroup`, such as
   `shortcutInteractionMode`, defaulting through a computed property.
3. Thread the resolved mode through `AppSwitcher.handleShortcut`,
   `cycleAllApps`, `cycleRunningAppsOnly`, and `showHUD`.
4. Extend `HUDManager.scheduleShow` with an interaction-mode parameter.
5. For `pressAndHold`, keep the existing monitor/finalize path untouched.
6. For `tapToCycle`, reveal immediately or after a very short delay, skip
   modifier-release finalization, install keyboard/click-away controls, and
   start/reset an inactivity finalize timer.
7. Add a cancellation path so Escape can dismiss the HUD without activating the
   pending target app.
8. Add settings UI for the group mode only after the behavior is proven.
9. Update export/import tests if the mode is stored in `AppGroup`.

## Design Questions

- Should the mode be per group or global? Per group is more flexible, but it
  touches the app group model and settings UI. A global advanced setting is
  simpler but may surprise users who only want one group to work with a gesture.
- Should tap mode reveal immediately, or keep the existing 200 ms hold delay?
  Immediate reveal seems better for one-shot triggers.
- Should timeout finalize or cancel? Finalize is closer to Command-Tab, while
  cancel is safer when the user accidentally triggers the shortcut.
- Should clicking outside finalize, cancel, or leave the HUD up until timeout?
- Should a repeated tap while the HUD is still invisible reveal and advance, or
  reveal only? Existing repeated invocation currently reveals immediately.
- Do we need a URL command or automation entry point for tap-mode selection?

## Validation Plan

Before shipping:

- Add unit coverage for `tapToCycle` HUD lifecycle:
  - one-shot shortcut reveals and stays visible after modifiers are released
  - repeated shortcut advances selection
  - timeout finalizes once
  - Escape cancels without activation
  - click/Return finalizes with activation
- Add regression coverage proving `pressAndHold` still finalizes on modifier
  release and still supports the repeating loop.
- Run `cd ShortcutCycle && swift test`.
- Manually test with a keyboard shortcut.
- Manually test with at least one macro or mouse gesture tool that emits a
  one-shot shortcut.

## Rollout

This exploration should land before website or app copy changes. If the mode is
feasible, product copy can explain how to use one-shot triggers. If we decide
not to support it, then the website and app can document the limitation with a
clearer rationale.
