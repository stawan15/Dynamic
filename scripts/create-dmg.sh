#!/bin/zsh

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/Dynamix.app /path/to/Dynamix.dmg" >&2
    exit 64
fi

app_path="$1"
output_path="$2"

if [[ ! -d "$app_path" ]]; then
    echo "App not found: $app_path" >&2
    exit 66
fi

staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT

ditto "$app_path" "$staging_directory/Dynamix.app"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
    -volname "Dynamix" \
    -srcfolder "$staging_directory" \
    -fs APFS \
    -format ULFO \
    -ov \
    "$output_path"
