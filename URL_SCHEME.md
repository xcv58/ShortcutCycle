# ShortcutCycle URL Scheme Reference

This document is the complete reference for automation via the `shortcutcycle://` URL scheme.

## Scheme

- Base scheme: `shortcutcycle://`
- macOS shell usage:

```bash
open "shortcutcycle://<command>?<query>"
```

## Quick Start

```bash
open "shortcutcycle://open-settings"
open "shortcutcycle://cycle?group=Browsers"
open "shortcutcycle://set-setting?key=showHUD&value=true"
open "shortcutcycle://backup"
open "shortcutcycle://create-group?name=Editors"
open "shortcutcycle://add-app?group=Editors&bundleId=com.microsoft.VSCode"
open "shortcutcycle://list-groups"
```

## Commands

### Settings and navigation

- `open-settings` (alias: `settings`)
  - Optional: `tab=groups|general`
  - Tab aliases: `group` (alias for `groups`), `app` or `application` (alias for `general`)
  - Special backup browser trigger:
    - `tab=backup|backups|backup-browser|automatic-backups`
    - `section=...`, `panel=...`, `view=...` (same values as above)
- `open-backup-browser` (aliases: `backup-browser`, `automatic-backups`)

Examples:

```bash
open "shortcutcycle://open-settings"
open "shortcutcycle://open-settings?tab=groups"
open "shortcutcycle://open-settings?tab=general"
open "shortcutcycle://open-backup-browser"
open "shortcutcycle://open-settings?tab=backup"
```

### Group actions

- `cycle`
  - Optional group selector (if omitted, app uses selected enabled group, then first enabled group)
- `select-group` (group selector required)
- `enable-group` (group selector required)
- `disable-group` (group selector required)
- `toggle-group` (group selector required)

Examples:

```bash
open "shortcutcycle://cycle?group=Browsers"
open "shortcutcycle://cycle?groupId=9B8E6AA2-3C63-4B63-BF8F-2D95B6E45D59"
open "shortcutcycle://select-group?index=1"
open "shortcutcycle://enable-group?group=Browsers"
open "shortcutcycle://disable-group?group=Browsers"
open "shortcutcycle://toggle-group?group=Browsers"
```

### Group CRUD

- `create-group`
  - Required: `name=<string>`
  - Creates a new group with the given name.
- `delete-group` (group selector required)
  - Shows a confirmation dialog before deleting.
- `rename-group` (group selector required)
  - Required: `newName=<string>` (alias: `to`)
- `reorder-group` (group selector required)
  - Required: `position=<1-based-index>` (alias: `to`)
  - Out-of-range values are clamped to first or last position.

Examples:

```bash
open "shortcutcycle://create-group?name=Editors"
open "shortcutcycle://delete-group?group=Editors"
open "shortcutcycle://rename-group?group=Browsers&to=Web"
open "shortcutcycle://rename-group?group=Browsers&newName=Web"
open "shortcutcycle://reorder-group?group=Web&position=1"
open "shortcutcycle://reorder-group?group=Web&to=2"
```

### App management

- `add-app` (group selector required)
  - Required: `bundleId=<bundle-identifier>` (aliases: `app`, `bundle`)
  - Adds the app to the group. Skips if already present.
  - The app must be installed on the system.
- `remove-app` (group selector required)
  - Required: `bundleId=<bundle-identifier>` (aliases: `app`, `bundle`)
  - Removes the app from the group.

Examples:

```bash
open "shortcutcycle://add-app?group=Browsers&bundleId=com.google.Chrome"
open "shortcutcycle://add-app?group=Browsers&app=com.apple.Safari"
open "shortcutcycle://remove-app?group=Browsers&bundleId=com.google.Chrome"
open "shortcutcycle://remove-app?group=Browsers&bundle=com.apple.Safari"
```

### Query commands

Query commands write JSON results to a file. Default output: `/tmp/shortcutcycle-result.json`.

- `list-groups`
  - Optional: `output=<path>` (default: `/tmp/shortcutcycle-result.json`)
  - Returns all groups with id, name, isEnabled, appCount, and 1-based index.
- `get-group` (group selector required)
  - Optional: `output=<path>` (default: `/tmp/shortcutcycle-result.json`)
  - Returns full group details including apps (bundleId and name).

Output format:

```json
{
  "command": "list-groups",
  "success": true,
  "data": [
    {"id": "UUID", "name": "Browsers", "isEnabled": true, "appCount": 3, "index": 1}
  ]
}
```

Examples:

