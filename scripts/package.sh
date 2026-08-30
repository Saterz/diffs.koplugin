#!/bin/bash

set -euo pipefail

PLUGIN_VERSION="${1:-development}"
PLUGIN_NAME="$(basename "$PWD")"

if [[ ! "$PLUGIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] &&
    [[ "$PLUGIN_VERSION" != "development" ]]; then
    echo "Invalid plugin version: $PLUGIN_VERSION" >&2
    exit 1
fi

rm -rf "dist/$PLUGIN_NAME"
mkdir -p "dist/$PLUGIN_NAME"

rsync -a \
    --include="*/" \
    --include="*.lua" \
    --exclude="*" \
    src/ "dist/$PLUGIN_NAME/"
cp README.md "dist/$PLUGIN_NAME/"

sed -i -E \
    "s/^([[:space:]]*version[[:space:]]*=[[:space:]]*)\"[^\"]+\"/\\1\"$PLUGIN_VERSION\"/" \
    "dist/$PLUGIN_NAME/_meta.lua"

rm -f "$PLUGIN_NAME.zip"
(cd dist && zip -qr "../$PLUGIN_NAME.zip" "$PLUGIN_NAME")
