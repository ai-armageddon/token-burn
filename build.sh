#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
bundle="$PWD/dist/Token Burn.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
ditto "$bin_dir/TokenBurn_TokenBurn.bundle" "$bundle/Contents/Resources/TokenBurn_TokenBurn.bundle"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp "$bin_dir/TokenBurn" "$bundle/Contents/MacOS/TokenBurn"
strip -S -x "$bundle/Contents/MacOS/TokenBurn"
codesign --force --sign - "$bundle"
echo "$bundle"
