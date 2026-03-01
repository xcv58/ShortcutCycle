# URL Scheme: Group CRUD and Query Commands

Date: 2026-03-01

## Goal

Expand the `shortcutcycle://` URL scheme with group CRUD operations, app management, and query commands. This enables full automation scripting (shell scripts, Hammerspoon, Shortcuts.app) and complements the existing import/export for new-Mac setup.

## Approach

- **Mutations** are fire-and-forget (no response), consistent with existing commands.
- **Queries** write JSON to a file (default `/tmp/shortcutcycle-result.json`, overridable with `output=<path>`).
- Destructive mutations (`delete-group`) show a confirmation dialog, consistent with `import-settings` and `restore-backup`.

## New Commands

### Group CRUD

| Command | Parameters | Behavior |
|---------|-----------|----------|
| `create-group` | `name=<string>` | Creates a new group. Fails silently if name is empty. |
| `delete-group` | group selector | Deletes the group. Shows confirmation dialog. |
| `rename-group` | group selector + `newName=<string>` (alias: `to`) | Renames the matched group. |
| `reorder-group` | group selector + `position=<1-based-index>` (alias: `to`) | Moves group to the given position. Clamps to valid range. |

### App Management

| Command | Parameters | Behavior |
|---------|-----------|----------|
| `add-app` | group selector + `bundleId=<id>` (alias: `app`, `bundle`) | Adds the app to the group. Skips if already present. |
| `remove-app` | group selector + `bundleId=<id>` (alias: `app`, `bundle`) | Removes the app from the group. |

### Query Commands

| Command | Parameters | Output |
|---------|-----------|--------|
| `list-groups` | `output=<path>` (optional) | JSON array of groups with id, name, isEnabled, app count |
| `get-group` | group selector + `output=<path>` (optional) | JSON object with full group details including apps |

## Group Selector (existing)

All group-targeting commands reuse the existing selector parameters:
- `group=<name>` (alias: `name=<name>`, case-insensitive)
- `groupId=<uuid>` (alias: `id=<uuid>`)
- `index=<1-based-index>` (alias: `groupindex=<1-based-index>`)

## Query Output Format

Default output path: `/tmp/shortcutcycle-result.json`

### list-groups

```json
{
  "command": "list-groups",
  "success": true,
  "data": [
    {"id": "UUID", "name": "Browsers", "isEnabled": true, "appCount": 3, "index": 1},
    {"id": "UUID", "name": "Editors", "isEnabled": false, "appCount": 2, "index": 2}
  ]
}
```

### get-group

```json
{
  "command": "get-group",
  "success": true,
  "data": {
    "id": "UUID",
    "name": "Browsers",
    "isEnabled": true,
    "apps": [
      {"bundleId": "com.google.Chrome", "name": "Google Chrome"},
      {"bundleId": "com.apple.Safari", "name": "Safari"}
    ]
  }
}
```

## Design Decisions

- **`delete-group` requires confirmation** -- destructive actions should not be silent, consistent with existing `import-settings` and `restore-backup`.
- **`add-app` uses bundleId** -- bundle IDs are stable and unambiguous. Display name is resolved from the system.
- **`rename-group` and `reorder-group` use `to=` alias** -- `rename-group?group=Browsers&to=Web` reads naturally.
- **Query default path `/tmp/shortcutcycle-result.json`** -- no path required for quick scripting; override with `output=` for parallel scripts.
- **No `update-group` mega-command** -- individual `rename`, `reorder`, `enable`, `disable` are more composable.
- **`reorder-group` clamps position** -- out-of-range values move to first or last instead of failing.

## Example Usage

```bash
# Create a group and populate it
open "shortcutcycle://create-group?name=Editors"
sleep 1
open "shortcutcycle://add-app?group=Editors&bundleId=com.microsoft.VSCode"
open "shortcutcycle://add-app?group=Editors&bundleId=com.jetbrains.intellij"

# Rename and reorder
open "shortcutcycle://rename-group?group=Editors&to=Code Editors"
open "shortcutcycle://reorder-group?group=Code%20Editors&position=1"

# Query state
open "shortcutcycle://list-groups?output=/tmp/groups.json"
sleep 0.5
cat /tmp/groups.json | jq '.data[].name'

# Get details of a specific group
open "shortcutcycle://get-group?group=Browsers"
sleep 0.5
cat /tmp/shortcutcycle-result.json | jq '.data.apps[].name'
```

## Scope

**In scope:** The 8 new commands listed above.

**Out of scope (for now):**
- x-callback-url response parameters
- Shortcuts.app Intents (App Intents framework)
- Batch/chained commands in a single URL
- Shortcut key assignment via URL
