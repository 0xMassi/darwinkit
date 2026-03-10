#!/bin/bash
set -euo pipefail

INSTALL_DIR="${DARWINKIT_INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://github.com/genesiscz/darwinkit-swift.git"

mkdir -p "$INSTALL_DIR"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning darwinkit-swift..."
git clone --depth 1 "$REPO_URL" "$TMPDIR/darwinkit-swift"

cd "$TMPDIR/darwinkit-swift/packages/darwinkit-swift"

echo "Building universal binary (this may take a minute)..."
swift build -c release --arch arm64 --arch x86_64

cp .build/apple/Products/Release/darwinkit "$INSTALL_DIR/darwinkit"
echo "darwinkit installed to $INSTALL_DIR/darwinkit"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "Add to your shell profile:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
