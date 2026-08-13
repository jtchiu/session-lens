#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_icon="$repo_root/docs/design/sessionlens-icon-source.png"
resource_directory="$repo_root/Sources/SessionLens/Resources"
icon_png="$resource_directory/SessionLensIcon.png"
icon_icns="$resource_directory/SessionLens.icns"

test -f "$source_icon"
mkdir -p "$resource_directory"
cp "$source_icon" "$icon_png"

icon_temp_directory="$(mktemp -d "${TMPDIR:-/tmp}/sessionlens-icon.XXXXXX")"
trap 'rm -rf -- "$icon_temp_directory"' EXIT
iconset_directory="$icon_temp_directory/SessionLens.iconset"
mkdir -p "$iconset_directory"

for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$source_icon" \
    --out "$iconset_directory/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  /usr/bin/sips -z "$retina_size" "$retina_size" "$source_icon" \
    --out "$iconset_directory/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil -c icns "$iconset_directory" -o "$icon_icns"
test -f "$icon_png"
test -f "$icon_icns"
print "Built $icon_icns"
