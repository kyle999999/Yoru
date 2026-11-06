# Yoru 4.1.1 — current community sources

This is the native iPhone/iPad project for Yoru (iOS 26+), combining the anime tracker with its separate aidoku section. Build scheme **Aidoku (iOS)** produces **Yoru**, bundle `studio.yoru.Yoru`.

Current source packages use the independent GPL backend in ModernRuntime/. Existing legacy sources use the retained GPL Aidoku 0.6.11 implementation. [Compatibility findings/tests/limits](SOURCE_COMPATIBILITY.md), [integration details](INTEGRATION.md), [runtime provenance](ModernRuntime/UPSTREAM.md).

## Build

Requires Xcode 26.6 and Go 1.27.1 for rebuilding the embedded modern runtime. Dependency source is pinned/vendored; generated arm64 device/simulator libraries are also supplied.

```sh
./ModernRuntime/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Aidoku.xcodeproj -scheme 'Aidoku (iOS)' \
  -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO \
  SWIFT_OPTIMIZATION_LEVEL=-Onone build
```

The unsigned IPA is version **4.1.1 (8)**. It requires Signulous or another signer. Preserve the same signing/application identifier and update without uninstalling to retain app data. Signing and physical-device installation are not verified here.

Use Validation/run_checks.py for the 63 anime model checks. Additional source/runtime validation is described in SOURCE_COMPATIBILITY.md. Debug-only probes are opt-in launch arguments and absent from the release executable.