```bash
open "shortcutcycle://list-groups"
sleep 0.5 && cat /tmp/shortcutcycle-result.json

open "shortcutcycle://list-groups?output=/tmp/groups.json"
sleep 0.5 && cat /tmp/groups.json

open "shortcutcycle://get-group?group=Browsers"
sleep 0.5 && cat /tmp/shortcutcycle-result.json

open "shortcutcycle://get-group?group=Browsers&output=/tmp/detail.json"
sleep 0.5 && cat /tmp/detail.json
```

### Backup actions

- `backup`
  - Triggers manual backup now.
- `flush-auto-save`
  - Aliases: `flush-auto-backup`, `trigger-auto-save`, `trigger-auto-backup`, `autosave`
  - Flushes pending debounced auto-save immediately.
- `restore-backup` (alias: `restore`)
  - Selectors (all optional):
    - `path=<absolute-path-or-file-url>`
    - `file=<absolute-path-or-file-url>` (alias for `path`)
    - `name=<backup-filename>`
    - `index=<1-based-index>` (newest first)
    - `backupindex=<1-based-index>` (alias for `index`)
  - If no selector is provided, the latest backup is restored.
  - Selector precedence: `path/file` > `name` > `index/backupindex` > latest.

Examples:

```bash
open "shortcutcycle://backup"
open "shortcutcycle://flush-auto-save"
open "shortcutcycle://restore-backup"
open "shortcutcycle://restore-backup?index=2"
open "shortcutcycle://restore-backup?name=backup%202026-03-01%2000-00-00.json"
open "shortcutcycle://restore-backup?path=/tmp/backup.json"
open "shortcutcycle://restore-backup?file=/tmp/backup.json"
```

### Settings actions

- `set-setting`
  - Required key: `key=<setting-key>` (alias: `name=<setting-key>`)
  - Required value: `value=<setting-value>` (alias: `v=<setting-value>`)

All keys and values are case-insensitive.

Supported keys (with aliases):

- `showHUD` (alias: `hud`)
- `showShortcutInHUD` (aliases: `hudShortcut`, `showShortcut`)
- `appTheme` (aliases: `theme`, `appearance`)
- `selectedLanguage` (alias: `language`)
- `openAtLogin` (alias: `launchAtLogin`)

Supported values:

- Boolean keys accept: `1|true|yes|on|enabled` and `0|false|no|off|disabled`
- `appTheme`: `system|light|dark` (`default` is an alias for `system`)
- `selectedLanguage`: `system` or one of:
  - `en`, `de`, `fr`, `es`, `ja`, `pt-BR`, `zh-Hans`, `zh-Hant`, `it`, `ko`, `ar`, `nl`, `pl`, `tr`, `ru`

Examples:

```bash
open "shortcutcycle://set-setting?key=showHUD&value=true"
open "shortcutcycle://set-setting?key=showShortcutInHUD&value=false"
open "shortcutcycle://set-setting?key=appTheme&value=dark"
open "shortcutcycle://set-setting?key=selectedLanguage&value=ja"
open "shortcutcycle://set-setting?key=openAtLogin&value=true"
```

### Import and export settings

- `export-settings` (alias: `export`)
  - Required: `path=<absolute-path-or-file-url>` or `file=<...>`
- `import-settings` (alias: `import`)
  - Required: `path=<absolute-path-or-file-url>` or `file=<...>`

Examples:

```bash
open "shortcutcycle://export-settings?path=/tmp/ShortcutCycle-Settings.json"
open "shortcutcycle://import-settings?path=/tmp/ShortcutCycle-Settings.json"
open "shortcutcycle://export-settings?file=/tmp/ShortcutCycle-Settings.json"
open "shortcutcycle://import-settings?file=/tmp/ShortcutCycle-Settings.json"
```

## Group selector parameters

Commands that target groups can use:

- `group=<name>` (alias: `name=<name>`, case-insensitive)
- `groupId=<uuid>` (alias: `id=<uuid>`)
- `index=<1-based-index>` (alias: `groupindex=<1-based-index>`)

## x-callback style action path

The parser also supports this action format:

```bash
open "shortcutcycle://x-callback-url/cycle?group=Browsers"
open "shortcutcycle://x-callback-url/enable-group?index=2"
```

## Important notes

- `import-settings` and `restore-backup` replace current groups/settings immediately.
- `delete-group`, `import-settings`, and `restore-backup` show a confirmation dialog before proceeding.
- Use absolute paths or `file://` URLs for file-based commands.
- Relative paths may resolve from the app process working directory, which is not stable.
- URL-encode special characters and spaces (for example, use `%20`).
- Query commands (`list-groups`, `get-group`) write results asynchronously. Use `sleep 0.5` before reading the output file in scripts.
