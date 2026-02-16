# CLAUDE.md — ShortcutCycle

## Project Overview

ShortcutCycle is a native macOS menu bar application built with Swift and SwiftUI. It lets users organize apps into groups and cycle between them using global keyboard shortcuts. A HUD overlay shows the current and next app during cycling.

**Key capabilities:** app group management, global keyboard shortcuts, HUD overlay, multi-profile app support (e.g., Chrome profiles), import/export settings as JSON, automatic GFS backup, 15-language localization, launch at login.

- **Language:** Swift 5.9+
- **Framework:** SwiftUI + AppKit
- **Minimum macOS:** 14.0
- **Build system:** Swift Package Manager + Xcode
- **External dependency:** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (v2.0.0+)

## Repository Layout

```
ShortcutCycle/
├── ShortcutCycle/                      # Xcode project root
│   ├── ShortcutCycle.xcodeproj/        # Xcode project config
│   ├── Package.swift                   # SPM manifest
│   ├── ShortcutCycle/                  # Main source code
│   │   ├── ShortcutCycleApp.swift      # App entry point, menu bar setup
│   │   ├── Models/                     # Data models (SPM target: ShortcutCycleCore)
│   │   │   ├── AppGroup.swift          # Group model with apps and shortcut refs
│   │   │   ├── AppItem.swift           # Individual app (bundle ID, name, icon)
│   │   │   ├── GroupStore.swift        # Observable persistence layer (UserDefaults)
│   │   │   ├── HUDAppItem.swift        # HUD-specific item with composite IDs
│   │   │   ├── SettingsExport.swift    # JSON import/export (v3 format)
│   │   │   ├── BackupRetention.swift   # GFS backup thinning policy
│   │   │   ├── BackupDiff.swift        # Backup comparison utility
│   │   │   └── KeyboardShortcutsNames.swift
│   │   ├── Services/                   # Business logic
│   │   │   ├── AppSwitcher.swift       # Core cycling and activation logic
│   │   │   ├── ShortcutManager.swift   # Global shortcut registration
│   │   │   ├── LaunchAtLoginManager.swift
│   │   │   ├── AppSwitcher/
│   │   │   │   └── IconCache.swift
│   │   │   ├── HUD/
│   │   │   │   ├── HUDManager.swift    # HUD visibility and interaction
│   │   │   │   └── AppSwitcherHUDView.swift
│   │   │   ├── Managers/
│   │   │   │   └── LanguageManager.swift
│   │   │   └── Overlay/
│   │   │       └── LaunchOverlayManager.swift
│   │   ├── Views/                      # SwiftUI views
│   │   │   ├── MainView.swift          # Settings window tab view
│   │   │   ├── MenuBarView.swift       # Menu bar popover
│   │   │   ├── GroupListView.swift     # Sidebar group list
│   │   │   ├── GroupEditView.swift     # Group name and app editor
│   │   │   ├── AppDropZoneView.swift   # Drag-and-drop for adding apps
│   │   │   └── Settings/
│   │   │       ├── GeneralSettingsView.swift
│   │   │       ├── GroupSettingsView.swift
│   │   │       ├── HUDPreviewView.swift
│   │   │       └── BackupBrowserView.swift
│   │   ├── Extensions/
│   │   │   └── String+Localization.swift
│   │   └── Resources/                  # 15 language .lproj directories
│   └── ShortcutCycleTests/            # XCTest test suites
│       ├── AppCyclingLogicTests.swift
│       ├── AppGroupTests.swift
│       ├── AppItemTests.swift
│       ├── BackupBrowserTests.swift
│       ├── BackupDiffTests.swift
│       ├── BackupRetentionTests.swift
│       ├── GroupStoreTests.swift
│       ├── LocalizationTests.swift
│       ├── SettingsExportTests.swift
│       └── ShortcutCycleTests.swift
├── .github/workflows/
│   ├── test.yml                        # CI: swift test on push/PR to master
│   └── static.yml                      # GitHub Pages deployment
├── ci_scripts/
│   └── ci_post_clone.sh               # Xcode Cloud build number setup
├── scripts/
│   └── optimize_images.py
└── docs/                               # Documentation and assets
```

## Build and Test Commands

```bash
# Run tests (primary way to validate changes)
cd ShortcutCycle && swift test

# Build only (no tests)
cd ShortcutCycle && swift build

# Resolve dependencies
cd ShortcutCycle && swift package resolve
```

All SPM commands must be run from the `ShortcutCycle/` subdirectory (where `Package.swift` lives), not the repository root.

## CI

