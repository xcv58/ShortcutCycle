# Test Coverage Analysis — ShortcutCycle

## Current State

~80 tests across 8 test files, targeting `ShortcutCycleCore`.

### Coverage by Module

| Module | Tests | Status |
|--------|-------|--------|
| AppCyclingLogic | 44 | Well covered |
| BackupRetention | 14 | Well covered |
| SettingsExport | 15 | Good, some edge cases missing |
| GroupStore | 7 | Basic CRUD only |
| AppGroup | 6 | Basics only |
| Localization | 3 | Completeness checks |
| BackupBrowser | 1 | Minimal |
| BackupDiff | 0 | **Untested** |
| AppItem | 0 | **Untested** |
| ShortcutCycleTests | 1 | Empty placeholder |

## Recommended Improvements

### 1. BackupDiff — Zero Tests (High Priority)

`BackupDiff.compute(before:after:)` is a pure function in `ShortcutCycleCore` with no macOS dependencies.

Recommended test cases:
- Identical snapshots → `hasChanges == false`
- Added/removed/modified groups detected correctly
- App-level changes within groups (added, removed, unchanged)
- Each settings field changing independently
- Nil settings default handling
- Empty group lists on both sides

### 2. GroupStore — Expand Coverage (High Priority)

Only basic CRUD and backup tested. Missing:
- `moveGroups(from:to:)` — reordering
- `addApp` / `removeApp` / `moveApp` — app-level operations
- `updateLastActiveApp(bundleId:for:)` — last-active tracking
- `toggleGroupEnabled` — enable/disable
- Selection behavior on delete (selected vs. not selected; last group)
- `importData` / `exportData` round-trip through the store
- Error paths (malformed import data)

### 3. AppGroup — Edge Cases (Medium Priority)

Missing:
- `moveApp` boundary conditions (same index, out of bounds, single element)
- `lastModified` timestamp updates on mutations
- `openAppIfNeeded` nil-coalescing default
- Full Codable round-trip with all fields
- Same bundleIdentifier with different UUIDs (dedup behavior)

### 4. AppItem — Factory Method (Medium Priority)

`AppItem.from(appURL:)` is untested:
- Valid `.app` bundle → correct AppItem
- Invalid URL → nil
- Bundle without identifier → nil
- `.app` extension stripped from name

### 5. SettingsExport — Edge Cases (Medium Priority)

Missing:
- `AppSettings.current()` / `apply()` with isolated UserDefaults
- Future version handling (version 999)
- Settings with all nil optionals
- Shortcuts round-trip completeness

### 6. BackupRetention — Boundaries (Low Priority)

Missing:
- Exact tier boundaries (1h, 24h, 30d)
- `maxCount` of 1
- Same-timestamp files

### 7. Extract Service Logic to Core (Architectural)

Pure logic in services that could be extracted to `ShortcutCycleCore`:
- **HUDManager**: Grid navigation math (5-column wrapping), hold-to-show state machine
- **ShortcutManager**: Debounce logic, group ID tracking
- **AppSwitcher**: Toggle hide/show decision, running-app filtering

### 8. Placeholder Cleanup (Low Priority)

`ShortcutCycleTests.swift` is an empty placeholder using Swift Testing macros. Remove or implement.
