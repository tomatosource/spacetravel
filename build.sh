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

# Sign with a persistent local cert so macOS doesn't revoke Accessibility on each build.
# One-time setup: Keychain Access → Certificate Assistant → Create a Certificate
#   Name: SpaceTravel Dev | Identity Type: Self Signed Root | Type: Code Signing
CERT="SpaceTravel Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${CERT}\""; then
    codesign -s "${CERT}" --force "${APP}"
else
    echo "⚠️  '${CERT}' cert not found — falling back to ad-hoc signing."
    echo "   You'll need to re-grant Accessibility after each build until the cert exists."
    codesign -s - --force "${APP}"
fi

echo ""
echo "Built ${APP}"
echo ""
echo "Steps:"
echo "  1. open ${APP}  (or move to /Applications first)"
echo "  2. Grant Accessibility: System Settings → Privacy & Security → Accessibility"
echo "  3. SpaceTravel appears in the menu bar — long-press Space to switch between Slack & iTerm2"
