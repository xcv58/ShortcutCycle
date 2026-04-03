# Cross-Space Settings Close On HUD Finalize

## Summary

When the HUD is enabled and the Settings window is open, ShortcutCycle should close the Settings window only in the cross-Space cases that can cause macOS to snap back to the Settings Space.

This keeps normal HUD interaction intact while avoiding the visible regular-window state that pulls focus back after a cross-Space switch.

## Goals

- Preserve the current HUD interaction when Settings is open on the current Space.
- Prevent macOS from jumping back to the Settings Space after a HUD-driven switch to another Space.
- Keep the behavior narrow and predictable.
- Avoid reintroducing hidden-window restore state or warning-only UX.

## Non-Goals

- Changing behavior when `Show HUD when switching` is disabled.
- Closing Settings for same-Space switches.
- Reintroducing delayed restore or special reopen handling for Settings.
- Solving unrelated Space movement outside the Settings-window/HUD interaction.

## Behavior

### HUD Enabled

If `Show HUD when switching` is enabled:

- If Settings is already open on another Space when the shortcut begins, close Settings immediately before HUD activation.
- If Settings is open on the current Space when the shortcut begins, leave it open while the HUD is shown.
- When the user finalizes the HUD selection, if the chosen target app will switch to another Space, close Settings immediately before activating the target app.
- When the user finalizes the HUD selection and the chosen target app stays on the current Space, leave Settings open.

### HUD Disabled

If `Show HUD when switching` is disabled:

- Do not auto-close Settings.
- Keep the existing direct-switch behavior unchanged.

## Design

### Cross-Space Detection

Reuse the existing Settings-window detection helper for the pre-HUD case:

- Detect a visible Settings window whose `isOnActiveSpace` is `false`.
- Close it before calling the normal HUD activation path.

Add a separate finalization-time decision for the current-Space case:

- Resolve the pending HUD target from the current HUD selection.
- Determine whether activating that target will move macOS to another Space.
- If yes, close any visible Settings window before activating the target app.

This makes the trigger depend on the actual cross-Space handoff, not simply on whether Settings is visible.

### HUD Lifecycle

The HUD flow should remain unchanged until finalization:

- Initial key-down and hold-to-show behavior stays the same.
- Settings remains visible during the HUD if it is on the current Space.
- The close happens only at the point where the selected target is about to be activated for a cross-Space switch.

This preserves the current interactive feel while removing the regular Settings window before the Space transition.

### Settings Lifecycle

Closing Settings should use the app's normal close behavior:

- No `orderOut`-and-restore flow.
- No temporary hidden Settings state.
- No Dock/menu-bar reopen special case beyond the existing normal behavior.

The app should simply treat the window as closed.

## Implementation Notes

- Extend `HUDManager` with a narrow helper for "close visible Settings before cross-Space target activation".
- Keep the existing pre-HUD off-Space close path for the case where Settings starts on another Space.
- Add a small abstraction seam if needed so tests can inject target-space detection without depending on live macOS Spaces behavior.
- Leave non-HUD switching paths untouched.

## Testing

Add or update tests to cover:

- Off-Space Settings is closed before HUD activation.
- Current-Space Settings is not closed when showing the HUD.
- Current-Space Settings is closed during HUD finalization when the selected target is cross-Space.
- Current-Space Settings is not closed during HUD finalization when the selected target stays on the current Space.
- HUD-disabled switching does not auto-close Settings.

Manual smoke check:

- Settings open on current Space, target app on another Space, HUD enabled: HUD appears, release closes Settings, then macOS switches once without snapping back.
- Settings open on another Space, trigger shortcut from current Space, HUD enabled: Settings closes before HUD activation, then switching behaves normally.
- Same-Space HUD switching with Settings open keeps Settings open.
- HUD disabled leaves Settings behavior unchanged.
