#!/bin/sh

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"

version=$(tr -d '[:space:]' < VERSION)
application_path=${1:-dist/Barometer.app}
output_path=${2:-dist/Barometer-$version.dmg}

if [ ! -d "$application_path" ]; then
    echo "Barometer app bundle not found at $application_path" >&2
    exit 1
fi

staging_directory=$(mktemp -d "${TMPDIR:-/tmp}/barometer-dmg.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT HUP INT TERM

ditto "$application_path" "$staging_directory/Barometer.app"
ln -s /Applications "$staging_directory/Applications"
mkdir -p "$(dirname -- "$output_path")"
rm -f "$output_path"

diskutil image create from \
    --format UDZO \
    --volumeName Barometer \
    "$staging_directory" \
    "$output_path"

hdiutil verify "$output_path"
echo "$output_path"
