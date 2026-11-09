#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p artifacts
cargo build --manifest-path rust-core/Cargo.toml --release --target aarch64-apple-ios
xcodebuild -project App/Aidoku.xcodeproj -scheme 'Aidoku (iOS)' \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath build/ios -jobs 3 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO \
  SWIFT_OPTIMIZATION_LEVEL=-Onone build > artifacts/ipa-build.log 2>&1
mkdir -p build/package/Payload
# Use a clean staging bundle so stale binaries cannot survive incremental builds.
if [[ -d build/package/Payload/Yoru.app ]]; then
  mv build/package/Payload/Yoru.app "build/package/Yoru-previous-$(date +%s).app"
fi
ditto build/ios/Build/Products/Release-iphoneos/Yoru.app build/package/Payload/Yoru.app
(cd build/package && /usr/bin/zip -qry ../../artifacts/Yoru-Rust-Experiment-0.1.0-unsigned.ipa Payload)
echo "IPA: $PWD/artifacts/Yoru-Rust-Experiment-0.1.0-unsigned.ipa"
