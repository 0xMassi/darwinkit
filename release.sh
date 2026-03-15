#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NPM_ONLY=false
SKIP_NPM=false
BUILD_ONLY=false
VERSION=""
NPM_OTP=""

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --npm-only)    NPM_ONLY=true ;;
    --skip-npm)    SKIP_NPM=true ;;
    --build-only)  BUILD_ONLY=true ;;
    --otp=*)       NPM_OTP="${arg#--otp=}" ;;
    --*)           echo "Unknown flag: $arg"; exit 1 ;;
    *)             VERSION="$arg" ;;
  esac
done

if [ "$BUILD_ONLY" = false ] && [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--npm-only] [--skip-npm] [--build-only] [--otp=CODE]"
  echo ""
  echo "  --build-only Build Swift binary + TS SDK only (no release, no publish)"
  echo "  --npm-only   Only publish to npm (skip GitHub release)"
  echo "  --skip-npm   Only create GitHub release (skip npm publish)"
  echo "  --otp=CODE   npm OTP code for 2FA (or pass NPM_PUBLISH_TOKEN env var)"
  exit 1
fi

SWIFT_DIR="$SCRIPT_DIR/packages/darwinkit-swift"
SDK_DIR="$SCRIPT_DIR/packages/darwinkit"
TARBALL="darwinkit-macos-universal.tar.gz"
GH_REPO="genesiscz/darwinkit-swift"

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

# ── Build-only mode ───────────────────────────────────
if [ "$BUILD_ONLY" = true ]; then
  echo "Copying binary to SDK..."
  mkdir -p "$SDK_DIR/bin"
  cp "$BINARY" "$SDK_DIR/bin/darwinkit"
  chmod 755 "$SDK_DIR/bin/darwinkit"

  echo "Building TypeScript SDK..."
  cd "$SDK_DIR"
  bun install --frozen-lockfile 2>/dev/null || bun install
  bun run build

  echo "Build complete. Binary: $SDK_DIR/bin/darwinkit"
  echo "To link into another project: cd $SDK_DIR && bun link"
  exit 0
fi

# ── GitHub release ──────────────────────────────────────
if [ "$NPM_ONLY" = false ]; then
  echo "Creating tarball..."
  tar -czf "$SCRIPT_DIR/$TARBALL" -C "$SWIFT_DIR/.build/apple/Products/Release" darwinkit

  echo "Creating GitHub release $VERSION..."
  gh release create "$VERSION" "$SCRIPT_DIR/$TARBALL" \
    --repo "$GH_REPO" \
    --title "$VERSION" \
    --generate-notes

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

    echo "Published @genesiscz/darwinkit@$VERSION to npm."
  else
    echo "Skipping npm publish."
  fi
fi

echo "Done."
