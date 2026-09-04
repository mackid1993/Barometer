#!/bin/sh

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"

version=$(tr -d '[:space:]' < VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || printf '1')
application_directory="$project_directory/dist/Barometer.app"
contents_directory="$application_directory/Contents"
macos_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"

swift build -c release --product Barometer
binary_directory=$(swift build -c release --show-bin-path)

rm -rf "$application_directory"
mkdir -p "$macos_directory" "$resources_directory"
cp "$binary_directory/Barometer" "$macos_directory/Barometer"

sed \
    -e "s/__VERSION__/$version/g" \
    -e "s/__BUILD__/$build/g" \
    Scripts/Info.plist > "$contents_directory/Info.plist"

find "$binary_directory" -maxdepth 1 -type d -name '*.bundle' -exec cp -R '{}' "$resources_directory/" ';'

codesign \
    --force \
    --sign - \
    --identifier com.barometer.app \
    "$application_directory"

bundle_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$contents_directory/Info.plist")
bundle_executable=$(plutil -extract CFBundleExecutable raw -o - "$contents_directory/Info.plist")
executable_count=$(find "$contents_directory" -type f -perm -111 | wc -l | tr -d '[:space:]')

if [ "$bundle_identifier" != "com.barometer.app" ] || [ "$bundle_executable" != "Barometer" ]; then
    echo "Barometer bundle identity validation failed" >&2
    exit 1
fi

if [ "$executable_count" -ne 1 ] || [ ! -x "$macos_directory/Barometer" ]; then
    echo "Barometer.app must contain exactly one executable: Contents/MacOS/Barometer" >&2
    exit 1
fi

codesign --verify --strict "$application_directory"
