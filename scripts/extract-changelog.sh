#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 VERSION" >&2
    exit 2
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid changelog version: $VERSION" >&2
    exit 2
fi

if [[ ! -f CHANGELOG.md ]]; then
    echo "CHANGELOG.md not found." >&2
    exit 1
fi

awk -v version="$VERSION" '
BEGIN {
    heading = "## [" version "]"
    found = 0
}
{
    if (!found &&
        index($0, heading) == 1 &&
        (length($0) == length(heading) ||
         substr($0, length(heading) + 1, 1) ~ /[[:space:]]/)) {
        found = 1
        next
    }

    if (found && $0 ~ /^## \[/) {
        exit
    }

    if (found && $0 !~ /^\[[^]]+\]:[[:space:]]/) {
        print
    }
}
END {
    if (!found) {
        exit 1
    }
}
' CHANGELOG.md
