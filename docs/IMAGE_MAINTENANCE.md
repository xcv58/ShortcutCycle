# Landing Page Image Maintenance

This document describes how to update the images on the landing page (`docs/index.html`).

## Overview

The landing page uses optimized WebP images located in `docs/assets/images/`. These are generated from the high-resolution source screenshots in `ShortcutCycle/App Store Connect Assets/Screenshots/` and the app icon.

## How to Update Images

If you have updated the screenshots (e.g. for a new feature) or the app icon, follow these steps to regenerate the web assets:

1. **Update Source Files**: Ensure the new screenshots are in `ShortcutCycle/App Store Connect Assets/Screenshots/` with the same filenames as before.
   - `HUD Light.png`
   - `HUD-Grid Light.png`
   - `HUD Dark.png`
   - ...etc
   
   If you added *new* files, you will need to add them to the `FILES_TO_PROCESS` dictionary in `scripts/optimize_images.py`.

2. **Run the Optimization Script**:
   From the project root directory, run:

   ```bash
   python3 scripts/optimize_images.py
   ```

   **Prerequisites**:
   - Python 3
   - Pillow library (`pip3 install Pillow`)

3. **Verify**:
   - Check `docs/index.html` in your browser to match the new images.
   - Commit the changes to `docs/assets/images/`.

## Why this setup?

The raw screenshots are very large (PNG, ~9MB each). Serving them directly would give the page a poor performance score (approx ~25/100). 

The script:
- Resizes them to appropriate dimensions (1800px width for Retina support).
- Converts them to **WebP**, reducing size to ~200KB without visible quality loss.
- This ensures the landing page loads instantly and gets a high Lighthouse score (90+).
