# Screenshot Automation

## Overview

This document is the long-term source of truth for ShortcutCycle screenshot generation.

It covers:

- the canonical screenshot inventory
- the built-in fixture groups used to seed deterministic app state
- localization policy
- the screenshot harness architecture
- the operator workflow for regenerating screenshots after UI changes

This file is intentionally kept outside `docs/` because `docs/` is the marketing site source.

## Goals

- Regenerate the App Store screenshot sources in a repeatable way.
- Produce exact `2880x1800` PNGs for macOS App Store usage.
- Keep app-owned screenshots driven by deterministic in-repo fixtures.
- Keep the website image pipeline working from the regenerated screenshot sources.
- Make it easy to ask Codex to "regenerate all screenshots" after UI changes.

## Output Contract

Raw App Store screenshots live in:

- `ShortcutCycle/App Store Connect Assets/Screenshots/`

Website-optimized derivatives live in:

- `docs/assets/images/`

The current canonical output filenames are:

- `General Light.png`
- `General Dark.png`
- `Group Light.png`
- `Group Dark.png`
- `Automatic Backups.png`
- `Automatic Backups Dark.png`
- `HUD Light.png`
- `HUD Dark.png`
- `HUD-Grid Light.png`
- `HUD-Grid Dark.png`
- `Menu Bar.png`
- `Multiple Languages.png`

All raw PNG outputs must be exactly `2880x1800`.

## Canonical Scene Inventory

The screenshot harness should be able to generate these base scenes directly from the app:

- `general`
  - `MainView` with `GeneralSettingsView` selected
- `group`
  - `MainView` with `GroupSettingsView` selected
- `backups`
  - `MainView` with the Automatic Backups sheet open
- `hud-horizontal`
  - HUD overlay using a small built-in-only group
- `hud-grid`
  - HUD overlay using a larger built-in-only group
- `menu-popover`
  - screenshot-specific popover-style scene used for menu bar marketing assets

The final output set contains both:

- direct captures from those base scenes
- derived composite assets assembled from multiple base captures

## Fixture Groups

Only use macOS built-in apps in screenshot fixtures.

### Groups

- `Info`
  - Weather
  - Maps
  - Stocks
  - News
- `Communication`
  - Messages
  - FaceTime
  - Mail
  - Contacts
- `Productivity`
  - Calendar
  - Reminders
  - Notes
  - Freeform
  - Preview
- `Utilities`
  - Terminal
  - Activity Monitor
  - Console
  - System Settings
  - Calculator
  - Shortcuts
  - App Store
  - QuickTime Player
- `Media`
  - Music
  - TV
  - Podcasts
  - Photos
  - Books
- `Many Apps`
  - Weather
  - Maps
  - Music
  - TV
  - Photos
  - Notes
  - Terminal
  - System Settings
  - App Store
  - Preview

### Preferred Usage

- `Info`
  - horizontal HUD screenshots
- `Many Apps`
  - grid HUD screenshots
- `Utilities`
  - group editor screenshots
- full ordered group list
  - menu popover and localization showcase assets

### Stability Rules

- group order should remain fixed
- group UUIDs should remain fixed
- screenshot fixture shortcuts should remain fixed
- one group may be intentionally disabled for menu-popover marketing variants

## Localization Policy

Use one canonical screenshot set as the primary source of truth.

Localized screenshots are handled in two ways:

1. Composite showcase assets in the primary screenshot set
   - `Menu Bar.png`
   - `Multiple Languages.png`
2. Optional storefront overrides for selected locales
   - only generate these when needed for specific App Store localizations

Do not treat every supported in-app language as a mandatory full screenshot set.

The harness should still support language overrides for direct scene generation so localized variants can be created on demand.

## Technical Approach

### Screenshot Mode

The app provides an internal screenshot mode driven by launch arguments.

This mode is for deterministic generation only and is not an end-user feature.

### Store Seeding

The screenshot harness seeds the app from in-repo fixture definitions.

The seeded state should control:

- groups
- selected group
- keyboard shortcuts
- theme
- language
- HUD options
- welcome-banner dismissal
- backup fixture data

### Window Capture

Settings-style screenshots should come from a real app window sized to:

- `1440x900` points

At Retina scale that yields:

- `2880x1800` pixels

### Derived Composites

`Menu Bar.png` and `Multiple Languages.png` are derived assets.

They are assembled from multiple base captures by the generation script rather than captured as a single live app scene.

## Regeneration Workflow

From the repository root:

```bash
python3 scripts/generate_screenshots.py
```

That command should:

1. build the app
2. generate the raw screenshot set in `ShortcutCycle/App Store Connect Assets/Screenshots/`
3. validate the output dimensions
4. refresh `docs/assets/images/` using the optimized web asset pipeline

## When Updating UI

When the UI changes:

1. update the app
2. run the screenshot generator
3. verify the generated screenshots visually
4. update this document if the inventory, fixture set, or localization policy changed

## Future Work

Potential future extensions:

- storefront-localized screenshot folders for selected locales
- more advanced marketing compositions
- optional app preview generation support
