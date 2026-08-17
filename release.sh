#!/bin/zsh
# Full release: universal build, Developer ID signing, notarization,
# GitHub release, and Homebrew cask update.
#   ./release.sh 1.0.1
set -e
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
TAP_DIR="${TAP_DIR:-$HOME/htdocs/homebrew-tap}"
CASK="$TAP_DIR/Casks/kitty-taskbar.rb"

VERSION="$VERSION" ./build.sh --release

ZIP="KittyTaskbar-${VERSION}.zip"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

git tag "v${VERSION}" 2>/dev/null || true
git push origin "v${VERSION}"
gh release create "v${VERSION}" "$ZIP" --title "KittyTaskbar ${VERSION}" --generate-notes

sed -i '' \
    -e "s/^  version .*/  version \"${VERSION}\"/" \
    -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" \
    "$CASK"
git -C "$TAP_DIR" commit -am "kitty-taskbar ${VERSION}"
git -C "$TAP_DIR" push

echo "Released v${VERSION} and updated the Homebrew cask."
