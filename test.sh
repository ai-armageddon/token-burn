#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
args=(--disable-xctest)
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -f "$plugins/libTestingMacros.dylib" ]]; then
    args+=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi
swift test "${args[@]}"
