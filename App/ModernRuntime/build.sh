#!/bin/zsh
set -eu
ROOT_DIR=${0:A:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
for PLATFORM in iphoneos iphonesimulator; do
 SDK_PATH=$(xcrun --sdk "$PLATFORM" --show-sdk-path)
 if [[ "$PLATFORM" == iphoneos ]]; then TARGET=arm64-apple-ios26.0; else TARGET=arm64-apple-ios26.0-simulator; fi
 GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$(xcrun -f clang)" CGO_CFLAGS="-isysroot $SDK_PATH -target $TARGET" CGO_LDFLAGS="-isysroot $SDK_PATH -target $TARGET" go -C "$ROOT_DIR/Driver" build -buildmode=c-archive -o "$ROOT_DIR/Libraries/$PLATFORM/libYoruModern.a" .
 done
