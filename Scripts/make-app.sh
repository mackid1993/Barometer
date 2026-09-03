#!/bin/sh

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"

version=$(tr -d '[:space:]' < VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || printf '1')
application_directory="$project_directory/dist/MenuBarStats.app"
contents_directory="$application_directory/Contents"
macos_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"

swift build -c release --product MenuBarStatsApp
binary_directory=$(swift build -c release --show-bin-path)

rm -rf "$application_directory"
mkdir -p "$macos_directory" "$resources_directory"
cp "$binary_directory/MenuBarStatsApp" "$macos_directory/MenuBarStats"

sed \
    -e "s/__VERSION__/$version/g" \
    -e "s/__BUILD__/$build/g" \
    Scripts/Info.plist > "$contents_directory/Info.plist"

find "$binary_directory" -maxdepth 1 -type d -name '*.bundle' -exec cp -R '{}' "$resources_directory/" ';'

codesign \
    --force \
    --sign - \
    --identifier net.brustein.MenuBarStats \
    "$application_directory"
