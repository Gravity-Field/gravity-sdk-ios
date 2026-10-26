#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -D CORE_TEST_HARNESS -parse-as-library \
    "$repo/Sources/GravitySDK/utils/InAppPresentationGate.swift" \
    "$repo/Sources/GravitySDK/utils/VisibleImpressionStore.swift" \
    "$repo/Sources/GravitySDK/utils/InAppPresentation.swift" \
    "$repo/Sources/GravitySDK/utils/ModalImpressionSession.swift" \
    "$repo/Sources/GravitySDK/utils/VisibleImpressionDelivery.swift" \
    "$repo/Sources/GravitySDK/network/EngagementTransport.swift" \
    "$repo/Sources/GravitySDK/network/NetworkError.swift" \
    "$repo/Tests/GravitySDKTests/GravitySDKTests.swift" \
    "$repo/Tests/Portable/CoreTestHarness.swift" -o "$test_dir/core-tests"
"$test_dir/core-tests"
