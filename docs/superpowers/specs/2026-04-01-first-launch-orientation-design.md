# First-Launch Orientation Design

Date: 2026-04-01
Status: Approved for planning

## Summary

ShortcutCycle should keep its current one-time "open Settings on first manual launch" behavior, but replace the large Groups-tab welcome banner with a compact callout at the top of the Settings window.

The purpose of the callout is orientation, not onboarding. It should explain that:

- the app is now running in the macOS menu bar
- the current Settings window was opened intentionally on first launch
- the user can close the window and reopen it from the menu bar icon later

## Goals

- Make the first manual launch feel intentional rather than surprising
- Teach the menu-bar mental model clearly and quickly
- Reduce visual weight compared with the current banner
- Reuse the existing one-time welcome state and replay behavior

## Non-Goals

- Building a multi-step onboarding flow
- Spotlighting or animating the actual macOS menu bar icon
- Teaching advanced setup during first launch
- Reopening Settings on every future launch

## Chosen Approach

Render a slim, dismissible callout at the window level in Settings, above the main tab content.

The callout should:

- appear on first manual launch after Settings auto-opens
- also appear when the user chooses "Show welcome again"
- include the app icon, a short title, one sentence of explanatory copy, and a close button
- avoid embedded controls such as "Open at Login"
- avoid decorative menu bar mockups

Suggested copy direction:

> ShortcutCycle is now running in your menu bar. You can close this window and reopen it from the icon in the top-right.

## Why This Approach

This keeps the part that already works well: opening Settings once so the app does something visible on first launch.

It removes the part that feels too heavy: a large banner inside the Groups screen that competes with the real settings UI.

Placing the message at the window level better matches the actual question a first-time user has: "Why did this window open, and where did the app go after I close it?"

## Alternatives Considered

### 1. Subtle inline note inside the Groups content

Pros:

- Lowest visual weight
- Minimal layout disruption

Cons:

- Easy to miss
- Feels tied to one tab instead of the app as a whole

### 2. Stronger menu-bar handoff with explicit spotlight behavior

Pros:

- Teaches the destination most directly
- Could feel polished if done well

Cons:

- Higher implementation complexity
- More fragile on macOS
- Too much behavior for the current problem

## UI Structure

The Settings window should be structured as:

1. Optional first-launch callout
2. Existing tabbed Settings content

The callout should span the Settings window rather than live inside the Groups view. This makes the message feel like app-level context instead of part of one specific settings page.

## State and Data Flow

Keep the existing persistence model in `WelcomeCoordinator`:

- first manual launch sets the "seen" flag once
- a pending welcome request is queued
- replay creates a new transient request without resetting the "seen" flag

Adjust the view flow:

- `AppDelegate` continues to auto-open Settings only when `prepareAutomaticWelcomeIfNeeded()` returns a request
- `MainView` consumes the request, switches to the Groups tab, and shows the compact callout
- dismissing the callout clears only local presentation state
- closing the Settings window also ends that local presentation session

The request identifier no longer needs to flow into `GroupSettingsView`, because the welcome UI is no longer owned by the Groups screen.

## Components

- Add a new compact callout view dedicated to first-launch orientation
- Move welcome presentation ownership to `MainView`
- Remove welcome-specific rendering from `GroupSettingsView`
- Keep `WelcomeCoordinator` focused on persistence and request queuing

## Error Handling and Edge Cases

- If Settings is already open when a replay request arrives, switch to the Groups tab and show the callout in the existing window
- If the callout is dismissed, it should not reappear until a new replay request is made
- If Settings closes, the callout should not persist into unrelated future openings unless a new request is queued

## Testing

Add or update tests for:

- first manual launch still queues exactly one automatic presentation
- replay still creates a new transient presentation request
- consuming a request still switches to the Groups tab
- dismissing the callout affects only local UI state, not the persisted "seen" flag
- closing and reopening Settings without a new request does not show the callout again

## Implementation Notes

- Prefer a small, stable surface area: treat the callout as a thin presentation layer over the existing welcome coordinator
- Do not add setup controls to the callout; keep it focused on orientation
- Keep replay wording and behavior consistent between the menu bar and General settings entry points
