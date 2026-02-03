---
name: optimize_landing_page_images
description: Update and regenerate optimized landing page images from source screenshots.
---

# Optimize Landing Page Images

Use this skill when the user asks to "update website images", "add new screenshots to the website", or "optimize images".

## Context
The landing page (`docs/index.html`) uses optimized WebP images stored in `docs/assets/images/`.
These images are generated from high-resolution PNG screenshots located in `ShortcutCycle/App Store Connect Assets/Screenshots/`.
A Python script `scripts/optimize_images.py` handles the resizing and conversion.

## Instructions

### 1. Identify New or Changed Images
Check if the user has added new screenshots to `ShortcutCycle/App Store Connect Assets/Screenshots/` or if they want to update existing ones.

### 2. Update the Script (If necessary)
If there are **NEW** files that are not yet being processed:
1.  Read `scripts/optimize_images.py`.
2.  Add the new filename to the `FILES_TO_PROCESS` dictionary.
    - Key: The exact filename in the screenshots folder (e.g., `"New Feature.png"`).
    - Value: A simple, kebab-case name for the output file (e.g., `"new-feature"`).
3.  Save the script.

### 3. Run the Optimization
Execute the script from the project root:

```bash
python3 scripts/optimize_images.py
```

**Note**: The script automatically generates two versions for each screenshot:
- `filename.webp` (1800px width)
- `filename-small.webp` (900px width)

### 4. Verify Output
1.  Check that new `.webp` and `-small.webp` files exist in `docs/assets/images/`.
2.  If the user requested to show these images on the site, edit `docs/index.html`. 
    - Use the `<img srcset="..." sizes="...">` pattern for responsive loading.
    - Reference existing images in `docs/index.html` as examples.

## Dependencies
- Python 3
- Pillow (`pip3 install Pillow`)
