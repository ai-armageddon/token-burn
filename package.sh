#!/bin/zsh
# Build a drag-to-Applications DMG and cask. A GitHub project URL selects
# a hosted release asset; the default cask reads the DMG from the tap checkout.
set -euo pipefail
cd "${0:A:h}"
if (( $# > 1 )); then
    echo "Usage: ./package.sh [https://github.com/OWNER/REPO]" >&2
    exit 2
fi
project_url="${1:-}"
if [[ -n "$project_url" && ! "$project_url" =~ '^https://github\.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$' ]]; then
    echo "Use the GitHub project URL without a trailing slash." >&2
    exit 2
fi

./build.sh
bundle="$PWD/dist/Token Burn.app"
codesign --verify --deep --strict "$bundle"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$bundle/Contents/Info.plist")
arch=$(lipo -archs "$bundle/Contents/MacOS/TokenBurn")
case "$arch" in
    arm64) brew_arch=arm64 ;;
    x86_64) brew_arch=intel ;;
    *) echo "Unexpected build architecture: $arch" >&2; exit 1 ;;
esac
asset="Token-Burn-$version-$arch.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/image"
/usr/bin/ditto --noextattr --norsrc "$bundle" "$stage/image/Token Burn.app"
ln -s /Applications "$stage/image/Applications"
hdiutil create -quiet -volname "Token Burn" -fs HFS+ -format UDZO -srcfolder "$stage/image" "$stage/$asset"
mv "$stage/$asset" "dist/$asset"
echo "$PWD/dist/$asset"

checksum=$(shasum -a 256 "dist/$asset" | cut -d' ' -f1)
mkdir -p dist/Casks
{
    cat <<CASK
cask "token-burn" do
  version "$version"
  sha256 "$checksum"

CASK
    if [[ -n "$project_url" ]]; then
        echo "  url \"$project_url/releases/download/v#{version}/Token-Burn-#{version}-$arch.dmg\""
    else
        # A local tap can keep the DMG alongside Casks/. No machine path is embedded.
        printf '  url "file://#{URI::RFC2396_PARSER.escape(File.expand_path("../%s", __dir__))}"\n' "$asset"
    fi
    echo '  name "Token Burn"'
    echo '  desc "Floating deck of AI subscription allowances"'
    if [[ -n "$project_url" ]]; then
        echo "  homepage \"$project_url\""
    fi
    cat <<CASK

  depends_on macos: ">= :sonoma"
  depends_on arch: :$brew_arch

  app "Token Burn.app"
end
CASK
} > "$stage/token-burn.rb"
mv "$stage/token-burn.rb" dist/Casks/token-burn.rb
echo "$PWD/dist/Casks/token-burn.rb"
