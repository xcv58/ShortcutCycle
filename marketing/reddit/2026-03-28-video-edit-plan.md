# Reddit Video Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-edit `docs/assets/videos/1.mp4` into a clearer Reddit launch clip that communicates `⌥1 Daily` and `⌥3 Chats` within the first few seconds using minimal captions and existing footage.

**Architecture:** Build a reproducible local editing pipeline instead of a one-off manual export. Use the existing source video, trim the strongest beats into a shorter structure, overlay lightweight caption cards, and export a new Reddit-ready MP4 in `marketing/reddit/` so the website asset remains untouched.

**Tech Stack:** `ffmpeg`, `ffprobe`, ImageMagick (`magick`, `montage`), shell script

---

### Task 1: Map the source clip into reusable segments

**Files:**
- Create: `marketing/reddit/edit-work/clip-map.md`
- Read: `docs/assets/videos/1.mp4`

- [ ] **Step 1: Create the working directory**

Run:

```bash
mkdir -p marketing/reddit/edit-work marketing/reddit/output marketing/reddit/overlays
```

Expected: the three directories exist.

- [ ] **Step 2: Generate dense frame sheets for the source clip**

Run:

```bash
for t in $(seq 0 0.5 12); do
  ffmpeg -y -ss "$t" -i docs/assets/videos/1.mp4 -frames:v 1 "marketing/reddit/edit-work/frame-${t}.png" >/dev/null 2>&1
done
montage marketing/reddit/edit-work/frame-*.png \
  -tile 5x5 -geometry 320x180+6+6 -background white \
  marketing/reddit/edit-work/source-contact-sheet.png
```

Expected: a contact sheet exists at `marketing/reddit/edit-work/source-contact-sheet.png`.

- [ ] **Step 3: Record the selected clip ranges**

Write `marketing/reddit/edit-work/clip-map.md` with the chosen time windows for:

- opening `⌥1` readability beat
- strongest `⌥1` Daily cycle
- strongest `⌥3` Chats jump
- ending HUD / hold-to-peek proof beat

Expected: exact start/end timestamps are documented before editing logic is written.

### Task 2: Create reusable caption overlay assets

**Files:**
- Create: `marketing/reddit/overlays/one-shortcut-per-group.png`
- Create: `marketing/reddit/overlays/opt1-daily.png`
- Create: `marketing/reddit/overlays/opt3-chats.png`
- Create: `marketing/reddit/overlays/hold-to-peek.png`

- [ ] **Step 1: Generate the caption cards with ImageMagick**

Use `magick` to create transparent PNG overlays with:

- small rounded dark background
- white text
- consistent padding
- SFNS or Arial font

Expected: all four PNG overlays render at 1920x1080 with transparency.

- [ ] **Step 2: Verify overlay legibility**

Run:

```bash
identify marketing/reddit/overlays/*.png
```

Expected: each overlay exists and reports the expected image size.

### Task 3: Build a reproducible export script

**Files:**
- Create: `marketing/reddit/build-reddit-video.sh`
- Read: `docs/assets/videos/1.mp4`
- Read: `marketing/reddit/overlays/*.png`
- Read: `marketing/reddit/edit-work/clip-map.md`

- [ ] **Step 1: Write the export script**

The script should:

- define the selected timestamps from the clip map
- trim 3-4 segments from `docs/assets/videos/1.mp4`
- apply a short opening pause with `tpad` or a brief repeated frame if needed
- concatenate the segments in the approved order
- overlay caption PNGs only during their intended time ranges
- encode a final H.264 MP4 to `marketing/reddit/output/shortcutcycle-reddit-cut.mp4`

Expected: a single script can rebuild the output from source + overlays.

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x marketing/reddit/build-reddit-video.sh
```

Expected: the script is executable.

### Task 4: Render and review a first pass

**Files:**
- Run: `marketing/reddit/build-reddit-video.sh`
- Create: `marketing/reddit/output/shortcutcycle-reddit-cut.mp4`
- Create: `marketing/reddit/edit-work/review-sheet.png`

- [ ] **Step 1: Render the edited video**

Run:

```bash
./marketing/reddit/build-reddit-video.sh
```

Expected: `marketing/reddit/output/shortcutcycle-reddit-cut.mp4` is created successfully.

- [ ] **Step 2: Verify runtime, resolution, and codec**

Run:

```bash
ffprobe -v error \
  -show_entries format=duration:stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 \
  marketing/reddit/output/shortcutcycle-reddit-cut.mp4
```

Expected:

- duration roughly `14-16` seconds
- `width=1920`
- `height=1080`
- `codec_name=h264`

- [ ] **Step 3: Generate a review contact sheet**

Run:

```bash
for t in $(seq 0 1 10); do
  ffmpeg -y -ss "$t" -i marketing/reddit/output/shortcutcycle-reddit-cut.mp4 -frames:v 1 "marketing/reddit/edit-work/review-${t}.png" >/dev/null 2>&1
done
montage marketing/reddit/edit-work/review-*.png \
  -tile 4x3 -geometry 360x202+6+6 -background white \
  marketing/reddit/edit-work/review-sheet.png
```

Expected: `marketing/reddit/edit-work/review-sheet.png` shows the new narrative flow clearly.

### Task 5: Refine once if the first pass is still too cryptic

**Files:**
- Modify: `marketing/reddit/build-reddit-video.sh`
- Modify: `marketing/reddit/edit-work/clip-map.md`
- Regenerate: `marketing/reddit/output/shortcutcycle-reddit-cut.mp4`

- [ ] **Step 1: Review the first pass against the acceptance criteria**

Check whether a cold viewer can infer:

- one shortcut maps to one group
- `⌥1` and `⌥3` represent different contexts
- the app switches grouped apps quickly
- the video still feels native

Expected: either approve the first pass or identify one precise fix.

- [ ] **Step 2: Apply one focused refinement if needed**

Allowed refinements:

- shorten redundant cycling
- shift clip boundaries
- change caption timing
- drop `Hold to peek` if the ending feels too busy

Expected: only one iteration unless a serious clarity problem remains.

### Task 6: Deliver the final asset and document usage

**Files:**
- Final: `marketing/reddit/output/shortcutcycle-reddit-cut.mp4`
- Modify: `marketing/reddit/launch-plan.md`

- [ ] **Step 1: Update the launch plan to point at the edited asset**

Replace the old file reference if needed so the runbook points to the final Reddit upload asset.

- [ ] **Step 2: Final verification**

Run:

```bash
git status --short
ls -lh marketing/reddit/output/shortcutcycle-reddit-cut.mp4
```

Expected: the edited asset exists and the changed files are easy to review.

- [ ] **Step 3: Commit once the asset and supporting files are approved**

Run:

```bash
git add marketing/reddit
git commit -m "marketing: re-edit reddit launch video"
```

Expected: one focused commit covering the Reddit video edit pipeline and output.
