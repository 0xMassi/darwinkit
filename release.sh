#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NPM_ONLY=false
SKIP_NPM=false
VERSION=""
NPM_OTP=""

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --npm-only)  NPM_ONLY=true ;;
    --skip-npm)  SKIP_NPM=true ;;
    --otp=*)     NPM_OTP="${arg#--otp=}" ;;
    --*)         echo "Unknown flag: $arg"; exit 1 ;;
    *)           VERSION="$arg" ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--npm-only] [--skip-npm] [--otp=CODE]"
  echo ""
  echo "  --npm-only   Only publish to npm (skip GitHub release)"
  echo "  --skip-npm   Only create GitHub release (skip npm publish)"
  echo "  --otp=CODE   npm OTP code for 2FA (or pass NPM_PUBLISH_TOKEN env var)"
  exit 1
fi

SWIFT_DIR="$SCRIPT_DIR/packages/darwinkit-swift"
SDK_DIR="$SCRIPT_DIR/packages/darwinkit"
TARBALL="darwinkit-macos-universal.tar.gz"

# ── Build universal binary ──────────────────────────────
if [ "$NPM_ONLY" = false ]; then
  echo "Building universal binary..."
  cd "$SWIFT_DIR"
  swift build -c release --arch arm64 --arch x86_64
  cd "$SCRIPT_DIR"
fi

BINARY="$SWIFT_DIR/.build/apple/Products/Release/darwinkit"

if [ ! -f "$BINARY" ]; then
  echo "Error: Binary not found at $BINARY"
  echo "Run without --npm-only first, or build manually."
  exit 1
fi

# ── GitHub release ──────────────────────────────────────
if [ "$NPM_ONLY" = false ]; then
  echo "Creating tarball..."
  tar -czf "$SCRIPT_DIR/$TARBALL" -C "$SWIFT_DIR/.build/apple/Products/Release" darwinkit

  echo "Creating GitHub release $VERSION..."
  if ! gh release create "$VERSION" "$SCRIPT_DIR/$TARBALL" \
    --title "$VERSION" \
    --generate-notes 2>/dev/null; then
    echo "gh release create failed, falling back to API..."
    gh api repos/{owner}/{repo}/releases \
      -f tag_name="$VERSION" \
      -f name="$VERSION" \
      -F generate_release_notes=true > /dev/null
    gh release upload "$VERSION" "$SCRIPT_DIR/$TARBALL"
  fi

  rm "$SCRIPT_DIR/$TARBALL"
  echo "GitHub release $VERSION created."
fi

# ── npm publish ─────────────────────────────────────────
if [ "$SKIP_NPM" = false ]; then
  read -p "Publish @genesiscz/darwinkit@$VERSION to npm? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Bundling binary into npm package..."
    mkdir -p "$SDK_DIR/bin"
    cp "$BINARY" "$SDK_DIR/bin/darwinkit"
    chmod 755 "$SDK_DIR/bin/darwinkit"

    echo "Building TypeScript SDK..."
    cd "$SDK_DIR"
    bun install --frozen-lockfile 2>/dev/null || bun install
    bun run build

    # Update version to match release
    npm version "$VERSION" --no-git-tag-version --allow-same-version

    # Build publish command
    PUBLISH_CMD="npm publish --access public"
    if [ -n "$NPM_OTP" ]; then
      PUBLISH_CMD="$PUBLISH_CMD --otp $NPM_OTP"
    fi

    echo "Publishing to npm..."
    $PUBLISH_CMD

    # Clean up bundled binary from source tree
    rm -rf "$SDK_DIR/bin/darwinkit"

    echo "Published @genesiscz/darwinkit@$VERSION to npm."
  else
    echo "Skipping npm publish."
  fi
fi

echo "Done."
