# Off-Space Settings HUD Design

Date: 2026-04-02
Status: Approved for planning

## Summary

ShortcutCycle should preserve the current HUD-first switching experience even when a Settings window exists on another macOS Space.

The specific bug to solve is:

- the user is working on the current Space
- a ShortcutCycle Settings window exists on a different, non-active Space
- the user triggers a shortcut
- macOS jumps to the Settings window's Space before the actual app switch completes

The chosen design is to add a narrow deferred-activation HUD path for this case only. When an off-space Settings window exists, ShortcutCycle should keep the HUD on the current Space while the shortcut is held, and only activate the selected app when the user releases the shortcut. That makes the Space switch happen at the end of the interaction instead of at the beginning.

## Goals

- Preserve the HUD-first interaction for the off-space Settings-window case
- Prevent an early jump to the Space that contains the Settings window
- Keep the fix narrowly scoped to the real bug condition
- Avoid destabilizing menu bar interactivity or Dock behavior again

## Non-Goals

- Changing HUD behavior when Settings is closed
- Changing HUD behavior when Settings is open on the current Space
- Reworking the entire Settings-window lifecycle
- Adding new warnings, banners, or onboarding copy
- Perfecting full keyboard interaction in the special off-space path

## Chosen Approach

Introduce a special HUD presentation path that is used only when a Settings window exists and is not on the active Space.

In that path:

- ShortcutCycle does not activate itself before showing the HUD
- ShortcutCycle does not hide, restore, reorder, or otherwise manipulate the Settings window
- the HUD is shown on the current Space and kept there while the shortcut is held
- selection continues to update through the existing hold-to-cycle / repeated-shortcut flow
- the selected app is activated only when the shortcut is released or the interaction finalizes

All other cases continue to use the existing HUD path unchanged.

## Why This Approach

The recent regressions all came from treating the Settings window as something the HUD flow needed to manage: hiding it, restoring it, or changing app activation state around it.

That makes the problem larger than it really is.

The real bug is narrower: activating ShortcutCycle while a normal Settings window exists on another Space causes macOS to jump there too early.

By deferring app activation in that one case, we solve the actual Space-jump problem without expanding the Settings lifecycle surface area any further.

## Alternatives Considered

### 1. Temporarily hide and later restore the Settings window

Pros:

- Keeps the existing HUD path mostly intact
- Can prevent the early Space jump when it works

Cons:

- Reintroduced menu bar and Dock interaction regressions
- Adds fragile hidden-window lifecycle state
- Couples HUD presentation to Settings window restoration

### 2. Skip the HUD entirely while Settings is open

Pros:

- Much simpler logic
- Very robust

Cons:

- Removes the HUD in cases where it should still work
- Feels like a product regression rather than a targeted bug fix

### 3. Always allow the current active HUD path and accept the early Space jump

Pros:

- No extra code path
- Preserves current full HUD input handling

Cons:

- Leaves the reported bug unfixed
- Produces a confusing, jumpy interaction

## Behavior

### Normal cases

No behavior changes:

- Settings closed: current HUD behavior remains
- Settings open on the current Space: current HUD behavior remains

### Special case

When a Settings window exists on another Space:

1. The user triggers a shortcut from the current Space
2. ShortcutCycle shows the HUD on the current Space without activating itself
3. The user continues holding the shortcut and cycles as usual
4. When the user releases, ShortcutCycle activates the chosen target app
5. macOS switches to the target app's Space only at that point

## Input Model and Tradeoffs

The deferred-activation path should preserve:

- repeated shortcut hits to move selection
- press-and-hold cycling behavior
- release-to-switch behavior

One tradeoff is acceptable in this special path:

- full in-app keyboard interaction may be reduced because ShortcutCycle stays inactive while the HUD is visible

In practice, arrow-key navigation may not be reliable in the special off-space path. This tradeoff is acceptable because:

- it affects only the narrow off-space Settings-window case
- the primary shortcut-driven switching interaction still works
- it avoids the more serious regression of Space jumps and menu bar instability

## State and Data Flow

The new decision point should be:

1. Detect whether a Settings window exists
2. If it exists, detect whether it is on the active Space
3. If there is no off-space Settings window, continue through the current HUD flow
4. If there is an off-space Settings window, use the deferred-activation HUD flow

The deferred path should track:

- current HUD items
- current selected item
- pending target app identifier
- modifier/key release finalization

It should not introduce hidden-window restoration state for Settings.

## Components

- `HUDManager` owns the branching between normal presentation and deferred activation
- a small helper or policy object should answer whether an off-space Settings window exists
- existing Settings-window presentation state used for hiding/restoring should be removed or reduced if it is no longer needed by any other flow

`AppSwitcher` should continue deciding what to switch to. `HUDManager` should decide how the HUD is presented for the already-selected target.

## Error Handling and Edge Cases

- If no Settings window exists, the special path must not run
- If the Settings window is visible on the current Space, the special path must not run
- If the target app is already on the current Space, the special path can still be used when the triggering condition is met, but it should not break final activation
- If the user releases before the HUD fully presents, the pending selection should still finalize correctly
- If the HUD is dismissed without a pending selection, no app activation should occur

## Testing

Add or update tests for:

- detecting the off-space Settings-window condition
- keeping the normal HUD path when Settings is closed
- keeping the normal HUD path when Settings is on the active Space
- using the deferred-activation path when Settings is off-space
- ensuring activation is deferred until finalization in that path
- ensuring the deferred path does not mark Settings as temporarily hidden
- ensuring existing menu bar interaction and Settings reopen behavior stay unaffected

## Implementation Notes

- Keep the new behavior narrowly scoped to the actual bug condition
- Prefer removing existing hidden-window management if it becomes unnecessary
- Do not add new user-facing warnings or notes as part of this fix
- Preserve existing HUD behavior everywhere else
