#!/bin/zsh
set -eu
ROOT_DIR=${0:A:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PLATFORMS=("$@")
if (( $# == 0 )); then PLATFORMS=(iphoneos iphonesimulator maccatalyst); fi
for PLATFORM in "${PLATFORMS[@]}"; do
 case "$PLATFORM" in
  iphoneos) SDK=iphoneos; TARGET=arm64-apple-ios26.0 ;;
  iphonesimulator) SDK=iphonesimulator; TARGET=arm64-apple-ios26.0-simulator ;;
  maccatalyst) SDK=macosx; TARGET=arm64-apple-ios26.0-macabi ;;
  *) print -u2 "Unknown platform: $PLATFORM"; exit 1 ;;
 esac
 SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
 GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$(xcrun -f clang)" CGO_CFLAGS="-isysroot $SDK_PATH -target $TARGET" CGO_LDFLAGS="-isysroot $SDK_PATH -target $TARGET" go -C "$ROOT_DIR/Driver" build -buildmode=c-archive -o "$ROOT_DIR/Libraries/$PLATFORM/libYoruModern.a" .
done
