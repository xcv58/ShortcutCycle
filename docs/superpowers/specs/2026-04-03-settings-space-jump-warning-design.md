# Settings Space-Jump Warning Design

Date: 2026-04-03
Status: Approved for planning
Supersedes: `docs/superpowers/specs/2026-04-02-off-space-settings-hud-design.md`

## Summary

ShortcutCycle should stop trying to special-case the situation where a Settings window is open on another macOS Space.

Instead, the app should use one normal HUD/app-switching path in all cases and add a small inline note near the `Show HUD when switching` setting to explain that macOS may briefly jump Spaces when Settings is open elsewhere.

## Problem

The current off-space Settings handling has grown into fragile lifecycle logic:

- detecting whether Settings is on another Space
- changing HUD activation behavior
- preserving menu bar interactivity
- preserving hold-to-cycle behavior
- keeping Settings and Dock reopen behavior stable

That complexity is not paying for itself. Even when the app handles the case more carefully, the remaining UX is still subtle and fragile.

The simpler product truth is:

- if Settings is open on another Space
- and the user triggers HUD switching
- macOS may jump between Spaces during that interaction

That is acceptable as long as the app explains it clearly in Settings.

## Goals

- Remove the off-space Settings special-case behavior
- Return HUD/app switching to one normal code path
- Explain the Space-jump caveat in the Settings UI
- Keep the warning small, contextual, and easy to ignore

## Non-Goals

- Eliminating the macOS Space jump when Settings is open elsewhere
- Disabling the HUD while Settings is open
- Adding banners, alerts, or onboarding around this behavior
- Adding runtime detection or warnings only when the bug is about to happen

## Chosen Approach

When `Show HUD when switching` is enabled, General Settings should display a small inline note near that toggle.

The note explains that if the Settings window is open on another Space, macOS may briefly switch Spaces while the HUD is shown.

At the same time, ShortcutCycle should remove the special handling that was added for off-space Settings windows:

- no deferred HUD activation path
- no off-space Settings detection used by HUD presentation
- no Settings-window-specific switching behavior

The app returns to the standard HUD flow everywhere.

## Why This Approach

This is the best complexity-to-value tradeoff:

- users get an accurate explanation
- the app stops carrying brittle Space-specific behavior
- the menu bar and HUD logic become easier to reason about again

The previous design attempted to smooth over a macOS behavior that ShortcutCycle cannot control reliably. A small explanation is more honest and much safer than continued lifecycle workarounds.

## Alternatives Considered

### 1. Keep the off-space Settings special handling

Pros:

- attempts to reduce visible Space jumping

Cons:

- already caused regressions in menu bar behavior and HUD interaction
- increases lifecycle complexity around Settings and HUD presentation
- still does not produce a perfectly stable result

### 2. Disable the HUD whenever Settings is open

Pros:

- very robust
- easy to explain

Cons:

- bigger product behavior change than needed
- removes HUD in cases where it still works fine

### 3. Warning only, but only when Settings is currently open

Pros:

- slightly more contextual

Cons:

- requires runtime window-state coupling for a low-value detail
- the simpler always-available note next to the HUD toggle is easier to understand and maintain

## Behavior

### HUD behavior

ShortcutCycle uses the normal HUD behavior regardless of whether the Settings window is closed, on the current Space, or on another Space.

There is no special off-space Settings path.

### Settings UI behavior

When `Show HUD when switching` is enabled:

- show a small inline note directly beneath the HUD toggles in General Settings

When `Show HUD when switching` is disabled:

- do not show the note

## User-Facing Copy

Recommended copy:

`If Settings is open on another Space, macOS may briefly switch Spaces while showing the HUD.`

Copy goals:

- factual, not apologetic
- brief
- specific to the real condition
- no promise that the app will prevent the jump

## UI Placement

Place the note in `GeneralSettingsView` inside the existing `HUD Behavior` section.

Recommended layout:

- `Show HUD when switching`
- if enabled:
  - `Show shortcut in HUD`
  - existing shortcut explanation
  - new Space-jump note

The note should use secondary/caption styling so it reads like contextual help, not an alert.

## Components

- `GeneralSettingsView`
  - owns the conditional inline note near the HUD toggles
- `HUDManager`
  - should return to the standard presentation path only
- `SettingsWindowPresentationState`
  - should no longer participate in HUD presentation decisions

## Error Handling and Edge Cases

- If the user never opens Settings on another Space, nothing changes
- If `Show HUD when switching` is off, the note stays hidden
- If the user opens Settings on another Space and sees the jump, the app behavior matches the note rather than hidden special handling

## Testing

Add or update tests for:

- the note appearing only when `showHUD` is enabled
- the note being rendered in `GeneralSettingsView`
- removal of off-space/deferred HUD special-case tests
- standard HUD behavior still using the normal path

## Implementation Notes

- This change intentionally removes the off-space Settings handling added on the current branch
- Prefer deleting special-case logic rather than leaving dormant helpers behind
- Add the minimum new localized copy needed for the inline note
