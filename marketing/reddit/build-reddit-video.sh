#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT_DIR/docs/assets/videos/1.mp4"
OUT_DIR="$ROOT_DIR/marketing/reddit/output"
OUT="$OUT_DIR/shortcutcycle-reddit-cut.mp4"
OVERLAY_DIR="$ROOT_DIR/marketing/reddit/overlays"
INTRO_CARD="$OVERLAY_DIR/intro-card.png"

mkdir -p "$OUT_DIR"

for required in \
  "$SRC" \
  "$INTRO_CARD"
do
  if [[ ! -f "$required" ]]; then
    echo "Missing required file: $required" >&2
    exit 1
  fi
done

# Source clip map
SEGMENT_A_START="0.35"
SEGMENT_A_END="10.60"
SEGMENT_B_START="12.50"
SEGMENT_B_END="17.00"

# Intro timing
INTRO_DURATION="1.00"

ffmpeg -y \
  -loop 1 -t "$INTRO_DURATION" -i "$INTRO_CARD" \
  -i "$SRC" \
  -filter_complex "\
[0:v]fps=30,format=yuv420p,setpts=PTS-STARTPTS[intro]; \
[1:v]trim=start=${SEGMENT_A_START}:end=${SEGMENT_A_END},setpts=PTS-STARTPTS[v0]; \
[1:v]trim=start=${SEGMENT_B_START}:end=${SEGMENT_B_END},setpts=PTS-STARTPTS[v1]; \
[v0][v1]concat=n=2:v=1:a=0[main]; \
[intro][main]concat=n=2:v=1:a=0[vout]" \
  -map "[vout]" \
  -an \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -r 30 \
  -movflags +faststart \
  "$OUT"

echo "Wrote $OUT"
