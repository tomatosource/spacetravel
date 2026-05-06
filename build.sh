#!/bin/bash
set -e

PRODUCT="SpaceTravel"
APP="${PRODUCT}.app"
BUILD_DIR=".build/release"

echo "Building ${PRODUCT}..."
swift build -c release

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "${BUILD_DIR}/${PRODUCT}" "${APP}/Contents/MacOS/"
cp "Info.plist" "${APP}/Contents/"

# Ad-hoc sign so macOS will run it and SMAppService works.
codesign -s - --force "${APP}"

echo ""
echo "Built ${APP}"
echo ""
echo "Steps:"
echo "  1. open ${APP}  (or move to /Applications first)"
echo "  2. Grant Accessibility: System Settings → Privacy & Security → Accessibility"
echo "  3. SpaceTravel appears in the menu bar — long-press Space to switch between Slack & iTerm2"
