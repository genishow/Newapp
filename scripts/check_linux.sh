#!/usr/bin/env bash
# The checks that can run without a Mac, in the swift:6.0-noble Docker image:
#   1. every Swift file parses
#   2. the logic unit tests pass (the parts of the app with no screens)
#   3. the Amharic table is complete
# The screens themselves and the end-to-end tests only run on GitHub's Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_strings.py

PKG="$(mktemp -d)"
mkdir -p "$PKG/Sources/Kinbir" "$PKG/Tests/KinbirTests"
cp Sources/API/{Models,APIError,SSEParser,Multipart,KinbirAPI,MockAPI,VideoModels,AvatarModels,ExtrasModels}.swift \
   Sources/Support/{TextKind,Formatters,Amharic,Launch,TempFiles}.swift "$PKG/Sources/Kinbir/"
cp Tests/*.swift "$PKG/Tests/KinbirTests/"
cat > "$PKG/Package.swift" <<'PKGEOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "Kinbir", targets: [
    .target(name: "Kinbir", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
    .testTarget(name: "KinbirTests", dependencies: ["Kinbir"],
                swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
])
PKGEOF

docker run --rm -v "$PWD":/src -w /src swift:6.0-noble bash -c \
  'swiftc -frontend -parse $(find Sources Tests UITests -name "*.swift") && echo "All files parse"'
docker run --rm -v "$PKG":/pkg -w /pkg swift:6.0-noble swift test 2>&1 | grep -E "error:|Executed" | tail -12
