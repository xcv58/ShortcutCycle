# Changelog

All notable changes to this project will be documented in this file.

## [1.4] - 2026-02-12

### Added
- **App Groups**: Groups can now contain specific apps, and you can define custom keyboard shortcuts for each group.
- **Press and Hold**: Added support for "Press and Hold" behavior to match macOS Command+Tab. Hold the shortcut to view the HUD; tap quickly to switch blindly.
- **In-App Keyboard Shortcuts**: Added macOS menu bar commands with keyboard shortcuts when the settings window is open. Includes tab switching (Cmd+1/2), add/delete group (Cmd+N, Cmd+Delete with confirmation), group navigation (Cmd+Up/Down, Cmd+[/], Cmd+K/J), and sidebar toggle (Cmd+Ctrl+S).
- **Language Picker**: Language picker now shows both the system-language name and the native name (e.g. "German / Deutsch") for easier identification.

### Fixed
- **HUD Visibility Bug**: Fixed an issue where rapid, disjoint presses of the shortcut could incorrectly trigger the HUD (treating it as a cycle). Now, releasing the key properly ends the session, ensuring blind switching is reliable.

### Fixed
- **Multi-Profile Reliability**: Fixed issues where cycling and app activation could fail for multi-instance apps (e.g. Firefox/Chrome profiles) after a process restart or when the HUD fallback path was triggered. Also fixed a regression where the shortcut always activated the first instance (by PID) instead of the last-active one when returning from a different app.
- **System Language Detection**: Fixed detection of system language for non-English locales.

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
