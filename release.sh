#!/bin/bash
# Build Clack, sign it with Developer ID, notarize with Apple, staple, package
# a signed DMG into dist/, and (unless NO_PUBLISH=1) tag + publish a GitHub release.
#
#   ./release.sh 1.0 "What changed"
#   NO_PUBLISH=1 ./release.sh 1.0          # build + notarize + DMG only
#   RESUME=1 ./release.sh 1.0 "notes"      # keep waiting on the same upload
#
# Notarization goes through Xcode's signed-in account for team CH6CSBA54G
# (Xcode → Settings → Accounts); no notarytool profile or password needed.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTES="${2:-}"
[ -n "$VERSION" ] || { echo "usage: ./release.sh <version> [notes]"; exit 1; }

die() { echo "✗ $*" >&2; exit 1; }
say() { echo "▸ $*"; }

TEAM_ID="CH6CSBA54G"
APP_NAME="Clack"
REPO="sammystech/Clack"
BUILD_DIR=".release-build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
WAIT_MIN="${NOTARY_WAIT_MIN:-30}"

SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application:.*($TEAM_ID)" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)
[ -n "$SIGN_IDENTITY" ] || die "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain."
echo "  signing as: $SIGN_IDENTITY"

if [ "${RESUME:-}" = 1 ]; then
    [ -d "$ARCHIVE" ] || die "Nothing to resume: no archive at $ARCHIVE"
    say "Resuming $VERSION: waiting on the upload already with Apple…"
else
    say "Setting version $VERSION…"
    BUILD=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: "([0-9]+)"/\1/p' project.yml)
    sed -i '' -E "s/^( *MARKETING_VERSION: )\".*\"/\1\"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION: )\".*\"/\1\"$((BUILD + 1))\"/" project.yml

    say "Archiving…"
    xcodegen generate >/dev/null
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        -archivePath "$ARCHIVE" -derivedDataPath "$BUILD_DIR/dd" -allowProvisioningUpdates archive \
        > "$BUILD_DIR/archive.log" 2>&1 \
        || { grep -E "error:" "$BUILD_DIR/archive.log" | sort -u | head -20; die "Archive failed. Log: $BUILD_DIR/archive.log"; }

    say "Signing with Developer ID and uploading for notarization…"
    cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -exportPath "$BUILD_DIR/upload-receipt" -allowProvisioningUpdates > "$BUILD_DIR/export.log" 2>&1 \
        || { grep -iE "error" "$BUILD_DIR/export.log" | sort -u | head -20; die "Export/upload failed. Log: $BUILD_DIR/export.log"; }
    echo "  uploaded; waiting for Apple"
fi

NOTARIZED="$BUILD_DIR/notarized"
rm -rf "$NOTARIZED"
TRIES=$(( WAIT_MIN * 60 / 25 ))
for attempt in $(seq 1 "$TRIES"); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$NOTARIZED" \
            > "$BUILD_DIR/notarize.log" 2>&1; then
        echo "  notarized after ~$((attempt * 25))s"
        break
    fi
    grep -q "No Accounts" "$BUILD_DIR/notarize.log" && die "Xcode is signed out. Sign in (team $TEAM_ID), then RESUME=1 ./release.sh $VERSION"
    if grep -qiE "invalid|rejected|not accepted" "$BUILD_DIR/notarize.log"; then
        grep -iE "error|invalid|reject" "$BUILD_DIR/notarize.log" | head -10
        die "Apple rejected the submission. Details: Xcode → Window → Organizer."
    fi
    [ "$attempt" -eq "$TRIES" ] && die "Not notarized after $WAIT_MIN minutes. Resume: RESUME=1 ./release.sh $VERSION"
    sleep 25
done

APP="$NOTARIZED/$APP_NAME.app"
[ -d "$APP" ] || die "Notarized app not found at $APP"
xcrun stapler validate "$APP" >/dev/null 2>&1 || die "No notarization ticket stapled to the app."
ASSESS=$(spctl -a -t exec -vv "$APP" 2>&1 || true)
echo "$ASSESS" | grep -q "source=Notarized Developer ID" || { echo "$ASSESS"; die "Gatekeeper rejects the app."; }
echo "  Gatekeeper: accepted (Notarized Developer ID)"
codesign --verify --deep --strict "$APP" || die "Bundle signature doesn't verify."

say "Packaging the DMG…"
mkdir -p dist
DMG="dist/$APP_NAME.dmg"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG" || die "Couldn't sign the DMG."
ls -lh "$DMG"

if [ "${NO_PUBLISH:-}" = 1 ]; then
    echo "✓ Built, notarized and packaged $VERSION (not published)."
    echo "  Install: rm -rf /Applications/$APP_NAME.app && cp -R \"$APP\" /Applications/"
    exit 0
fi

say "Committing, tagging, publishing…"
git add -A
git commit -m "Release v$VERSION" || echo "(nothing to commit)"
git tag -f "v$VERSION"
git push origin HEAD
git push -f origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "$APP_NAME $VERSION" \
    --notes "${NOTES:-See the commit history for what changed.}" \
    || gh release upload "v$VERSION" "$DMG" --clobber --repo "$REPO"
echo "✓ Released v$VERSION"
