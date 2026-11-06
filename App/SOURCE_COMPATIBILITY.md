# Current community sources — Yoru 4.1 (7)

## What changed

The app now executes the current packages from https://aidoku-community.github.io/sources/. It embeds the independent GPL [aidoku-backend-0.7](https://github.com/ohaiibuzzle/aidoku-backend-0.7), base commit `660e08724d78f7ab2d9921b2b1e8c76f71478fb6`, through a native C/JSON bridge. Wazero runs in interpreter mode with no JIT. The existing GPL 0.6.11 engine remains available for already installed legacy packages. The restricted Swift AidokuRunner implementation is not included.

Current-repository support is implemented, not a version-label change: modern manifests and repository envelopes, serialized source ABI, network/HTML/JavaScript/canvas/defaults imports, dynamic listings/settings/filters, searches, manga updates, chapters, image requests, processed page/cover images and native WebKit execution are connected to the existing app. Backend dependencies are pinned and vendored. See [runtime provenance and build instructions](ModernRuntime/UPSTREAM.md).

The current repository is added once alongside existing lists. Repository merging selects the newest package deterministically, so a faster legacy repository cannot hide a modern update. Download and icon URLs use the repository's actual relative URLs. Legacy source records, library/history databases and host data keys are retained. Existing language/content filters still apply; Thai and normalized language codes are supported. Source requirements are checked against the verified modern API ceiling (0.9.0), separately from the legacy engine's real 0.6.11 version. Instantiation validates actual imports before file replacement; unsupported future packages are not simply declared compatible.

## Compatibility fixes found through real failures

- Correct native settings types across JSON: string arrays, booleans, integers, floats and encoded data remain distinct. This fixed current MangaDex v14's `Unable to fetch languages` error.
- Preserve original response bytes until source decryption. MangaPlus's encrypted JPEG cannot be image-decoded first; its source receives the raw ImageRef bytes, decrypts them, and supplies the decoded image. Original encoded bytes are retained for ImageRef.data(), avoiding lossy re-encoding and large PNG expansion.
- Bridge page context and image-request modification through a private URLProtocol into the existing Nuke reader pipeline. Images, inline images, archives and source-side processing use the actual source implementation.
- Map modern listing IDs/name fallbacks, including MangaPlus's ID-only listings. All source manifests pass the native decoder.
- Omit empty text filters. Sending empty author/artist values caused MangaFire v8's catalog parser to fail; browsing now returns results.
- Retain modern source languages, viewer direction and chapter metadata in legacy UI models; use the chapter title when an extension provides no chapter number.
- Route networking and WebKit through Aidoku's isolated stores, preserving host appearance/settings/cookies. Keep native browser verification support and bounded request lifetimes. No TLS checks are disabled.
- Keep failed updates transactional and preserve installed sources. Metadata/network failures after a successful install are reported separately and can retry.
- Keep existing native navigation, library and reader layouts. New account fields use the existing native settings style. No second installed app or remote website wrapper is involved.

## Actual tests on 2026-11-06

The repository contained **146 packages** requiring **74 distinct host imports**.

1. Downloaded all 146 real packages and inspected their manifests, imports and exports. Instantiated **146/146** in the independent replacement runtime with no missing-import failures. Package versions, SHA-256 hashes and detected capabilities are recorded in [modern-package-load-results.json](Validation/modern-package-load-results.json). This is an ABI/loading test, not a live website test.
2. The actual iOS Source initializer decoded **146/146** manifests in the simulator. This caught and fixed ID-only listing compatibility.
3. Live tests used actual current packages, the native bridge, real HTTP requests and source functions:

| Current source | Install | Browse / search | Chapters / selected page count | Page image |
|---|---|---|---|---|
| WEBTOON v5 | Pass | 615 / 14 | 95 / 99 | Decoded |
| MangaDex v14 | Pass | 20 / 20 | 446 / 5 | Decoded |
| WeebCentral v8 | Pass | 32 / 25 | 6 / 168 | Decoded |
| MangaPlus v6 | Pass | 20 / 1 | 12 / 2 | Decrypted by source and decoded |
| MangaFire v8 | Pass | 50 / 50 | 34 / 25 | CDN TLS failure in this environment |

MangaPlus was also loaded through the **existing ReaderPageView/Nuke pipeline**, which returned success. Its decrypted first page was visibly rendered in the unchanged full-screen native reader with the glass toolbar. The final native probe is [modern-native-reader-results.json](Validation/modern-native-reader-results.json). The live summary combines the observed probe runs; it is not a claim that all 146 websites were browsed.

MangaFire's page list succeeded, but its mfcdn3.xyz image endpoints failed TLS negotiation. An independent TLS client outside the app failed too. This remains unresolved and may be provider/CDN/network related; the site is not declared globally unavailable. The extension is not marked as a successful image-loading test.

4. Backend runtime/host/source/model/postcard tests pass. New regressions cover typed native preferences and original JPEG byte ownership. Native Foundation tests cover modern URL/schema handling and deterministic modern-over-legacy repository precedence. The existing 63 anime regression checks and Aidoku settings-isolation check pass. Host anime library persistence matches its pre-modern-probe hash, including after source installation and manga reading.
5. Xcode 26.6 / iOS 26.5 SDK: arm64 simulator and unsigned arm64 Release device builds pass. No debug probe arguments or simulator/user data are packaged in the release. The IPA needs signing.

## Limits

All 146 packages loaded, but not every website was live tested. Websites can be offline, region-restricted, require an account, or change their API/anti-bot behavior. Markdown-only notice pages remain limited by the retained image reader. Account login, OAuth/PKCE variations, every advanced settings/filter interaction, every page, long background downloads and every touch gesture were not exhaustively verified. Basic/web login bridge paths are implemented but were not tested with personal accounts. Existing language/content filters can hide entries without indicating engine incompatibility.

Physical iPhone installation and Signulous signing were not tested. Update using the same signing/app identifier without uninstalling to retain the iOS data container. This modified build is not endorsed by Aidoku or the independent backend's author.
