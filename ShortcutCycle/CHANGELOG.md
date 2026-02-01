# Changelog

All notable changes to this project will be documented in this file.

## [1.2] - 2026-02-01

### Added
- **Cycling Modes**: Added ability to choose between "Running apps only" or "All apps (open if needed)" for each group.
- **macOS 14+ Support**: Bumped minimum requirement to macOS 14.0 for modern API usage.

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
