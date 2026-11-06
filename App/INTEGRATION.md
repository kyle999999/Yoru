# Integration provenance

Yoru host: original SwiftUI anime tracker, journals, collections and streaks. Retained native manga UI/reader and legacy engine: GPL Aidoku v0.6.11 (`0fd6ee2847f06bdc0354c91345cc2f976506cb16`). Current source runtime: GPL independent aidoku-backend-0.7 (`660e08724d78f7ab2d9921b2b1e8c76f71478fb6`), modified through the native bridge in Integration/ and ModernRuntime/Driver/. Combined version 4.1.1 build 8.

The restricted Swift AidokuRunner implementation is not copied or linked. Original licenses, authorship, artwork, dependency notices and corresponding source are retained. The independent backend's upstream source and tests live in ModernRuntime/Backend; mobile dependencies are vendored in ModernRuntime/Driver/vendor.

Both sections share one installed app. A separate same-scene native window preserves the manga appearance and Back to Yoru behavior. Original navigation and reader layouts remain. Anime and manga defaults, network cookies/cache, SQLite paths, source files and backups remain isolated. No anime schema/key migration is introduced. Legacy packages remain installed; the current repository is added once alongside existing lists.

Modern manifests and model data are adapted to the existing controllers. Real WASM source execution is provided by interpreter-only Wazero. Native Foundation/WebKit supplies browser/network handling; JavaScript/canvas/source ABI functions are implemented by the independent backend and native adapter. Processed images enter the existing Nuke reader through a private URLProtocol. Runtime eviction limits live interpreters without installing a second app.

Device export is unsigned; original private iCloud/push entitlements remain omitted and CloudKit mirroring remains disabled. No source installations, account tokens, cookies or simulator data are distributed. [Exact compatibility tests and limits](SOURCE_COMPATIBILITY.md).
