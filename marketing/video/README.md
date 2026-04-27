# Video Pipeline

This directory is the tracked source of truth for marketing video recipes.

## Layout

- `fixtures/` contains deterministic app/group state for the integration app.
- `profiles/` contains output and capture defaults.
- `scenes/` describes reusable raw clips. A scene may be recaptured or resolved from a checked-in fallback clip.
- `sources/` contains tracked canonical scene captures used as the preferred render source.
- `templates/` contains simple card-rendering templates.
- `videos/` contains published video recipes assembled from cards and scene trims.
- `sets/` groups multiple video recipes for bulk builds.
- `ShortcutCycle/App Store Connect Assets/Preview Videos/` receives the same processed `1.mp4`, `2.mp4`, and `3.mp4` outputs as `docs/assets/videos/` so the website and App Store preview stay in sync by default.

Generated artifacts are written under:

- `.artifacts/video/raw/<run-id>/`
- `.artifacts/video/cards/<run-id>/<video-id>/`
- `.artifacts/video/renders/<run-id>/<video-id>.mp4`

The pipeline prefers a scene's tracked `source_clip` when rendering. Fresh captures still land in `.artifacts/video/raw/<run-id>/`, and if a scene declares `source_clip`, the capture is also copied into `marketing/video/sources/` so later re-renders do not depend on the local `.artifacts` cache.

Scene capture no longer publishes final website or App Store outputs directly. Final deliverables come from the recipe-driven video layer so every public-facing clip can share the same intro-card treatment.

## Primary Commands

```bash
python3 scripts/video_pipeline.py doctor
python3 scripts/video_pipeline.py capture --scene overview-main
python3 scripts/video_pipeline.py build-set --set docs
python3 scripts/video_pipeline.py build-set --set launch
```

## Prerequisites

- Install Python deps: `pip3 install PyYAML Pillow`
- Build the integration app into `.artifacts/xcode-integration/DerivedData/Build/Products/Debug/ShortcutCycle.app`
- If automatic AVFoundation screen detection picks the wrong device, set `SHORTCUTCYCLE_CAPTURE_DEVICE` to an explicit ffmpeg device string such as `3:none`

## Current Scope

The pipeline now supports the real-capture docs and launch flows.

- `marketing-default` is the stable settings fixture used by `settings-story`.
- `marketing-story` is the storytelling fixture used by `overview-main` and `hud-story`.
- `overview-main` is prepared for repeated group switching across privacy-safe `Writing` and `Tools` groups with controlled TextEdit/Preview demo assets.
- `hud-story` is prepared for alternating compact and grid HUD beats across `Writing` and `Showcase` with longer holds and subtle shortcut badges so the workflow reads clearly on video.
- `reddit-overview`, `hud-preview`, and `settings-preview` are the canonical processed videos. They publish the same intro-card style to the website and App Store preview outputs by default.

## Semantic Settings Capture

`settings-story` uses semantic accessibility actions instead of coordinate clicks. Supported ShortcutCycle settings actions include:

- `select-group` with `group`
- `set-tab` with `tab`
- `click-button` with `button`
- `select-backup-row` with `index`
- `scroll-area` with optional `direction`, `count`, and `target`

Set `capture.clean_background: true` on real screen captures to launch a temporary neutral backdrop behind the app. This keeps full-screen AVFoundation captures clean even when unrelated windows are open on the desktop.
