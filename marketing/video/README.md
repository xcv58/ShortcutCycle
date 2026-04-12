# Video Pipeline

This directory is the tracked source of truth for marketing video recipes.

## Layout

- `fixtures/` contains deterministic app/group state for the integration app.
- `profiles/` contains output and capture defaults.
- `scenes/` describes reusable raw clips. A scene may be recaptured or resolved from a checked-in fallback clip.
- `templates/` contains simple card-rendering templates.
- `videos/` contains published video recipes assembled from cards and scene trims.
- `sets/` groups multiple video recipes for bulk builds.

Generated artifacts are written under:

- `.artifacts/video/raw/<run-id>/`
- `.artifacts/video/cards/<run-id>/<video-id>/`
- `.artifacts/video/renders/<run-id>/<video-id>.mp4`

## Primary Commands

```bash
python3 scripts/video_pipeline.py doctor
python3 scripts/video_pipeline.py build --video reddit-overview
python3 scripts/video_pipeline.py capture --scene overview-main
python3 scripts/video_pipeline.py build-set --set launch
```

## Current Scope

The pipeline now supports the real-capture docs and launch flows.

- `marketing-default` is the stable settings fixture used by `settings-story`.
- `marketing-story` is the storytelling fixture used by `overview-main` and `hud-story`.
- `overview-main` is prepared for repeated group switching across `Essentials` and `Explore` with Calculator as the bridge app and a tracked Preview PDF for deterministic content.
- `hud-story` is prepared for alternating compact and grid HUD beats with longer holds and subtle shortcut badges so the workflow reads clearly on video.
- `reddit-overview` still composes from `overview-main`, but the next capture run should regenerate that source clip before publishing.
