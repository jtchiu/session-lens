#!/bin/zsh
set -euo pipefail

sessionlens_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR="$sessionlens_developer_dir"

exec /usr/bin/xcrun swift test \
  -Xswiftc -F \
  -Xswiftc "$sessionlens_developer_dir/Library/Developer/Frameworks" \
  "$@"
