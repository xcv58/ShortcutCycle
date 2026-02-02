#!/bin/sh
set -e

# Offset ensures Xcode Cloud build numbers stay above existing local builds.
# Adjust if needed — current local build is 8.
OFFSET=100
BUILD_NUMBER=$((CI_BUILD_NUMBER + OFFSET))

echo "Setting CURRENT_PROJECT_VERSION to $BUILD_NUMBER (CI_BUILD_NUMBER=$CI_BUILD_NUMBER + OFFSET=$OFFSET)"

cd "$CI_PRIMARY_REPOSITORY_PATH/ShortcutCycle"
agvtool new-version -all "$BUILD_NUMBER"
