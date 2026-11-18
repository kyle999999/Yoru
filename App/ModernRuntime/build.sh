#!/bin/zsh
set -eu
ROOT_DIR=${0:A:h}
# Respect Xcode's selected toolchain, including hosted Mac installations.
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export GOTOOLCHAIN=auto
YORU_GO_BINARY=${YORU_GO_EXECUTABLE:-$(command -v go || true)}
if [[ -z "$YORU_GO_BINARY" && -x /usr/local/go/bin/go ]]; then YORU_GO_BINARY=/usr/local/go/bin/go; fi
[[ -x "$YORU_GO_BINARY" ]] || { print -u2 "Go 1.27.1+ is required. Set YORU_GO_EXECUTABLE to its full path, or use the updated Hosted Mac shortcut which installs Go automatically."; exit 1; }
"$YORU_GO_BINARY" version
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
 GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$(xcrun -f clang)" CGO_CFLAGS="-isysroot $SDK_PATH -target $TARGET" CGO_LDFLAGS="-isysroot $SDK_PATH -target $TARGET" "$YORU_GO_BINARY" -C "$ROOT_DIR/Driver" build -mod=vendor -buildvcs=false -buildmode=c-archive -o "$ROOT_DIR/Libraries/$PLATFORM/libYoruModern.a" .
done
