#!/bin/sh

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_directory=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
sdk_path=$(DEVELOPER_DIR="$developer_directory" xcrun --sdk macosx --show-sdk-path)
clang=$(DEVELOPER_DIR="$developer_directory" xcrun --find clang)

"$clang" \
    --analyze \
    -o /dev/null \
    -std=c17 \
    -isysroot "$sdk_path" \
    -I "$project_directory/Sources/CSystemSources/include" \
    -Xanalyzer -analyzer-checker=security.FloatLoopCounter \
    -Xanalyzer -analyzer-checker=security.insecureAPI.rand \
    -Xanalyzer -analyzer-checker=security.insecureAPI.strcpy \
    "$project_directory/Sources/CSystemSources/shim.c"

printf '%s\n' "C security diagnostics passed"
