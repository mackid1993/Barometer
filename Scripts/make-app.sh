#!/bin/sh

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"

version=${BAROMETER_VERSION:-$(tr -d '[:space:]' < VERSION)}
build=$(git rev-list --count HEAD 2>/dev/null || printf '1')
application_directory="$project_directory/dist/Barometer.app"
contents_directory="$application_directory/Contents"
macos_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Barometer version '$version' is not major.minor.patch" >&2
    exit 1
fi

swift build -c release --product Barometer
binary_directory=$(swift build -c release --show-bin-path)

rm -rf "$application_directory"
mkdir -p "$macos_directory" "$resources_directory"
cp "$binary_directory/Barometer" "$macos_directory/Barometer"
cp Resources/Barometer.icns "$resources_directory/Barometer.icns"

sed \
    -e "s/__VERSION__/$version/g" \
    -e "s/__BUILD__/$build/g" \
    Scripts/Info.plist > "$contents_directory/Info.plist"

find "$binary_directory" -maxdepth 1 -type d -name '*.bundle' -exec cp -R '{}' "$resources_directory/" ';'

signing_identity=${CODESIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1)
fi

if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ]; then
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        --identifier com.barometer.app \
        --entitlements Scripts/Barometer.entitlements \
        "$application_directory"
else
    echo "No Developer ID Application identity found; using an ad-hoc development signature." >&2
    codesign \
        --force \
        --sign - \
        --identifier com.barometer.app \
        --entitlements Scripts/Barometer.entitlements \
        "$application_directory"
fi

bundle_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$contents_directory/Info.plist")
bundle_executable=$(plutil -extract CFBundleExecutable raw -o - "$contents_directory/Info.plist")
bundle_version=$(plutil -extract CFBundleShortVersionString raw -o - "$contents_directory/Info.plist")
executable_count=$(find "$contents_directory" -type f -perm -111 | wc -l | tr -d '[:space:]')

if [ "$bundle_identifier" != "com.barometer.app" ] || [ "$bundle_executable" != "Barometer" ]; then
    echo "Barometer bundle identity validation failed" >&2
    exit 1
fi

if [ "$bundle_version" != "$version" ]; then
    echo "Barometer version stamping failed: expected $version, found $bundle_version" >&2
    exit 1
fi

if [ "$executable_count" -ne 1 ] || [ ! -x "$macos_directory/Barometer" ]; then
    echo "Barometer.app must contain exactly one executable: Contents/MacOS/Barometer" >&2
    exit 1
fi

codesign --verify --strict "$application_directory"

# A valid signature alone does not prove that hardened-runtime privacy prompts are permitted.
signed_entitlements="$project_directory/dist/signed-entitlements.plist"
codesign --display --entitlements - --xml "$application_directory" > "$signed_entitlements"
calendar_access=$(plutil -extract 'com\.apple\.security\.personal-information\.calendars' raw -o - \
    "$signed_entitlements")
if [ "$calendar_access" != "true" ]; then
    echo "Barometer.app is missing its Calendar access entitlement" >&2
    exit 1
fi
location_access=$(plutil -extract 'com\.apple\.security\.personal-information\.location' raw -o - \
    "$signed_entitlements")
if [ "$location_access" != "true" ]; then
    echo "Barometer.app is missing its Location access entitlement" >&2
    exit 1
fi
