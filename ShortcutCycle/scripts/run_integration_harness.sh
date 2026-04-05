#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$PROJECT_ROOT/.." && pwd)

PROJECT_FILE="ShortcutCycle.xcodeproj"
SCHEME="ShortcutCycleIntegration"
CONFIGURATION="Debug"
APP_BUNDLE_ID="com.xcv58.ShortcutCycle.Integration"
FIXTURE_PATH="$PROJECT_ROOT/ShortcutCycleIntegrationFixtures/IntegrationHUD.settings.json"
WINDOW_PROBE="$SCRIPT_DIR/integration_window_probe.swift"

CALCULATOR_BUNDLE_ID="com.apple.calculator"
CHESS_BUNDLE_ID="com.apple.Chess"

MAKE_VIDEO=0

while [ $# -gt 0 ]; do
    case "$1" in
        --video)
            MAKE_VIDEO=1
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
    shift
done

RUN_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
RUN_ROOT="$REPO_ROOT/.artifacts/integration/$RUN_ID"
XCODE_ROOT="$REPO_ROOT/.artifacts/xcode-integration"
DERIVED_DATA="$XCODE_ROOT/DerivedData"
CLONED_PACKAGES="$XCODE_ROOT/SourcePackages"
MODULE_CACHE_ROOT="$XCODE_ROOT/ModuleCache"
CLANG_MODULE_CACHE="$MODULE_CACHE_ROOT/clang"
SWIFT_MODULE_CACHE="$MODULE_CACHE_ROOT/swift"
CONTEXT_FILE="$XCODE_ROOT/integration-context.env"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/ShortcutCycle.app"

LAUNCHED_SYSTEM_APPS=0
LAUNCHED_APP_PIDS=()

log() {
    echo "[integration] $*"
}

fail() {
    echo "[integration] $*" >&2
    exit 1
}

run_window_probe() {
    /usr/bin/env \
        CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE" \
        SWIFT_MODULE_CACHE_PATH="$SWIFT_MODULE_CACHE" \
        swift "$WINDOW_PROBE" "$@"
}

cleanup() {
    if [ "$LAUNCHED_SYSTEM_APPS" -eq 1 ] && [ ${#LAUNCHED_APP_PIDS[@]} -gt 0 ]; then
        kill "${LAUNCHED_APP_PIDS[@]}" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

app_is_running() {
    local bundle_id="$1"

    if run_window_probe running "$bundle_id" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

describe_running_app() {
    local bundle_id="$1"
    run_window_probe describe-running "$bundle_id" 2>/dev/null || true
}

append_launched_app_pids() {
    local bundle_id="$1"
    local pid

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        LAUNCHED_APP_PIDS+=("$pid")
    done < <(run_window_probe pids "$bundle_id" 2>/dev/null || true)
}

launch_and_wait_for_window() {
    local bundle_id="$1"

    /usr/bin/open -b "$bundle_id" >/dev/null 2>&1 || {
        fail "Required app with bundle ID $bundle_id could not be launched."
    }

    run_window_probe wait-visible-window "$bundle_id" 15 >/dev/null || {
        fail "Timed out waiting for a visible regular window for $bundle_id."
    }

    append_launched_app_pids "$bundle_id"
}

maybe_make_video() {
    local frames_dir="$RUN_ROOT/happy-path/frames"
    local output_path="$RUN_ROOT/happy-path/playback.mp4"

    if [ "$MAKE_VIDEO" -ne 1 ]; then
        return
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        log "Skipping video generation because ffmpeg is not available."
        return
    fi

    if ! find "$frames_dir" -name '*.png' -print -quit 2>/dev/null | grep -q .; then
        log "Skipping video generation because no PNG frames were captured."
        return
    fi

    ffmpeg -y \
        -framerate 1 \
        -pattern_type glob \
        -i "$frames_dir/*.png" \
        -pix_fmt yuv420p \
        "$output_path" >/dev/null 2>&1 || {
        log "ffmpeg was available but failed to generate $output_path."
        return
    }

    log "Generated playback video at $output_path"
}

mkdir -p "$RUN_ROOT" "$DERIVED_DATA" "$CLONED_PACKAGES" "$CLANG_MODULE_CACHE" "$SWIFT_MODULE_CACHE"

[ -f "$FIXTURE_PATH" ] || fail "Fixture not found at $FIXTURE_PATH"
[ -f "$WINDOW_PROBE" ] || fail "Window probe helper not found at $WINDOW_PROBE"

running_apps=()

if app_is_running "$CALCULATOR_BUNDLE_ID"; then
    running_apps+=("Calculator: $(describe_running_app "$CALCULATOR_BUNDLE_ID" | tr '\n' '; ' | sed 's/; $//')")
fi

if app_is_running "$CHESS_BUNDLE_ID"; then
    running_apps+=("Chess: $(describe_running_app "$CHESS_BUNDLE_ID" | tr '\n' '; ' | sed 's/; $//')")
fi

if [ ${#running_apps[@]} -gt 0 ]; then
    fail "Preflight failed because these apps still have a running process: ${running_apps[*]}. Closing the window is not always enough on macOS; fully quit the app and rerun."
fi

log "Launching Calculator and Chess for the happy-path run."
LAUNCHED_SYSTEM_APPS=1
launch_and_wait_for_window "$CALCULATOR_BUNDLE_ID"
launch_and_wait_for_window "$CHESS_BUNDLE_ID"
/usr/bin/osascript -e 'tell application id "com.apple.finder" to activate' >/dev/null 2>&1 || true

export SHORTCUTCYCLE_INTEGRATION_APP_PATH="$APP_PATH"
export SHORTCUTCYCLE_INTEGRATION_VALID_FIXTURE_PATH="$FIXTURE_PATH"
export SHORTCUTCYCLE_INTEGRATION_RUN_ROOT="$RUN_ROOT"
export SHORTCUTCYCLE_INTEGRATION_APP_BUNDLE_ID="$APP_BUNDLE_ID"

printf '%s\n' \
    "SHORTCUTCYCLE_INTEGRATION_APP_PATH=$APP_PATH" \
    "SHORTCUTCYCLE_INTEGRATION_VALID_FIXTURE_PATH=$FIXTURE_PATH" \
    "SHORTCUTCYCLE_INTEGRATION_RUN_ROOT=$RUN_ROOT" \
    "SHORTCUTCYCLE_INTEGRATION_APP_BUNDLE_ID=$APP_BUNDLE_ID" \
    > "$CONTEXT_FILE"

log "Artifacts will be written to $RUN_ROOT"

(
    cd "$PROJECT_ROOT"
    xcodebuild test \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -clonedSourcePackagesDirPath "$CLONED_PACKAGES" \
        -parallel-testing-enabled NO \
        SHORTCUTCYCLE_APP_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID"
)

maybe_make_video

log "Integration harness finished successfully."
log "Artifacts: $RUN_ROOT"
