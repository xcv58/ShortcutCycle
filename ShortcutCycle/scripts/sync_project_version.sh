#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_FILE="$REPO_ROOT/ShortcutCycle.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
  echo "error: project file not found: $PROJECT_FILE" >&2
  exit 1
fi

CURRENT_BUILD=$(
  sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);/\1/p' "$PROJECT_FILE" \
    | head -n 1
)

if [ -z "$CURRENT_BUILD" ]; then
  CURRENT_BUILD=0
fi

if [ -n "${SC_BUILD_NUMBER:-}" ]; then
  TARGET_BUILD="$SC_BUILD_NUMBER"
  BUILD_SOURCE="SC_BUILD_NUMBER"
elif [ -n "${CI_BUILD_NUMBER:-}" ]; then
  CI_OFFSET="${SC_CI_BUILD_OFFSET:-1000}"
  case "$CI_OFFSET" in
    ''|*[!0-9]*)
      echo "error: SC_CI_BUILD_OFFSET must be numeric, got: $CI_OFFSET" >&2
      exit 1
      ;;
  esac
  TARGET_BUILD=$((CI_BUILD_NUMBER + CI_OFFSET))
  BUILD_SOURCE="CI_BUILD_NUMBER + SC_CI_BUILD_OFFSET"
else
  TARGET_BUILD=$((CURRENT_BUILD + 1))
  BUILD_SOURCE="current + 1"
fi

case "$TARGET_BUILD" in
  ''|*[!0-9]*)
    echo "error: build number must be numeric, got: $TARGET_BUILD" >&2
    exit 1
    ;;
esac

if [ -n "$CURRENT_BUILD" ] && [ "$TARGET_BUILD" -le "$CURRENT_BUILD" ]; then
  TARGET_BUILD=$((CURRENT_BUILD + 1))
  BUILD_SOURCE="$BUILD_SOURCE (monotonic guard)"
fi

TARGET_MARKETING="${SC_MARKETING_VERSION:-}"

if [ "${SC_DRY_RUN:-0}" = "1" ]; then
  echo "sync_project_version (dry run)"
  echo "  current build: $CURRENT_BUILD"
  echo "  target build:  $TARGET_BUILD"
  echo "  source:        $BUILD_SOURCE"
  if [ -n "$TARGET_MARKETING" ]; then
    echo "  target marketing version: $TARGET_MARKETING"
  fi
  exit 0
fi

perl -i -pe "s/(CURRENT_PROJECT_VERSION = )[^;]+;/\${1}$TARGET_BUILD;/g" "$PROJECT_FILE"

if [ -n "$TARGET_MARKETING" ]; then
  perl -i -pe "s/(MARKETING_VERSION = )[^;]+;/\${1}$TARGET_MARKETING;/g" "$PROJECT_FILE"
fi

echo "Synced project version:"
echo "  CURRENT_PROJECT_VERSION=$TARGET_BUILD"
echo "  source=$BUILD_SOURCE"
if [ -n "$TARGET_MARKETING" ]; then
  echo "  MARKETING_VERSION=$TARGET_MARKETING"
fi
