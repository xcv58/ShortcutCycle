# Website screenshots — 1.11

Fresh native captures taken on macOS 27, September 15, 2026, using the
separately identified local capture build. These show the released UI with
demo groups; they are not screenshots of the installed App Store binary.

## Updated assets

Ten images, each with an 1800×1125 desktop and 900×562 mobile WebP:

- Horizontal HUD and grid HUD, light and dark.
- Groups and General settings, light and dark.
- Automatic Backups, light and dark, including the updated General view behind it.

Existing filenames in `docs/assets/images` preserve gallery, appearance-switching,
responsive-image, and social-preview references. The menu montage was inspected
and retained because the represented menu surface is unchanged. There is no
language montage referenced by the website. Video files and their posters are
unchanged; the approved Reddit video is a separate asset.

## Reproduce

Build the isolated `capture-1.11` app from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project ShortcutCycle/ShortcutCycle.xcodeproj -scheme ShortcutCycle \
  -configuration Debug -derivedDataPath .artifacts/capture-1.11/DerivedData \
  PRODUCT_BUNDLE_IDENTIFIER=com.xcv58.ShortcutCycle.capture \
  CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES build
```

Use Python with Pillow and PyYAML. On the capture machine's 1512×982-point Retina display:

```sh
python3 scripts/refresh_website_screenshots.py capture --region 36,41,1440,900
```

The region must fit entirely on the staged display, excluding the menu bar and
Dock. Raw PNGs and logs go to `.artifacts/website-1.11`. Inspect every image before:

```sh
python3 scripts/refresh_website_screenshots.py install
```

HUD captures include the real backdrop and native glass in a single screen
capture. Settings use native window captures. The temporary backdrop is raised
again for every scene. The system glass preference and accessibility settings
are preserved; this set uses the machine's existing maximum glass tint setting.
Only resize and WebP encoding are applied to captured pixels.

Screenshot mode hides the development-only status badge, while retaining native
controls. Screenshot backup fixtures use unique temporary directories. The
capture app's preferences are backed up and restored, and the production app is
not terminated or used for demo setup.

Use this workflow for website refreshes instead of the legacy
`generate_screenshots.py` HUD cutout/compositing route. App Store screenshot
masters are not replaced by this website-only workflow. The capture report
records the binary hash, source commit, environment, and raw image hashes.

These asset changes are prepared locally; deployment is separate.
