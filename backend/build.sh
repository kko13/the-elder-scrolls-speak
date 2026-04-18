#!/usr/bin/env bash
# Builds three Lambda deployment zips into backend/dist/.
# Each zip contains both the per-Lambda package and the shared/ package
# plus its third-party dependencies.
#
# Usage:  cd backend && ./build.sh
set -euo pipefail

cd "$(dirname "$0")"
DIST="$(pwd)/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

build_one() {
  local name="$1"        # ingestion | tts | api
  local extra_deps="$2"  # space-separated pip args specific to this Lambda

  local stage
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' RETURN

  echo "==> building $name"
  pip install \
    --target "$stage" \
    --quiet \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.12 \
    --implementation cp \
    boto3 httpx selectolax rapidfuzz pydantic aws-lambda-powertools cryptography \
    $extra_deps

  cp -r "./$name"  "$stage/$name"
  cp -r "./shared" "$stage/shared"

  ( cd "$stage" && zip -qr "$DIST/$name.zip" . )
  echo "    wrote $DIST/$name.zip"
}

build_one ingestion ""
build_one tts ""
build_one api ""

echo "done."
