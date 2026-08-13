#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="$ROOT_DIR/.artifacts/video/venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    PYTHON="python3"
fi

"$PYTHON" "$ROOT_DIR/scripts/video_pipeline.py" build --video reddit-1.10 "$@"
