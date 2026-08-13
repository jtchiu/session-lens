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

# Finder/FileProvider can attach metadata to an app copied into a synced
# Documents folder. Verify the exact signed contents from a metadata-free copy
# so the check stays read-only and is not racy with the host's file provider.
verification_directory="$(mktemp -d "${TMPDIR:-/tmp}/sessionlens-verify.XXXXXX")"
trap 'rm -rf -- "$verification_directory"' EXIT
verification_app="$verification_directory/SessionLens.app"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
  "$app_path" "$verification_app"
/usr/bin/codesign --verify --deep --strict "$verification_app"

print "PASS: $app_path"
