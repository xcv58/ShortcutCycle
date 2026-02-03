# Landing Page Image Maintenance

This document describes how to update the images on the landing page (`docs/index.html`).

## Overview

The landing page uses optimized WebP images located in `docs/assets/images/`. These are generated from the high-resolution source screenshots in `ShortcutCycle/App Store Connect Assets/Screenshots/` and the app icon.

## Image Generation

The `scripts/optimize_images.py` script automatically generates two versions of each screenshot to support responsive loading:

1.  **Large (Default)**: 1800px width (Retina/Desktop). Filename format: `name.webp`
2.  **Small**: 900px width (Mobile/Standard). Filename format: `name-small.webp`

## How to Update Images

If you have updated the screenshots (e.g. for a new feature) or the app icon, follow these steps to regenerate the web assets:

1.  **Update Source Files**: Ensure the new screenshots are in `ShortcutCycle/App Store Connect Assets/Screenshots/` with the same filenames as before.
    - `HUD Light.png`
    - `HUD-Grid Light.png`
    - ...etc
    
    If you added *new* files, you will need to add them to the `FILES_TO_PROCESS` dictionary in `scripts/optimize_images.py`.

2.  **Run the Optimization Script**:
    From the project root directory, run:

    ```bash
    python3 scripts/optimize_images.py
    ```

    **Prerequisites**:
    - Python 3
    - Pillow library (`pip3 install Pillow`)

3.  **Verify**:
    - Check `docs/assets/images/` to ensure both `.webp` and `-small.webp` files are updated.
    - Check `docs/index.html` in your browser.
    - Commit the changes to `docs/assets/images/`.

## Why this setup?

The raw screenshots are very large. We use a responsive image setup (`srcset` in `index.html`) to serve the appropriate size based on the user's device. This significantly improves the Lighthouse performance score by reducing the data transfer on smaller devices.
