#!/usr/bin/env python3
import os
import sys
from PIL import Image

# Configuration
# Paths are relative to the project root (where this script is expected to be run from)
PROJECT_ROOT = os.getcwd()

# Source Directories
SCREENSHOTS_DIR = os.path.join(PROJECT_ROOT, "ShortcutCycle/App Store Connect Assets/Screenshots")
ICON_PATH = os.path.join(PROJECT_ROOT, "ShortcutCycle/ShortcutCycle/Assets.xcassets/AppIcon.appiconset/1024.png")

# Output Directory
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "docs/assets/images")

# Map source filename to output filename (without extension)
FILES_TO_PROCESS = {
    "HUD Light.png": "hud-light",
    "HUD-Grid Light.png": "hud-grid-light",
    "HUD Dark.png": "hud-dark",
    "HUD-Grid Dark.png": "hud-grid-dark",
    "General Light.png": "general-light",
    "General Dark.png": "general-dark",
    "Group Light.png": "group-light",
    "Group Dark.png": "group-dark",
    "Menubar and languages.png": "menubar-languages",
    "Automatic Backups.png": "automatic-backups",
    "Automatic Backups Dark.png": "automatic-backups-dark",
}

# Target widths for responsive images
TARGET_WIDTHS = {
    "large": 1800,  # Retina / Desktop
    "small": 900    # Mobile / Standard
}
MAX_WIDTH_ICON = 160 # Retina quality for 40px icon

def optimize_image(source_path, output_name_base, widths):
    if not os.path.exists(source_path):
        print(f"Warning: Source file not found: {source_path}")
        return

    try:
        with Image.open(source_path) as original_img:
            for suffix, width in widths.items():
                img = original_img.copy()
                
                # Resize if needed
                if img.width > width:
                    ratio = width / img.width
                    new_height = int(img.height * ratio)
                    img = img.resize((width, new_height), Image.Resampling.LANCZOS)
                
                # Construct output filename
                # If suffix is 'large', use base name for backward compatibility/simplicity
                # If suffix is 'small', append -small
                if suffix == "large":
                    final_name = f"{output_name_base}.webp"
                else:
                    final_name = f"{output_name_base}-{suffix}.webp"

                output_path = os.path.join(OUTPUT_DIR, final_name)
                img.save(output_path, "WEBP", quality=80)
                print(f"✅ Generated {final_name} ({img.width}x{img.height})")
            
    except Exception as e:
        print(f"❌ Error processing {source_path}: {e}")

def optimize_icon(source_path, output_name, max_width):
    if not os.path.exists(source_path):
        print(f"Warning: Icon file not found: {source_path}")
        return
        
    try:
        with Image.open(source_path) as img:
             if img.width > max_width:
                img = img.resize((max_width, max_width), Image.Resampling.LANCZOS)
             
             output_path = os.path.join(OUTPUT_DIR, f"{output_name}.webp")
             img.save(output_path, "WEBP", quality=80)
             print(f"✅ Generated {output_name}.webp")
    except Exception as e:
        print(f"❌ Error processing icon: {e}")

def main():
    print(f"🚀 Starting image optimization...")
    print(f"📂 Output directory: {OUTPUT_DIR}")
    
    if not os.path.exists(OUTPUT_DIR):
        print("Creating output directory...")
        os.makedirs(OUTPUT_DIR)

    # Check for Pillow
    try:
        import PIL
    except ImportError:
        print("❌ Error: 'Pillow' library is not installed.")
        print("Please install it running: pip3 install Pillow")
        sys.exit(1)

    # Process Screenshots
    count = 0
    for filename, output_name in FILES_TO_PROCESS.items():
        source = os.path.join(SCREENSHOTS_DIR, filename)
        optimize_image(source, output_name, TARGET_WIDTHS)
        count += 1

    # Process Icon
    optimize_icon(ICON_PATH, "app-icon", MAX_WIDTH_ICON)
    count += 1
    
    print(f"✨ Done! Processed {count} source images.")

if __name__ == "__main__":
    # Ensure we are running from project root if possible
    if not os.path.isdir("docs") or not os.path.isdir("ShortcutCycle"):
        print("⚠️  Warning: It looks like you aren't running this from the project root.")
    
    main()
