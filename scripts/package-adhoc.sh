#!/bin/zsh
# Packages the Release build into a local DMG and ZIP.
#
# This is not scripts/release.sh: it needs no Developer ID certificate and no notarization account, so the result is
# ad-hoc signed and Gatekeeper will warn anyone else who opens it. It exists so a local build can be handed to someone
# with a "right-click, Open" and nothing else.
#
# Two things differ from a Developer ID build and both are required:
#   - no hardened runtime. Library validation matches Team IDs, and an ad-hoc signature has none, so the hardened
#     runtime refuses to load the Sparkle framework the bundle ships. The app crashes at launch without this.
#   - `disable-library-validation`, which makes the same point explicitly.
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ARCHIVE="${2:?usage: package-adhoc.sh <project-dir> <path/to/Compositor.xcarchive>}"
APP=Compositor
WORK=/tmp/compositor-package
DIST="$PROJECT_DIR/dist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$ARCHIVE/Products/Applications/$APP.app/Contents/Info.plist")
NAME="$APP-$VERSION-zh-Hans"

rm -rf "$WORK"; mkdir -p "$WORK" "$DIST"

echo "==> Staging $APP $VERSION"
ditto "$ARCHIVE/Products/Applications/$APP.app" "$WORK/stage/$APP.app"
STAGED="$WORK/stage/$APP.app"

cat > "$WORK/adhoc.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>com.wonderassembly.compositor-spks</string>
        <string>com.wonderassembly.compositor-spki</string>
    </array>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Signing ad-hoc"
codesign --force --deep --sign - "$STAGED/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --entitlements "$WORK/adhoc.entitlements" "$STAGED/Contents/MacOS/$APP"
codesign --force --sign - --entitlements "$WORK/adhoc.entitlements" "$STAGED"
codesign --verify --deep --strict --verbose=1 "$STAGED"

echo "==> Building the DMG"
# /Volumes is read-only under the harness sandbox, so the writable image is mounted inside /tmp.
hdiutil create -volname "$APP" -size 90m -fs HFS+ -type SPARSE -ov "$WORK/rw.sparseimage" >/dev/null
hdiutil attach "$WORK/rw.sparseimage" -nobrowse -noverify -mountpoint "$WORK/mnt" >/dev/null
cp -R "$STAGED" "$WORK/mnt/"
ln -s /Applications "$WORK/mnt/Applications"
ASSETS="$PROJECT_DIR/scripts/dmg"
if [[ -f "$ASSETS/dmg-bg.jpg" && -f "$ASSETS/dmg-bg-retina.jpg" ]]; then
  mkdir -p "$WORK/mnt/.background"
  sips -s format png -s dpiWidth 72 -s dpiHeight 72 "$ASSETS/dmg-bg.jpg" --out "$WORK/bg.png" >/dev/null
  sips -s format png -s dpiWidth 144 -s dpiHeight 144 "$ASSETS/dmg-bg-retina.jpg" --out "$WORK/bg@2x.png" >/dev/null
  tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/mnt/.background/background.tiff" >/dev/null
fi
# Finder scripting is blocked in this sandbox, so the window layout is written straight into .DS_Store.
python3 "$PROJECT_DIR/scripts/dmg-layout.py" "$WORK/mnt/.DS_Store"
sync
hdiutil detach "$WORK/mnt" >/dev/null
hdiutil convert "$WORK/rw.sparseimage" -format UDZO -imagekey zlib-level=9 -o "$DIST/$NAME.dmg" >/dev/null

echo "==> Building the ZIP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED" "$DIST/$NAME.zip"

echo "==> Checksums"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt)
echo "==> Done: $DIST/$NAME.dmg"
