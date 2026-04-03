# Off-Space Settings Auto-Close Design

Date: 2026-04-03
Status: Approved for planning
Supersedes: `docs/superpowers/specs/2026-04-03-settings-space-jump-warning-design.md`

## Summary

ShortcutCycle should stop relying on warning copy alone for the Settings-on-another-Space case.

Instead, when an app-switch shortcut is about to show the HUD and the Settings window is open on a different macOS Space, ShortcutCycle should close the Settings window first and then continue with the normal HUD flow.

## Problem

The warning-only approach is honest, but it does not solve the real issue.

When the HUD appears, ShortcutCycle activates itself first. If the Settings window is already open on another Space, that activation can pull macOS back to the Settings window's Space before the target app activation finishes.

That means users can still see:

- a jump to the target app's Space
- an immediate jump back to the Space containing Settings

This is still disruptive even if the app warns about it.

## Goals

- Prevent the jump-back caused by an off-Space Settings window during HUD switching
- Keep the normal HUD behavior for all other cases
- Avoid the earlier hide-and-restore Settings lifecycle complexity
- Use the app's existing Settings close path instead of inventing a new window state

## Non-Goals

- Closing Settings for every shortcut press
- Closing Settings when it is already on the active Space
- Reintroducing deferred HUD activation or Settings restore state
- Adding new warning copy inside the HUD for this issue

## Chosen Approach

Before showing the HUD, ShortcutCycle should check whether a visible Settings window exists on another Space.

If it does:

- close that Settings window
- continue into the standard HUD flow

If it does not:

- behave exactly as the normal HUD path does today

This special handling is intentionally narrow:

- it applies only to app-switch shortcuts
- it applies only when the HUD will actually be shown
- it applies only when Settings is visible and off-Space

## Why This Approach

This is the best tradeoff between correctness and simplicity:

- it fixes the actual cause rather than documenting the symptom
- it is much simpler than hiding and later restoring Settings
- it is less surprising than closing Settings on every shortcut
- it reuses existing close behavior that already returns the app toward menu-bar-only mode

## Alternatives Considered

### 1. Keep the warning-only approach

Pros:

- simplest code
- fully transparent about macOS behavior

Cons:

- does not actually stop the jump-back
- still leaves the user in a broken-feeling interaction

### 2. Close Settings on every app-switch shortcut

Pros:

- easy to reason about
- guaranteed to avoid the off-Space Settings problem

Cons:

- too surprising when the user is actively working in Settings
- broader behavior change than the bug requires

### 3. Reintroduce hidden/off-space Settings restore logic

Pros:

- can preserve Settings while smoothing the HUD flow

Cons:

- this was the fragile path that already caused regressions
- brings back lifecycle complexity around hidden-but-not-closed windows

## Behavior

### When Settings is closed

No behavior changes.

### When Settings is open on the current Space

No behavior changes.

The shortcut can still show the HUD normally while Settings remains open.

### When Settings is open on another Space

If the shortcut will show the HUD:

- close the Settings window first
- then show the HUD using the existing normal path

If the shortcut does not show the HUD:

- do not add any new Settings-specific behavior

## User Experience Notes

Closing Settings is acceptable here because:

- the user has already chosen to leave Settings and trigger an app-switch shortcut
- the current behavior is actively disruptive
- reopening Settings remains straightforward through the menu bar or Settings shortcut

The app should not add banners, alerts, or HUD copy for this case once the auto-close behavior is in place.

## Components

- `HUDManager`
  - gains the narrow pre-HUD off-Space Settings close step
- `SettingsWindowPresentationState`
  - should expose only the small amount of window-state detection needed for this decision
- `ShortcutCycleApp` / existing Settings close handling
  - remains the source of truth for what happens when Settings closes

## Error Handling and Edge Cases

- If no Settings window exists, do nothing
- If Settings exists but is not visible, do nothing
- If Settings is visible on the active Space, do nothing
- If multiple windows exist, only windows identified as Settings participate in this behavior
- If closing Settings fails for any reason, continue with the normal HUD flow rather than blocking switching

## Testing

Add or update tests for:

- detecting a visible off-Space Settings window
- closing off-Space Settings before HUD presentation
- not closing Settings when it is on the active Space
- not closing Settings when HUD is disabled / not shown
- preserving the normal HUD activation path after the close

## Implementation Notes

- Prefer `close()` over `orderOut`, hidden-window state, or restore bookkeeping
- Keep the special case as small as possible and limited to the pre-HUD boundary
- Remove the new warning-only direction if it is no longer part of the product behavior
