#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT_DIR/scripts/video_pipeline.py" build --video reddit-overview "$@"
