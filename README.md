Mac version: [Yoru 4.2 release](https://github.com/kyle999999/Yoru/releases/tag/v4.2.0), Apple Silicon/macOS 26+. Includes the anime tracker and separate Aidoku section. [Mac build and validation](App/MAC_BUILD.md). The iPhone IPA remains available under [4.1.1](https://github.com/kyle999999/Yoru/releases/tag/v4.1.1).

# Yoru — anime tracker + separate aidoku section

Yoru 4.1.1 adds a native runtime for the **current [Aidoku community repository](https://aidoku-community.github.io/sources/)** while retaining the existing anime tracker, separate manga data, native layouts and Liquid Glass reader.

Download the unsigned iPhone/iPad IPA and complete corresponding source from [v4.1.1 releases](https://github.com/kyle999999/Yoru/releases/tag/v4.1.1). Requires iOS 26+ and signing, such as Signulous. Update with the same app identifier/signing setup without uninstalling to preserve data. Physical-device installation/signing were not tested here.

**146/146 current source packages instantiated**, and all 146 native manifests decoded. Current WEBTOON v5, MangaDex v14, WeebCentral v8 and MangaPlus v6 passed browsing/search/chapters/page-image tests. MangaPlus also visibly rendered through the existing native reader. MangaFire v8 loaded its catalog and chapters but its CDN images failed TLS negotiation from this environment. Other websites and authenticated access were not exhaustively tested. [Full evidence and limitations](App/SOURCE_COMPATIBILITY.md).

The newer source ABI is executed by an independent GPL Go backend with native Foundation/WebKit integration and interpreter-only Wazero. Existing legacy packages retain the GPL Aidoku 0.6.11 engine. The restricted Swift AidokuRunner package is not included. Licenses and attribution are retained; this is an unofficial modified integration.

Source project: [App/](App/README.md). Open App/Aidoku.xcodeproj and build the Aidoku (iOS) scheme, which produces Yoru. [Runtime provenance/build steps](App/ModernRuntime/UPSTREAM.md). Previous release archives remain historical and do not describe 4.1 source compatibility.
