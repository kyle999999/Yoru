# Source compatibility patch — Yoru 4.0.1 (6)

Tested 2026-11-06 with Xcode 26.6 and iOS 26.5 simulator/SDK.

## Findings and scope

The integrated engine really is GPL Aidoku v0.6.11, not a stale displayed version. Latest stable upstream checked: [v0.9-4](https://github.com/Aidoku/Aidoku/releases/tag/v0.9-4). Its current source engine uses AidokuRunner, whose [licensing notice](https://github.com/Aidoku/AidokuRunner#licensing) restricts redistribution of derivatives without an exception. This patch does not include that code or claim current-engine parity.

The MIT [Aidoku Rust SDK](https://github.com/Aidoku/aidoku-rs) was inspected. Modern packages use a different ABI: serialized postcard buffers, start/free_result/get_manga_update/get_search_manga_list exports, different network import signatures and additional modules. The real current WEBTOON v5 package was inspected with Validation/inspect_source_abi.py. Renaming the engine or skipping minAppVersion cannot make it executable. Modern 0.7+ repositories/packages remain unsupported; they are explicitly diagnosed in logs and incompatible updates do not replace working sources. No dependency version changes were needed for the verified legacy fixes. A permissively licensed SDK does not itself supply a functioning replacement runner.

## Fixes

- Correct multi-chunk network buffer reads; previously subsequent reads included earlier bytes and could write beyond the requested length. A test invokes the actual WASM import in three chunks and verifies all bytes.
- Preserve existing percent escapes, including encoded query separators and signed image URL components.
- Recognize MangaDex's HTTP-200 browser-verification redirect, run its normal JavaScript verification in WebKit, transfer domain cookies into the isolated source session, then retry. No server/version checks are bypassed.
- Case-insensitive Cloudflare header lookup; retain the original failed response when verification fails; prevent late callbacks from double-signalling the runtime semaphore. Verification is bounded.
- Isolate verification website data from the host app and retain isolated persistent network cookies. Set bounded network timeouts.
- Validate HTTP status before decoding repository JSON or unzipping downloads, and normalize repository base/index URLs without treating dotted directory names as files.
- Surface extension traps/negative error codes in existing logs rather than reporting an empty successful catalog. Network diagnostics omit request queries, bodies, cookies and authorization headers.
- Validate required legacy exports while treating initialize as optional. Stage updates and restore the previous files if replacement or database saving fails. Preserve local import archives.
- Update existing source database records rather than creating duplicates. Preserve records when a source fails to load. No data schema migration, host data-key change, navigation redesign, reader redesign or version-check bypass.

## Live source results

The Debug-only --source-compatibility-probe invokes the app's real SourceManager, WASM runtime, network imports and image-request modification. It installs actual packages from the community legacy repository, not mocked source responses.

| Source | Install | Browse | Search | Details / chapters / page list | First image |
|---|---|---|---|---|---|
| Komga v3, public demo | Pass | 7 series | 1 result for Space | 4 chapters; 36 pages in selected chapter | HTTP 200; UIKit decoded |
| xkcd v1, English | Pass | 1 comic | Not offered by extension | 3,319 chapters; 2 pages | HTTP 200; UIKit decoded |
| WEBTOON v3, English | Pass | 615 series | 14 results for Alice | 2 chapters; 66 pages | HTTP 200; UIKit decoded |
| MangaDex v8 | Pass | 20 results | 20 results for Alice | 446 chapters; 5 pages | HTTP 200; UIKit decoded |

MangaDex initially returned HTTP 200 text/html from mangadex.org/edge/challenge and its legacy parser returned -1. After the WebKit verification fix it completed the full path. One earlier run hit an intermittent malformed-WASM install error; the prior installation survived and the subsequent final installation/full test passed. This is not evidence that every provider or package works.

A real modern WEBTOON v5 update was rejected; the installed v3 main.wasm remained byte-for-byte identical. Exact sanitized live results are in Validation/source-compatibility-results.json. Legacy repository loading returned 34 entries. Legacy repositories are unmaintained, so future website/API changes can still break extensions. No website was declared unavailable merely because an extension failed.

## Existing app and limits

63 anime model/journal/calendar/check-in checks pass. The existing isolated-settings reset check passes. Additional transport checks cover encoded query integrity, accepted HTTP 200, six error statuses and credential-safe error messages. The actual multi-chunk ABI regression passes. The existing host and separate Aidoku native section launch; screenshots were inspected. Existing host source, UI and reader files are unchanged except Debug probe startup; no manga action writes anime library data. The host library preference was also hashed across normal relaunch after the live probe.

The live tests exercise engine operations and decode the first image; they do not test every touch gesture, every page, tracker login, all providers, long/background downloads, physical-device installation or Signulous signing. Previous 4.0 reader interaction evidence is historical, not a repeated touch-gesture test for this patch.

The release IPA is unsigned and requires signing. Use the same application identifier/signing setup as the previous install and update without uninstalling to preserve its data container. Production packages contain no probe data, installed sources, website cookies, user libraries or credentials.
