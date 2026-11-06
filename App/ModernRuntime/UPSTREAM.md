# Independent modern source runtime

Backend: https://github.com/ohaiibuzzle/aidoku-backend-0.7, GPL-3.0, base commit `660e08724d78f7ab2d9921b2b1e8c76f71478fb6` (2026-11-05). Original license, attribution and tests are retained in Backend/. This is the independent Go implementation offered under GPL by its author. The restricted Swift AidokuRunner package is not included or linked.

Yoru modifications: force Wazero interpreter mode (no JIT); add a native WebKit host-module hook. Driver/ contains Yoru's C/JSON adapter, typed isolated preferences, HTTP transport, LRU runtime lifecycle, catalog/home/search, manga/chapter/page bridges, processed images, archive pages and login operations. Native UIKit/Foundation/WebKit code lives in Integration/.

Build dependencies are pinned by Driver/go.mod/go.sum and vendored in Driver/vendor. Run build.sh with Go 1.27.1 and Xcode 26.6, then build Aidoku.xcodeproj's Aidoku (iOS) scheme. Xcode links Libraries/$(PLATFORM_NAME)/libYoruModern.a. Product/bundle remains Yoru/studio.yoru.Yoru. iOS runs Wazero in interpreter mode with no JIT entitlement requirement.

The source session/cookies/site data and settings remain isolated from the anime tracker. The current community repository is added once alongside existing URLs; later removal is respected. Existing source version numbers are not rewritten. Installation actually instantiates the module before replacing files.

Package/ABI loading and website availability are separate tests. A loaded module does not establish that its website is online or that account/region restrictions disappear. See ../../SOURCE_COMPATIBILITY.md for evidence and remaining failures.
