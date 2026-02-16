# ShortcutCycle

**Switch apps instantly with hotkeys**

[![Test](https://github.com/xcv58/ShortcutCycle/actions/workflows/test.yml/badge.svg)](https://github.com/xcv58/ShortcutCycle/actions/workflows/test.yml)

ShortcutCycle helps you switch between your favorite apps with just one keyboard shortcut. Instead of remembering many shortcuts, just group your apps (like "Chat Apps" or "Work Apps") and use one key to cycle through them. Simplify your workflow and save time every day!

## Features

- **Group Apps**: Put related apps together (e.g., \"Browsers\" for Chrome, Safari, Edge; or \"Messaging\" for Slack, Discord, Messages).
- **One Key Magic**: Press your global shortcut to cycle through apps in the group. Press it again to switch to the next one.
- **Smart Order**: Apps are automatically ordered by most recently used — the app you want is always one tap away, just like macOS's Command+Tab.
- **Press and Hold**: Hold the shortcut to see the HUD without switching immediately, just like macOS's native Command+Tab behavior.
- **Multi-Profile Support**: Apps with multiple instances (like Firefox profiles) are shown separately and can be cycled through individually.
- **See What's Happening**: A beautiful, native-looking HUD overlay shows you which app is active and what's coming up next.
- **Instant Access**: Automatically launches apps if they aren't running when you switch to them.
- **Multi-language**: Fully localized in 15 languages: English, Arabic, Chinese (Simplified & Traditional), Dutch, French, German, Italian, Japanese, Korean, Polish, Portuguese (Brazil), Russian, Spanish, and Turkish.
- **Keyboard Shortcuts**: Navigate the settings window with standard macOS keyboard shortcuts — switch tabs, add/delete groups, cycle through groups, and toggle the sidebar.
- **Import/Export**: Save your groups and settings to a JSON file to keep them safe or share with others.
- **Light & Dark**: Looks great in both Light and Dark modes.

### Accessibility
We believe tools should be for everyone. ShortcutCycle is built with accessibility in mind:
- **VoiceOver**: Fully labeled controls and navigation.
- **Voice Control**: All features accessible via standard voice commands.
- **Dark Interface**: Fully compatible with macOS Dark Mode.
- **Differentiate Without Color Alone**: Critical information uses text or position, not just color.
- **Sufficient Contrast**: Uses standard system colors for maximum readability.
- **Reduced Motion**: Standard animations respect system preferences.

## Installation

### From Releases
1. Download the latest `ShortcutCycle.dmg` from the [Releases page](https://github.com/xcv58/ShortcutCycle/releases).
2. Open it and drag `ShortcutCycle` to your Applications folder.
3. Open the app. You'll see a small icon in your menu bar.

### From Source
1. Clone the repository:
   ```bash
   git clone https://github.com/xcv58/ShortcutCycle.git
   ```
2. Open `ShortcutCycle/ShortcutCycle.xcodeproj` in Xcode.
3. Build and Run (Command + R).

## Usage

1. Launch ShortcutCycle.
2. Click the menu bar icon and select **Settings...**.
3. Create a group (click `+`) and drag apps into it.
4. Record a global shortcut (e.g., `Option + 1`).
5. Press the shortcut to open the first app or cycle between them!

## Privacy Policy

Everything runs locally on your Mac. No data is collected.

## For Developers

Requirements:
- macOS 14.0 or later
- Xcode 15.0 or later

```bash
# Clone the code
git clone https://github.com/xcv58/ShortcutCycle.git

# Open the project
open ShortcutCycle/ShortcutCycle.xcodeproj
```

## License

MIT License.
