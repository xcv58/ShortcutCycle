# Tap-to-Cycle Mode Exploration

## Context

A user reported that a shortcut mapped to a mouse gesture, such as right-click
and swipe down, does not keep the switching HUD open long enough to choose an
app. This matches the current interaction model: ShortcutCycle is designed
around keyboard shortcuts where one or more modifier keys remain physically held
while the user cycles.

This planning note tracks the first lightweight implementation of one-shot
shortcut support before we decide whether to document mouse gestures as a
supported workflow.

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

## Implemented Mode

Add a new optional per-group shortcut trigger mode:

- `pressAndHold`: current behavior and default for existing users.
- `tapToCycle`: each shortcut activation advances the HUD selection and keeps
  the HUD visible without requiring modifier keys to remain held.

In `tapToCycle` mode:

- First tap starts a HUD session and selects the next app.
- Additional taps while the HUD is visible advance the selected app.
- Clicking a HUD item selects and activates it.
- Return confirms the current selection.
- Escape cancels without activating a new app.
- A 2-second inactivity timeout finalizes the current selection.
- The existing press-and-hold loop remains unchanged for groups using the
  default mode.

This is deliberately small: no new timing preference, no dedicated mouse
integration, and no URL automation surface yet.

## Implementation

1. Add `ShortcutTriggerMode` in Core with `.pressAndHold` and `.tapToCycle`.
2. Store an optional `shortcutTriggerMode` on `AppGroup`; legacy groups resolve
   to `.pressAndHold`.
3. Thread the resolved mode through `AppSwitcher` into `HUDManager`.
4. Keep the existing modifier-monitor and loop behavior for `.pressAndHold`.
5. For `.tapToCycle`, reveal the HUD immediately, skip modifier-release
   finalization, allow repeated shortcut taps to advance selection, and reset a
   short auto-finalize timer.
6. Add Escape cancellation and Return confirmation through the existing HUD key
   handling path.
7. Add a small "Shortcut Behavior" picker next to the existing group cycling
   mode setting.
8. Include the mode in backup diffs and localization coverage.

## Remaining Questions

- Is a 2-second timeout the right default once tested with real mouse gesture
  tools?
- Should clicking outside finalize, cancel, or leave the HUD up until timeout?
- Should tap mode eventually get an explicit "confirm on click/Return only"
  variant, or is auto-finalize the better lightweight behavior?
- Do we need a URL command or automation entry point for tap-mode selection?

## Validation Plan

Implemented coverage:

- `tapToCycle` reveals immediately and does not install modifier-release
  monitors.
- Repeated shortcut invocations advance the selection.
- The idle timeout finalizes once.
- Escape cancels without activation.
- `AppGroup` decoding remains backward-compatible.
- Backup diffs detect shortcut behavior changes.
- Localization key coverage remains complete.

Still worth doing before release:

- Manually test with a keyboard shortcut.
- Manually test with at least one macro or mouse gesture tool that emits a
  one-shot shortcut.

## Rollout

If this behavior feels good in manual testing, website and app copy can explain
tap-to-cycle as the recommended mode for mouse gestures, Stream Deck buttons,
and other one-shot shortcut sources.
