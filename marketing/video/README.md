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

The first implemented vertical slice targets the Reddit overview cut.

- `overview-main` generates a deterministic synthetic source clip and publishes it to `docs/assets/videos/1.mp4`.
- `reddit-overview` reuses that source clip and prepends the generated intro card before publishing `marketing/reddit/output/shortcutcycle-reddit-cut.mp4`.
- The current source footage is built from scripted app-style surfaces and real app icons, so it does not depend on Accessibility window choreography or the live desktop state.
