# Integration provenance and changes

Base: Aidoku v0.6.11, `0fd6ee2847f06bdc0354c91345cc2f976506cb16`, GPLv3. Yoru host: 3.1, combined version 4.0 build 5. This modified build is not distributed or endorsed by Aidoku’s original developer.

Yoru lives in Yoru/. The original GPL Aidoku source remains in Shared/ and iOS/. Original artwork is retained in OriginalBrand/. The app product name, bundle identifier, icon, and localized display name remain Yoru. The upstream explicit Xcode source/resource lists are retained; two synchronized groups add the host and integration adapter. Restricted AidokuRunner code is excluded.

Host edits are limited to the aidoku tab, removing the second executable entry point, and splitting a journal-sort expression without changing its ordering. A UIKit scene-phase adapter preserves the original anime daily check-in behavior. No anime library schema/key changes or manga-to-anime migrations are introduced.

Integration adapters establish a second same-app window for Aidoku’s actual native controllers, its own appearance, and a Back to Yoru control. iOS 26 tab/navigation APIs and reader progress controls modernize the UI; the original legacy WASM interpreter, database, library, source/settings controllers, download logic, and reader/page implementations do the work. No remote app/web wrapper is used.

Aidoku defaults, network session/cookies/cache, SQLite paths, files, backups, and source preferences are namespaced separately. Source import preserves local input archives. Compatibility/version checks use the legacy engine’s real version. Source Lists explains legacy compatibility and offers an explicit community-list setup button. No repository is auto-added to a clean production install.

Device signing is disabled for export; private iCloud/push entitlements are omitted and CloudKit mirroring is disabled. Existing sideload warnings remain. Swift optimization is disabled for the validation/re-signable Release build. No API keys, account sessions, signing certificates, or physical-device data are distributed.
