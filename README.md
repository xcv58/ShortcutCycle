# ShortcutCycle

**Switch apps instantly with hotkeys**

[![Test](https://github.com/xcv58/ShortcutCycle/actions/workflows/test.yml/badge.svg)](https://github.com/xcv58/ShortcutCycle/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/xcv58/ShortcutCycle/graph/badge.svg?token=8C1D6F0E5B)](https://codecov.io/gh/xcv58/ShortcutCycle)

ShortcutCycle helps you switch between your favorite apps with just one keyboard shortcut. Instead of remembering many shortcuts, just group your apps (like "Browsers", "Coding", or "Social") and use one key to cycle through them. Simplify your workflow and save time every day!

[Official Website](https://shortcutcycle.vercel.app/)

## Comparison

| Feature | ShortcutCycle | AltTab | Contexts | Witch | rcmd | TabTab | Raycast | Alfred | Manico | Command+Tab |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Type** | Group Switcher | Window Switcher | Window Switcher | Window Switcher | App Switcher | Window Switcher | Launcher | Launcher | App Launcher | App Switcher |
| **Context Switching** | ✅ (Groups) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **One-Key Cycle** | ✅ (Option+Num) | ❌ | ⚠️ (Numbered) | ❌ | ✅ (R-Cmd+Key) | ❌ | ❌ | ❌ | ✅ (Option+Num) | ❌ |
| **Visual HUD** | ✅ | ✅ (Thumbnails) | ✅ (Sidebar) | ✅ (List) | ✅ (Dynamic) | ✅ (Thumbnails) | ✅ (List) | ✅ (List) | ✅ (List) | ✅ (Icons) |
| **Launch Apps** | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **Search Windows** | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Price** | $3.99 | Free | ~$10 | $14 | ~$10 | ~$24 | Free/Pro | Free/Powerpack | Free/Pro | Free |

## Features

- **Group Apps**: Put related apps together (e.g., \"Browsers\" for Chrome, Safari, Edge; or \"Messaging\" for Slack, Discord, Messages).
- **One Key Magic**: Press your global shortcut to cycle through apps in the group. Press it again to switch to the next one.
- **Smart Order**: Apps are automatically ordered by most recently used — the app you want is always available, just like macOS's Command+Tab.
- **Press and Hold**: Hold the shortcut to peek at the HUD without switching immediately, just like macOS's native Command+Tab behavior.
- **Multi-Profile Support**: Apps with multiple instances (like Firefox profiles) are shown separately and can be cycled through individually.
- **See What's Happening**: A beautiful, native-looking HUD overlay shows you which app is active and what's coming up next.
- **Instant Access**: Automatically launches apps if they aren't running when you switch to them.
- **Multi-language**: Fully localized in 15 languages: English, Arabic, Chinese (Simplified & Traditional), Dutch, French, German, Italian, Japanese, Korean, Polish, Portuguese (Brazil), Russian, Spanish, and Turkish.
- **Keyboard Shortcuts**: Navigate the settings window with standard macOS keyboard shortcuts — switch tabs, add/delete groups, cycle through groups, and toggle the sidebar.
- **Import/Export**: Save your groups and settings to a JSON file to keep them safe or share with others.
- **Light & Dark**: Looks great in both Light and Dark modes.

### How Cycling Works

ShortcutCycle behaves a little differently depending on whether the HUD is enabled:

- **When HUD is enabled** (`Show HUD` = on):
  - Cycling follows the HUD selection during that interaction.
  - MRU order still decides which apps are near the front.
  - Best when you want visual feedback while switching.

- **When HUD is disabled** (`Show HUD` = off):
  - Repeated taps continue through the group in a short tap session.
  - This avoids getting stuck toggling between only two apps.
  - Best when you want fast, blind switching.

- **When switching between groups**:
  - First tap in a different group resumes that group's context, instead of stepping from an overlapping app that happens to be frontmost.

**Example (HUD off):**
- Group: `A, B, C`
- You tap the group shortcut repeatedly.
- Result: `A -> B -> C -> A` (continuous cycle), not just `A <-> B`.

**Example (cross-group):**
- Group 1: `A, B, C, D`
- Group 2: `X, Y, D`
- You use Group 2 and land on `D`, then trigger Group 1.
- Group 1 resumes its own context instead of jumping based only on `D` being frontmost.

### Accessibility
We believe tools should be for everyone. ShortcutCycle is built with accessibility in mind:
- **VoiceOver**: Fully labeled controls and navigation.
- **Voice Control**: All features accessible via standard voice commands.
- **Dark Interface**: Fully compatible with macOS Dark Mode.
- **Differentiate Without Color Alone**: Critical information uses text or position, not just color.
- **Sufficient Contrast**: Uses standard system colors for maximum readability.
- **Reduced Motion**: Standard animations respect system preferences.

## Installation

### From Mac App Store
1. Download ShortcutCycle from the [Mac App Store](https://apps.apple.com/us/app/shortcutcycle/id6758281578).
2. Open the app. You'll see a small icon (a command symbol in a square box) in your menu bar.

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

> **Tip:** Hold the shortcut key to peek at the HUD and automatically cycle through your apps!

## Support

Found a bug or have a feature request? Please [open an issue](https://github.com/xcv58/ShortcutCycle/issues) on GitHub.

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
