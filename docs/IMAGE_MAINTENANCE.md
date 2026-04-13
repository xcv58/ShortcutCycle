# Landing Page Image Maintenance

This document describes how to update the images on the landing page (`docs/index.html`).

## Overview

The landing page uses optimized WebP images located in `docs/assets/images/`. These are generated from the high-resolution source screenshots in `ShortcutCycle/App Store Connect Assets/Screenshots/` and the app icon.

## Image Generation

The preferred workflow is:

```bash
python3 scripts/generate_screenshots.py
```

That script:

1. Builds the app
2. Regenerates the raw App Store PNG screenshots in `ShortcutCycle/App Store Connect Assets/Screenshots/`
3. Rebuilds the optimized website images in `docs/assets/images/`

Under the hood, `scripts/optimize_images.py` generates two versions of each screenshot to support responsive loading:

1.  **Large (Default)**: 1800px width (Retina/Desktop). Filename format: `name.webp`
2.  **Small**: 900px width (Mobile/Standard). Filename format: `name-small.webp`

## How to Update Images

If you have updated the UI and want to regenerate both the App Store screenshots and the website images:

1.  Run the screenshot generator from the project root:

    ```bash
    python3 scripts/generate_screenshots.py
    ```

2.  Verify:
    - `ShortcutCycle/App Store Connect Assets/Screenshots/` contains the refreshed `2880x1800` PNGs
    - `docs/assets/images/` contains the refreshed `.webp` and `-small.webp` derivatives
    - `docs/index.html` still looks correct in a browser

3.  Commit both the raw PNG changes and the derived website assets.

## Web-Only Refresh

If you only changed the raw screenshot PNGs manually and do not need to rerun the app harness, you can still refresh the website assets directly:

```bash
python3 scripts/optimize_images.py
```

If you added new source filenames, also update the `FILES_TO_PROCESS` dictionary in `scripts/optimize_images.py`.

**Prerequisites**:
- Python 3
- Pillow library (`pip3 install Pillow`)

## Why this setup?

The raw screenshots are very large. We use a responsive image setup (`srcset` in `index.html`) to serve the appropriate size based on the user's device. This significantly improves the Lighthouse performance score by reducing the data transfer on smaller devices.
