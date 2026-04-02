# Shortcut Suggestions For Unassigned Groups

## Summary

Add lightweight shortcut suggestion chips to the group editor when a group does not yet have an assigned keyboard shortcut. The goal is to reduce first-run decision friction without introducing a separate onboarding flow.

## Current Context

The shortcut assignment flow already lives in `GroupEditView`. Users can record a shortcut there, but the UI does not currently suggest what kinds of shortcuts work well. Issue `#38` asks for simple guidance that helps users pick a shortcut pattern quickly.

## Goals

- Help first-time users choose a shortcut pattern faster
- Keep the guidance local to the existing group edit flow
- Make suggestions actionable instead of purely instructional
- Avoid conflicts with shortcuts already assigned to other groups

## Non-Goals

- No onboarding modal, wizard, or banner flow
- No complex recommendation engine based on group name or app contents
- No fallback to unusual shortcut combinations if common ones are unavailable

## Recommended Approach

Show a small row of click-to-apply suggestion chips directly under the existing keyboard shortcut recorder in `GroupEditView`.

### Behavior

- Only show the suggestion row when the current group has no assigned shortcut
- Render up to 3 suggestion chips
- Clicking a chip immediately assigns that shortcut to the current group
- Hide the suggestion row immediately after any shortcut is assigned, whether via chip or recorder
- Show one brief helper line under the chips explaining the pattern, for example that many people use one modifier plus numbers for each group

### Suggestion Generation

Use a deterministic ordered candidate list instead of a dynamic heuristic.

Primary candidate order:

- `Option + 1`
- `Option + 2`
- `Option + 3`
- ...
- `Option + 9`

Selection rules:

- Exclude any shortcut already assigned to a different group
- Take the first available candidates until 3 suggestions are collected
- If fewer than 3 are available, show fewer
- If none are available, show no suggestion chips

This keeps the UI predictable, easy to explain, and aligned with the product's existing examples.

## Interaction Notes

- Suggestion chips should feel secondary to the recorder, not like the main control
- The UI should not display suggestions that cannot be applied successfully
- Immediate assignment is preferred over inserting a hint into the recorder, because the feature is meant to reduce friction rather than add another step

## Data And Logic Placement

- UI rendering belongs in `GroupEditView`
- Suggestion generation should be implemented as a small, testable unit rather than embedded inline in the view body
- Conflict detection should reuse the same underlying shortcut source of truth already used by the recorder and shortcut manager

## Edge Cases

- Groups with an existing shortcut never show the suggestion row
- If the user clears a shortcut, the suggestion row can reappear
- If all preferred suggestions are unavailable, the recorder remains the only path
- If the current group somehow already holds one of the preferred shortcuts, the row stays hidden because the group is no longer unassigned

## Validation

The implementation should verify:

- suggestion chips appear only for groups without shortcuts
- only unused suggestions are shown
- clicking a suggestion assigns the shortcut and refreshes shortcut registration
- the suggestion row disappears after assignment

## Open Decisions Resolved

- Use suggestion chips rather than passive text or a broader onboarding UI
- Chips are click-to-apply, not examples only
- Suggestions are deterministic from a short preferred list, not personalized
