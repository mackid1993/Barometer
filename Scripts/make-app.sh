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

# Opt-in prototype: a second bundle that publishes one status item under its own identifier.
# A menu bar manager's concealment allowlist is keyed by the publishing process's bundle ID,
# so independent hiding requires an independent bundle. Off by default, which keeps the
# one-executable identity invariant below in force for every ordinary build.
if [ "${BAROMETER_HELPER_PROTOTYPE:-0}" = "1" ]; then
    swift build -c release --product BarometerGPUHelper
    helper_app_directory="$contents_directory/Library/LoginItems/Barometer GPU.app"
    helper_macos_directory="$helper_app_directory/Contents/MacOS"
    mkdir -p "$helper_macos_directory"
    cp "$binary_directory/BarometerGPUHelper" "$helper_macos_directory/BarometerGPUHelper"
    sed \
        -e "s/__VERSION__/$version/g" \
        -e "s/__BUILD__/$build/g" \
        Scripts/Helper-GPU-Info.plist > "$helper_app_directory/Contents/Info.plist"
fi

signing_identity=${CODESIGN_IDENTITY:-}
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1)
fi

# Nested code signs inside-out: the helper needs a valid signature of its own before the
# outer bundle seals it, otherwise the outer signature seals unsigned nested code.
if [ "${BAROMETER_HELPER_PROTOTYPE:-0}" = "1" ]; then
    if [ -n "$signing_identity" ] && [ "$signing_identity" != "-" ]; then
        codesign \
            --force \
            --options runtime \
            --timestamp \
            --sign "$signing_identity" \
            --identifier com.barometer.gpu \
            "$helper_app_directory"
    else
        codesign \
            --force \
            --sign - \
            --identifier com.barometer.gpu \
            "$helper_app_directory"
    fi
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

expected_executables=1
expected_executables_description="exactly one executable: Contents/MacOS/Barometer"
if [ "${BAROMETER_HELPER_PROTOTYPE:-0}" = "1" ]; then
    expected_executables=2
    expected_executables_description="Contents/MacOS/Barometer plus the opt-in GPU helper"
fi

if [ "$executable_count" -ne "$expected_executables" ] || [ ! -x "$macos_directory/Barometer" ]; then
    echo "Barometer.app must contain $expected_executables_description" >&2
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
