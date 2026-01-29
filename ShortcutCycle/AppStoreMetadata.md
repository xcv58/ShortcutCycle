# App Store Metadata

## Pricing
Tier 4 ($3.99 USD) - One-time purchase

## App Name
ShortcutCycle

## Subtitle
Switch apps instantly with hotkeys

## Promotional Text
Group your favorite apps and switch between them instantly with a single keyboard shortcut. Simplify your workflow and save time every day!

## App Icon
`ShortcutCycle/ShortcutCycle/Assets.xcassets/AppIcon.appiconset/1024.png`

## Privacy Policy
[Privacy Policy](https://github.com/xcv58/ShortcutCycle/blob/master/PRIVACY_POLICY.md) (File created at root: `PRIVACY_POLICY.md`)

## Description
ShortcutCycle helps you switch between your favorite apps with just one keyboard shortcut. Instead of remembering many shortcuts, just group your apps and use one key to cycle through them.

**Group Your Apps by Context**
Put related apps together so they are always at your fingertips:
- **Browsers**: Chrome, Safari, Edge, or even Chrome Apps.
- **Messaging**: Slack, Discord, Microsoft Teams, and Apple Messages.
- **Development**: Xcode, Terminal, and Simulator.
- **Design**: Figma, Sketch, and Adobe Creative Cloud.

**One Key Magic**
Press your global shortcut to open the first app in your group. Press it again to switch to the next one. It's the fastest way to navigate your Mac without taking your hands off the keyboard.

**Key Features:**
- **Instant Access**: If an app isn't running, ShortcutCycle launches it for you.
- **Visual HUD**: A beautiful, native-looking overlay shows you which app is active and what's coming up next.
- **Your Language**: Fully localized in 15 languages, including English, Japanese, Chinese, German, Spanish, French, and more.
- **Import/Export**: Save your settings to a JSON file to keep them safe or share with others.

**Built for Everyone**
ShortcutCycle is designed with accessibility in mind, supporting VoiceOver, Voice Control, Dark Interface, Sufficient Contrast, and Reduced Motion.

Optimize your workflow and stop digging through your Applications folder. Download ShortcutCycle today!

## Keywords
shortcuts, productivity, app switcher, hotkey, automation, workflow, tool, mac, cycle, utility

## Support URL
https://github.com/xcv58/ShortcutCycle/issues

## Copyright
2026 ShortcutCycle

## App Review Information

### Contact Information
*   **First Name**: [Your First Name]
*   **Last Name**: [Your Last Name]
*   **Phone Number**: [Your Phone Number]
*   **Email**: [Your Email]

### App Review Notes


**Test Instructions**:
1. Launch ShortcutCycle.

3. Click the menu bar icon and select **Settings...**.
4. Create a group (e.g., "Web") and drag Safari and another app into it.
5. Record a shortcut (e.g., `Option + 1`).
6. Press the shortcut to cycle between the apps. The HUD will appear briefly.
7. Verify that the HUD correctly displays the apps and switching works as intended.

## Screencast Scenarios

We need **3 screencasts**, each **15-30 seconds** long. We will use `KeyCastr` to visualize keystrokes.

### Video 1: Core Switching & One-Line View
**Theme**: Light (System)
**Focus**: The "One Key Magic" and linear HUD layout.

1.  **Setup**: A group "Browsers" with 3-4 apps (Safari, Chrome, Arc/Edge).
2.  **Action**:
    *   Press `Option + 1` repeatedly to cycle through the apps.
    *   Show the **Horizontal List (One Line)** HUD layout.
    *   Demonstrate launching: Close one browser, cycle to it, and show it launching automatically.
    *   *Overlay*: "Switch instantly" / "Auto-launch apps".

### Video 2: Grid View, Arrow Keys & No-HUD Mode
**Theme**: Dark
**Focus**: Handling many apps, keyboard navigation, and "Pro" speed.

1.  **Setup**: A group "Productivity" with 7+ apps (Notes, Calendar, Reminders, Mail, Music, etc.) to trigger the **Grid View**.
2.  **Action**:
    *   A. **Grid HUD**: Activate the group. Show the beautiful **Grid Layout** HUD.
    *   B. **Arrow Keys**: Instead of cycling, use **Right/Down/Left arrow keys** to highlight different apps in the grid. Select one to switch.
    *   C. **No-HUD High Speed**: Briefly open Menu Bar -> Toggle "Show HUD" **OFF**.
    *   Press shortcut quickly -> Show instant switching (like Command+Tab but faster) without any overlay.
    *   *Overlay*: "Grid View for power users" / "Silent Mode for speed".

### Video 3: Customization & Localization
**Theme**: Mixed
**Focus**: Global support and personalization.

1.  **Setup**: Settings Window open.
2.  **Action**:
    *   **Theme**: Toggle Appearance from System -> Dark -> Light. Show the UI adapting instantly.
    *   **Language**: Change Language from English -> Japanese -> Chinese (Simplified).
    *   Show the UI labels updating in real-time.
    *   End with a shot of the Menu Bar dropdown showing the localized text.

---

## Screenshots Guide (Required)

**Goal**: 10 High-Quality Screenshots.
**Resolution**: **2880 x 1800** (16:10 aspect ratio).
**Strategy**: Alternating Light/Dark mode.

### Tools & setup
Use the following **Hammerspoon script** to toggle window size to exactly 1440x900 (which is 2x density for 2880x1800):

```lua
-- Shortcut to resize the focused window to 1440x900
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "R", function()
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    -- Set the width and height
    f.w = 1440
    f.h = 900
    -- Center the window
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x + (max.w / 2) - (f.w / 2)
    f.y = max.y + (max.h / 2) - (f.h / 2)
    win:setFrame(f, 0)
  else
    hs.alert.show("No focused window found")
  end
end)
```

### Shot List

**1. Main Window - Light Mode**
*   **Content**: "Groups" sidebar selected. Populated with "Browsers", "Communication", "Dev".
*   **Focus**: Clean UI, localized specific group names.

**2. Main Window - Dark Mode**
*   **Content**: Same as above but in Dark Mode. Maybe different active group.

**3. HUD Overlay - Horizontal List (Light Mode)**
*   **Action**: Mid-cycle on a group with 3 apps (e.g., Safari, Calendar, Mail).
*   **Focus**: The sleek, floating one-line HUD.

**4. HUD Overlay - Grid View (Dark Mode)**
*   **Action**: Mid-cycle on a large group (8+ apps).
*   **Focus**: The grid layout capability for power users.

**5. Settings - General (Light Mode)**
*   **Content**: General Settings tab.
*   **Focus**: Showing "Launch at Login", "Theme", and "Language" options.

**6. Settings - Group Editing (Dark Mode)**
*   **Content**: Editing a specific group.
*   **Focus**: Drag & drop UI (if visible/mockable), "Cycle through all apps" toggle.

**7. Menu Bar Dropdown (Light/System)**
*   **Content**: Menu bar icon clicked, showing the list of groups and toggles.
*   **Focus**: Quick control access.

**8. Action Shot - "Browsers" (Context)**
*   **Content**: Desktop with Safari and Chrome visible, HUD overlay cycling between them.

**9. Action Shot - "Coding" (Context)**
*   **Content**: Visual Studio Code, Terminal, Simulator.
*   **Focus**: Developer workflow.

**10. Localization Showcase (Mosaic)**
*   **Content**: A composite of the Settings window in 3-4 different languages (English, Japanese, German, Chinese).

### Built-in Apps to Use
For consistency and copyright safety, prefer macOS built-in apps or highly recognizable free tools.

**Core macOS Apps:**
*   **Productivity**: Safari, Mail, Calendar, Reminders, Notes, Freeform.
*   **Media**: Music, TV, Podcasts, Photos, Books.
*   **Info**: Maps, Weather, News, Stocks, Home, Find My.
*   **Utilities**: System Settings, Terminal, Activity Monitor, Calculator, Voice Memos, TextEdit, Preview.
*   **Communication**: Messages, FaceTime, Contacts.

**Safe 3rd Party**: VS Code, Chrome, Firefox, Slack (common and generally safe for generic context).

### Grouping Strategies for Screenshots
Use these presets to create realistic looking groups for your screenshots:

1.  **The "Office" Setup (Productivity)**
    *   *Apps*: Mail, Calendar, Reminders, Notes, Pages.
    *   *Vibe*: Professional, organized. Good for Light Mode.

2.  **The "Creative" Setup (Visuals)**
    *   *Apps*: Photos, Music, Freeform, Safari (showing a design site), Preview.
    *   *Vibe*: Colorful, artistic.

3.  **The "Developer" Setup (Power User)**
    *   *Apps*: Terminal, VS Code (or Xcode icon), Activity Monitor, System Settings.
    *   *Vibe*: Technical, dense information. Perfect for **Dark Mode** & **Grid View**.

4.  **The "Social" Setup (Communication)**
    *   *Apps*: Messages, FaceTime, Mail, Slack.
    *   *Vibe*: Personal, connected.

5.  **The "Dashboard" Setup (Information)**
    *   *Apps*: Weather, Stocks, News, Home, Maps.
    *   *Vibe*: Widget-like, data-heavy. Good for showing off the HUD icons.


