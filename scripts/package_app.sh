#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sessionlens_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR="$sessionlens_developer_dir"

swift_command=(/usr/bin/xcrun swift)
"${swift_command[@]}" build -c release --product SessionLens
"${swift_command[@]}" build -c release --product SessionLensClaudeBridge
"$repo_root/scripts/build_icon.sh"

release_bin_directory="$("${swift_command[@]}" build -c release --show-bin-path)"
sessionlens_stage_directory="$(mktemp -d "${TMPDIR:-/tmp}/sessionlens-package.XXXXXX")"
trap 'rm -rf -- "$sessionlens_stage_directory"' EXIT
staged_app_path="$sessionlens_stage_directory/SessionLens.app"
staged_contents_path="$staged_app_path/Contents"
app_path="$repo_root/dist/SessionLens.app"

mkdir -p "$staged_contents_path/MacOS" "$staged_contents_path/Helpers" \
  "$staged_contents_path/Resources"

cp "$release_bin_directory/SessionLens" \
  "$staged_contents_path/MacOS/SessionLens"
cp "$release_bin_directory/SessionLensClaudeBridge" \
  "$staged_contents_path/Helpers/SessionLensClaudeBridge"
cp "$repo_root/Resources/Info.plist" "$staged_contents_path/Info.plist"
cp "$repo_root/Sources/SessionLens/Resources/SessionLens.icns" \
  "$staged_contents_path/Resources/SessionLens.icns"

chmod 755 "$staged_contents_path/MacOS/SessionLens"
chmod 755 "$staged_contents_path/Helpers/SessionLensClaudeBridge"

/usr/bin/xattr -cr "$staged_app_path" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$staged_app_path"
/usr/bin/codesign --verify --deep --strict "$staged_app_path"

mkdir -p "$repo_root/dist"
if [[ -e "$app_path" ]]; then
  rm -rf -- "$app_path"
fi
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
  "$staged_app_path" "$app_path"
for sessionlens_attribute in \
  com.apple.FinderInfo \
  com.apple.fileprovider.fpfs#P \
  com.apple.provenance \
  com.apple.quarantine \
  com.apple.ResourceFork; do
  /usr/bin/xattr -d "$sessionlens_attribute" "$app_path" 2>/dev/null || true
done

"$repo_root/scripts/verify_bundle.sh" "$app_path"
print "Packaged $app_path"
