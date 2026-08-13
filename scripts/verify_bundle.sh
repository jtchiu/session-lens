#!/bin/zsh
set -euo pipefail

app_path="${1:?app path required}"

test -x "$app_path/Contents/MacOS/SessionLens"
test -x "$app_path/Contents/Helpers/SessionLensClaudeBridge"
test -f "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_path/Contents/Info.plist" | grep -qx true
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist" | grep -qx 14.0
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app_path/Contents/Info.plist" | grep -qx SessionLens
test -f "$app_path/Contents/Resources/SessionLens.icns"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist" >/dev/null

# Finder/FileProvider can attach these attributes to an app copied into a
# synced Documents folder. They are not part of the signed bundle contents.
for sessionlens_attribute in \
  com.apple.FinderInfo \
  com.apple.fileprovider.fpfs#P \
  com.apple.provenance \
  com.apple.quarantine \
  com.apple.ResourceFork; do
  /usr/bin/xattr -d "$sessionlens_attribute" "$app_path" 2>/dev/null || true
done

/usr/bin/codesign --verify --deep --strict "$app_path"

print "PASS: $app_path"
