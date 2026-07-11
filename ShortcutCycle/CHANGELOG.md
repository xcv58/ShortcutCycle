# Changelog

All notable changes to this project will be documented in this file.

## [1.7] - Unreleased

### Added
- **Optional Settings window shortcut**: Users can assign their own global shortcut in General settings to show, focus, or hide the Settings window. No shortcut is assigned by default.
- **Accessible app management**: VoiceOver and Voice Control users can browse for apps and use named actions to move or remove apps, delete groups, and select apps in the HUD without relying on drag, hover, or pointer-only gestures.
- **Accessible running status**: The menu bar's running-app indicator now provides a localized screen-reader description without changing its visual design.

### Changed
- **Non-activating HUD**: Showing the HUD no longer activates ShortcutCycle, keeping focus on the current app and making switching feel more responsive.
- **Reduced Motion support**: The HUD now follows the macOS Reduce Motion setting by disabling spring scrolling and icon scaling while preserving clear selection feedback.

### Fixed
- **Shortcut conflicts**: Duplicate group and Settings window shortcut assignments now show a warning and clear the newly recorded shortcut instead of allowing both actions to share the same hotkey.
- **Shortcut recorder localization**: Shortcut recorder placeholder text and app-command conflict warnings now follow ShortcutCycle's in-app language setting.
- **HUD interaction stability**: Fixed an intermittent hover-related crash while preserving pointer hover feedback, keyboard navigation, clicks, and accessibility actions.
- **HUD layout and focus styling**: Fixed occasional off-center app rows and removed an unintended focus border around HUD icons.
- **Single-app tap and hold**: A quick shortcut tap still hides the frontmost app, while holding now reveals the one-item HUD and reliably keeps or returns that app to the front when released.

## [1.6] - 2026-05-26

### Added
- **Running app quick add**: The group editor now lets you add currently running apps with a single click, reducing the need to browse Finder when capturing an active workflow.
- **Shortcut suggestions**: Groups without an assigned shortcut now surface suggested hotkeys to streamline initial setup.
- **Expanded Settings shortcuts**: ShortcutCycle now adds more macOS-style commands while Settings is open, including Settings, appearance toggle, group navigation, and group reordering shortcuts.

### Changed
- **First-launch onboarding**: On first manual launch, ShortcutCycle now opens Settings with a welcome banner to make the menu bar-based app model clearer.
- **Language sync**: Changing the app language now updates bundled controls more consistently, including shortcut recorders and imported settings.
- **Backup comparison guidance**: The Automatic Backup Browser now explains that comparisons default to the next older backup and points to the "Changes from" picker for choosing a different baseline.

### Fixed
- **Narrow group editor layout**: Cycling Mode controls now remain readable and properly aligned in narrow group editor layouts.
- **Desktop Space jumps**: App switching no longer sends users to another Space merely because the Settings window is open elsewhere.
- **Minimized multi-profile windows**: Minimized multi-profile app instances (for example, multiple Firefox profiles) are now excluded from the HUD when macOS cannot reliably restore a specific minimized instance without Accessibility permission. Instances hidden with Cmd+H remain visible because `unhide()+activate()` restores them reliably. When all instances of a multi-profile app are minimized, ShortcutCycle preserves one HUD entry so the app remains accessible.
- **Quick-tap and press-and-hold reliability**: Blind switching, HUD reveal timing, and modifier-release finalization now follow the same session flow so rapid taps and peek-to-reveal interactions stay in sync.

## [1.5] - 2026-03-01

### Added
- **Automation with `shortcutcycle://`**: ShortcutCycle can now be controlled from Apple Shortcuts, Alfred, Raycast, Keyboard Maestro, shell scripts, and other tools.
- **Direct links into the app**: URL commands can now open Settings to a specific tab, open the Automatic Backup Browser, change settings, flush pending auto-save, export or import settings, and restore backups by latest item, index, name, or path.

### Changed
- **Smarter auto-backups**: Temporary switching-state updates now persist without creating unnecessary automatic backups.

### Fixed
- **Settings links after launch**: URL commands for opening Settings and related views now work reliably immediately after app launch.
- **Duplicate backup files**: Manual and automatic backups no longer create duplicate files when only temporary switching state has changed.

## [1.4] - 2026-02-12

### Added
- **MRU Cycling**: Apps in each group are now ordered by Most Recently Used, matching macOS Cmd+Tab behavior. The most recently used app is always one tap away. MRU order updates only when you finalize your selection (release modifiers or click), not during intermediate cycling steps.
- **Press and Hold**: Added support for "Press and Hold" behavior to match macOS Command+Tab. Hold the shortcut to view the HUD; tap quickly to switch blindly.
- **In-App Keyboard Shortcuts**: Added macOS menu bar commands with keyboard shortcuts when the settings window is open. Includes tab switching (Cmd+1/2), add/delete group (Cmd+N, Cmd+Delete with confirmation), group navigation (Cmd+Up/Down, Cmd+[/], Cmd+K/J), and sidebar toggle (Cmd+Ctrl+S).
- **Language Picker**: Language picker now shows both the system-language name and the native name (e.g. "German / Deutsch") for easier identification.

### Fixed
- **HUD Visibility Bug**: Fixed an issue where rapid, disjoint presses of the shortcut could incorrectly trigger the HUD (treating it as a cycle). Now, releasing the key properly ends the session, ensuring blind switching is reliable.
- **Multi-Profile Reliability**: Fixed issues where cycling and app activation could fail for multi-instance apps (e.g. Firefox/Chrome profiles) after a process restart or when the HUD fallback path was triggered. Also fixed a regression where the shortcut always activated the first instance (by PID) instead of the last-active one when returning from a different app.
- **System Language Detection**: Fixed detection of system language for non-English locales.
- **Manual Backup Error Feedback**: Fixed "Back Up Now" flow to show a failure message when writing the backup file fails, instead of reporting a successful save.

## [1.3] - 2026-02-06

### Added
- **Multi-Profile Support**: Apps with multiple instances (like Firefox profiles) are now shown separately in the HUD and can be cycled through individually.

## [1.2] - 2026-02-01

### Added
- **Cycling Modes**: Added ability to choose between "Running apps only" or "All apps (open if needed)" for each group.
- **macOS 14+ Support**: Bumped minimum requirement to macOS 14.0 for modern API usage.
- **Automatic Backups**: Added automatic backups for groups and settings, with a visual browser to preview, compare, and restore previous configurations.

### Changed
- **Refactoring**: Major code restructuring for better modularity and maintainability.
- **CI/Build**: Fixed CI build process and improved test coverage.

## [1.1] - 2026-01-29

### Added
- **Theme Selection**: Added option to choose between System, Light, and Dark themes in General settings and Menu Bar.
- **App Loop Toggle**: Option to control whether to loop only through currently open applications or open them if they are closed.
- **Localization**: Added missing keys for appearance settings.

### Changed
- **HUD & Menu Bar**: Enhanced layout, scrolling, and interactions for a smoother experience.
- **Group Editing**: Refined group name editing with a native-feeling "ghost text field" behavior.
- **Architecture**: Refactored models to Core and established extensive unit tests and CI.
- **Metadata**: Updated App Store plans and metadata.

### Fixed
- **Menu Bar**: Implemented dynamic height to correctly fit content, preventing excessive height or layout collapse.
- **Group Names**: Fixed an issue where group names could become stale.
- **HUD Theme**: Ensure App Switcher HUD properly respects the selected theme.
