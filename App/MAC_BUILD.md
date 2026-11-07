# Yoru 4.2 for Mac

Mac Catalyst build for Apple Silicon, macOS 26+. Uses the same Mac bundle identifier as Yoru 3.1 (`maccatalyst.studio.yoru.Yoru`) to preserve existing anime preferences/library data. iPhone settings remain version 4.1.1; the Mac build is 4.2 (9).

Both the anime tracker and native Aidoku section run in the same Mac app. Mac navigation uses a single window with an explicit Back to Yoru button and Library/Browse/History/Search/Settings selector. Pull-to-refresh becomes Refresh/Command-R. Unsupported UIStepper controls use native plus/minus buttons. Manga files/cache/database live under Yoru/Aidoku on Mac, separately from anime preferences and other Aidoku installations.

## Build

Use Xcode 26.6 and Go 1.27.1:

```sh
./ModernRuntime/build.sh maccatalyst
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Aidoku.xcodeproj -scheme 'Aidoku (iOS)' -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO SWIFT_OPTIMIZATION_LEVEL=-Onone build
```

The local Texture package in PlatformSupport/Texture retains the original iPhone/simulator binaries and adds a Catalyst slice built from the included Apache-licensed source. Catalyst fixes guard the unavailable OpenGLES layer class and correct four malformed text-position comparisons. The source runtime has an arm64 Catalyst static library. No restricted Swift AidokuRunner code is added.

## Verified

On macOS 26.5.2: anime home and existing library data; opening Aidoku; visible settings and section controls; Settings → Source Lists → Add URL dialog; Back to Yoru restoring the actual anime screen. The current repository returned 149 entries. Current MangaPlus v6 installed, browsed/searched, loaded details/12 chapters/22 pages, decrypted a page and passed the existing reader image pipeline. The iPhone 146-package audit remains historical; this Mac check does not claim live testing all 149 websites. Existing provider/TLS/account/Markdown limitations in SOURCE_COMPATIBILITY.md remain.

The app is locally ad-hoc signed, not Developer ID signed or notarized. No Signulous/IPA is required for the Mac download. The DMG contains Yoru.app and an Applications link. Keep the old app/data until the new one has been checked. The package contains no private library, cookies or installed test sources.

To rebuild the Catalyst UI dependency from the included source, build PlatformSupport/Texture/AsyncDisplayKit.xcodeproj, scheme AsyncDisplayKit, with destination platform=macOS,variant=Mac Catalyst,arch=arm64 and SUPPORTS_MACCATALYST=YES IPHONEOS_DEPLOYMENT_TARGET=15.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO. Recreate its XCFramework from the retained iPhone/simulator frameworks plus that Catalyst framework using xcodebuild -create-xcframework. All source and licenses are included.
