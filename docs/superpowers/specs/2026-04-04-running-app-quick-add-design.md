# Running App Quick Add For Group Editor

## Summary

Add an inline quick-add surface to the group editor that lets users add currently running apps with one click. The goal is to reduce setup friction when the user already has the right apps open, while keeping the existing Finder drag/drop and file-browse flow as the fallback.

## Current Context

The current app-add flow in the group editor depends on `AppDropZoneView`, which supports dragging `.app` bundles from Finder or clicking to browse for applications. That works, but it adds unnecessary friction when the user wants to group apps that are already running.

Issue `#37` asks for a faster app-picking flow, with the strongest direction being a quick-add surface for currently running apps.

## Goals

- Make creating a new group faster when the desired apps are already open
- Keep the flow local to the existing group editor
- Support one-click add with no extra modal step
- Preserve the existing browse and drag/drop path as a secondary option
- Keep the candidate list predictable and easy to scan

## Non-Goals

- No onboarding wizard, full-screen setup flow, or separate modal picker
- No search field or recent-app history in V1
- No Dock drag support in V1
- No smart classification or automatic grouping suggestions
- No changes to group persistence or dedupe rules

## Recommended Approach

Show a compact quick-add section directly in `GroupEditView`, above the existing drop zone.

Render the running-app candidates as an inline chip or adaptive grid treatment with app icon and app name. Clicking a candidate should immediately add it to the current group.

The existing `AppDropZoneView` remains visible below this section so that browsing and Finder drag/drop stay available for apps that are not currently running.

### Behavior

- Only show the quick-add section when there is at least one eligible running app candidate
- Render each candidate once, even if multiple instances of the app are running
- Clicking a candidate immediately adds it to the current group
- After add, that candidate disappears from the quick-add list immediately
- Keep the existing drop zone visible below the quick-add section
- If no eligible running apps exist, show only the existing drop zone flow

## Candidate Generation

Use the currently running applications list from macOS as the source of truth.

### Selection Rules

- Include only running apps with activation policy `.regular`
- Exclude `ShortcutCycle` itself
- Exclude apps already present in the current group
- Keep Finder eligible if it otherwise qualifies
- Dedupe candidates by `bundleIdentifier`
- Only show candidates that can be resolved into a valid `AppItem`
- Sort candidates alphabetically by app name for predictability

### Resolution Notes

- Exclusion of `ShortcutCycle` should be based on bundle identifier, not display name
- If a running app cannot be reliably resolved into an `AppItem`, omit it from the quick-add list in V1
- Candidate sorting should be case-insensitive and diacritic-insensitive so the list feels stable and natural

## Interaction Notes

- The quick-add UI should feel lightweight and immediate, not like a second picker
- Chips should have a large enough hit target that the user can add several apps quickly
- The quick-add section should feel like the primary fast path when present
- The drop zone should remain visually secondary but clearly available for apps that are not running

## Data And Logic Placement

- UI rendering belongs in `GroupEditView`
- Running-app candidate generation should be implemented as a small, testable helper rather than embedded directly in the view body
- The helper should take current group membership into account and return resolved `AppItem` candidates ready for the existing add flow
- The final add action should continue to use the same `store.addApp(...)` path used by the drop zone
- Existing group-level dedupe by `bundleIdentifier` remains the source of truth

## Edge Cases

- `ShortcutCycle` is running and should never appear as a candidate
- Finder may appear and should remain eligible
- Apps already in the current group should never appear in the quick-add list
- Multi-instance apps, such as browsers with multiple profiles, should appear only once
- If a candidate disappears from the running-app list while the editor is visible, the UI can simply refresh to the next valid state
- If every running app is already in the group or otherwise excluded, the quick-add section should stay hidden

## Validation

The implementation should verify:

- the quick-add section appears only when eligible candidates exist
- `ShortcutCycle` is excluded
- Finder can appear when eligible
- apps already in the group are excluded
- multiple running instances of the same app produce one candidate
- candidates are sorted alphabetically by name
- clicking a candidate adds it through the existing app-add path
- the added app disappears from quick add immediately
- the existing drag/drop and browse flow still works unchanged

## Open Decisions Resolved

- Use an inline chip or grid treatment rather than a modal sheet
- Exclude `ShortcutCycle` itself
- Exclude apps already in the current group
- Keep Finder eligible
- Sort candidates alphabetically for predictability
- Keep the existing browse and drag/drop flow as the fallback path
