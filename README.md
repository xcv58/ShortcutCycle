# ShortcutCycle

ShortcutCycle is a macOS utility that allows you to cycle through multiple applications using a single keyboard shortcut. It acts as a "Group Switcher" - you define a group of apps and assign a global hotkey. Pressing the hotkey activates the first app, pressing again cycles to the next one, and so on.

## Features

- **App Groups**: Create multiple groups of applications (e.g., "Development" might include Xcode, Terminal, and Simulator).
- **Single Hotkey Cycle**: Assign one global shortcut to cycle through all open apps in a group.
- **Smart Activation**: If no app in the group is running, it launches the first one. If one or more are running, it cycles through them.
- **HUD Display**: Shows a beautiful, native-like Heads-Up Display when switching, showing which app is active and what's next.
- **HUD Customization**: Toggle HUD visibility and whether to show the shortcut hint.
- **Localization**: Supports English, Japanese, Chinese (Simplified), and German.
- **Dark Mode Support**: Fully compatible with macOS Light and Dark modes.

## Installation

1. Download the latest `.dmg` from the [Releases](https://github.com/xcv58/ShortcutCycle/releases) page.
2. Drag `ShortcutCycle` to your Applications folder.
3. Launch the app. You will see a menu bar icon.
4. Grant **Accessibility Permissions** when prompted (required to intercept global shortcuts and switch apps).

## Usage

1. Click the menu bar icon and select **Settings...**.
2. Create a new group using the `+` button in the sidebar.
3. Drag and drop applications into the group area.
4. Record a global keyboard shortcut (e.g., `Option + 1`).
5. Close the settings window.
6. Press your shortcut (`Option + 1`) to launch or switch to the apps in that group!

## Building from Source

Requirements:
- macOS 14.0+
- Xcode 15.0+

```bash
# Clone the repository
git clone https://github.com/xcv58/ShortcutCycle.git

# Open project
open ShortcutCycle/ShortcutCycle.xcodeproj

# Build and Run
```

## License

MIT License.