GitHub Actions runs on every push to `master` and on all pull requests targeting `master`:
- **Runner:** `macos-latest`
- **Command:** `swift test --enable-code-coverage` in the `ShortcutCycle/` directory
- **Coverage report:** Filtered to `ShortcutCycleCore` source files only (excludes third-party dependencies, test files, and SPM boilerplate). Posted to the GitHub Actions job summary with per-file and total line coverage.
- **Coverage goal:** Maintain 100% line coverage on all `ShortcutCycleCore` source files. When adding new code to `Models/`, add corresponding tests to keep coverage at 100%.

Xcode Cloud uses `ci_scripts/ci_post_clone.sh` to set build numbers (`CI_BUILD_NUMBER + 100`).

## Architecture

### SPM Target Structure

| Target | Type | Purpose |
|--------|------|---------|
| `ShortcutCycleCore` | Library | Pure models and business logic (testable without UI) |
| `ShortcutCycle` | Executable | Main app (depends on Core) |
| `ShortcutCycleTests` | Test | Tests against ShortcutCycleCore |

The Core module is imported via `#if canImport(ShortcutCycleCore)` for compatibility between SPM and Xcode builds.

### Design Patterns

- **MVVM with reactive state:** `GroupStore` is the main `@Observable`/`@Published` store. Views bind with `@StateObject` and `@AppStorage`.
- **Singletons for services:** `ShortcutManager.shared`, `AppSwitcher` instances are created at app scope.
- **`@MainActor` for thread safety:** All UI-touching classes are `@MainActor`-annotated.
- **Notification-based communication:** `Notification.Name.shortcutsNeedUpdate`, `.deleteGroupRequested`, etc.
- **Isolated test state:** Each test suite uses a dedicated `UserDefaults(suiteName:)` to avoid test pollution.

### Key Algorithms

- **App cycling:** Deterministic algorithm in `AppCyclingLogic` — priority order: HUD selection > frontmost app > last active > first in group. Handles wrap-around.
- **MRU ordering:** `AppCyclingLogic.sortedByMRU` reorders HUD items by most recently used. Tracks composite IDs (`"bundleId-pid"`) so each instance has its own MRU rank; backward-compatible with old plain bundle ID entries via 3-tier matching (exact composite → plain bundle ID → bundle prefix fallback). Updates only on finalization (modifier release / click), not during intermediate cycling. Persisted in `AppGroup.mruOrder`, managed by `GroupStore.updateMRUOrder`.
- **Multi-instance apps:** Composite ID format `"{bundleId}-{pid}"` to distinguish browser profiles and multiple windows.
- **GFS backup retention:** Keep all < 1h, 1/hour for 1-24h, 1/day for 1-30d, 1/week for 30d+, cap at 100 backups.
- **Debounced auto-backup:** 60s timer, duplicate detection via content comparison, flushes on app termination.

## Code Conventions

- **Indentation:** 4 spaces
- **Code sections:** Organized with `// MARK: - Section Name` comments
- **Naming:** camelCase for variables/functions, PascalCase for types
- **Access control:** `public` for Core module types, `private` for internal implementation details
- **File organization:** Models → Services → Views, one primary type per file
- **Type safety:** Explicit type annotations, `Codable`/`Equatable` conformances, `UUID` identifiers
- **Error handling:** Result types and dedicated error enums (e.g., `SettingsExportError`), guard/optional chaining
- **No linter configured:** No SwiftLint or SwiftFormat — follow existing code style

## Localization

15 supported languages with `.lproj/Localizable.strings` files under `Resources/`:
en, de, fr, es, it, pt-BR, ja, ko, zh-Hans, zh-Hant, ar, nl, pl, tr, ru

Use `String+Localization.swift` extension for manual language selection. The app supports both system locale detection (via `CFPreferences`) and user-selected language override.

When adding new user-facing strings, add the key to all 15 `Localizable.strings` files.

## macOS App Specifics

- **Menu bar app:** Uses `MenuBarExtra` (no dock icon, `.accessory` activation policy)
- **HUD overlay:** Custom `NSPanel` at floating window level with 200ms hold-delay
- **App switching:** Uses `NSRunningApplication` and `NSWorkspace` APIs
- **Keyboard events:** Carbon event codes for key monitoring
- **Entitlements:** See `ShortcutCycle.entitlements`

## Tips for AI Assistants

- Always run `swift test` from the `ShortcutCycle/` directory after making changes to verify nothing breaks.
- Model files in `Models/` are shared between the `ShortcutCycleCore` and `ShortcutCycle` targets — they are listed explicitly in `Package.swift` sources/excludes. If you add a new model file, update both the `sources` array in the Core target and the `exclude` array in the executable target.
- The test target depends only on `ShortcutCycleCore`, not the full app. New testable logic should go in Core.
- HUD and AppSwitcher code uses `@MainActor` — maintain this when adding or modifying service classes.
- The default branch is `master`, not `main`.
