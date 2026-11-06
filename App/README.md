# Yoru 4.0 — aidoku

Yoru’s anime tracker plus a **separate native manga section** named **aidoku**, in one iPhone/iPad app.

The manga section uses actual Aidoku **v0.6.11 GPLv3 implementation**, commit `0fd6ee2847f06bdc0354c91345cc2f976506cb16`. It is modernized for iOS 26 with native Liquid Glass tabs/navigation, a separate Search tab, an accessible native reading-progress slider, page actions, and keyboard page navigation. It is a modified integration, not an official Aidoku release and not a claim of Aidoku 0.9 feature parity. There is no website wrapper or second installed app.

## Separate from the anime tracker

- Yoru retains its existing screens, colors, anime catalog/calendar, watch progress, journal, collections, and daily streak behavior. Its only navigation addition is the aidoku entry.
- Manga library, sources, source settings, reading progress/history, downloads, backups, cookies, and caches belong only to aidoku. Manga reading never earns anime streak activity.
- Aidoku preferences use `studio.yoru.embedded-aidoku`; files and SQLite stores are under `Aidoku` subdirectories. Resetting Aidoku preferences does not reset the anime library.
- The native Aidoku window keeps its own pink tint and system/light/dark preference. Back to Yoru returns to the anime tracker. Full-screen readers cover that integration control.
- The existing `studio.yoru.Yoru` application identifier and moon/yoru primary icon are retained. The app is intended as an update, not a fresh app install.

## Sources and compatibility

This build uses the open-source legacy WASM engine. **Aidoku 0.7+ / new-format source packages are not compatible.** The current AidokuRunner dependency is deliberately excluded because its stated redistribution restriction is not GPL-compatible.

Use legacy-compatible `.aix` packages or the legacy community list:
`https://raw.githubusercontent.com/Skittyblock/aidoku-community-sources/gh-pages/`

The in-app Source Lists page explains compatibility and provides an Add legacy community list button. That repository is no longer actively maintained; individual providers can be broken, unavailable, changed, or region-dependent. You can add your own compatible repositories. No source or third-party repository is silently installed in a fresh production app.

The real legacy **Komga v3** source was installed in the test simulator, loaded the official public Komga demo catalog, and rendered a 35-page Space Adventures chapter. This verifies one working source, not every legacy provider. No demo library, login sessions, or simulator data are bundled in the IPA.

## Compatibility fixes

- Current SDK async diffable-data-source application.
- Initialize the Core Data stack before background source work.
- Source import copies a local `.aix` before extraction, preserving the user’s original file.
- Use the embedded engine version for source compatibility checks rather than Yoru’s app version.
- Replace private old-toolbar layout assumptions with current native sizing and an accessible UISlider while retaining the original reader engine.
- Keep the anime check-in lifecycle active only in the anime section.
- Source reset, network cache clearing, and cookies remain isolated from the host.

## Build and signing

Requires **iOS/iPadOS 26+**, Xcode 26.6, and network access on the first dependency resolution. No private keys, provisioning profiles, or user credentials are included.

Open `Aidoku.xcodeproj`, select **Aidoku (iOS)** (the upstream scheme; the product is Yoru), and select your signing team if desired. Command-line build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Aidoku.xcodeproj -scheme 'Aidoku (iOS)' \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  SWIFT_OPTIMIZATION_LEVEL=-Onone ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO CODE_SIGNING_ALLOWED=NO build
```

The distributed IPA is an unsigned arm64 device build, version **4.0 (5)**. It uses Release configuration with Swift optimization disabled to avoid an expensive upstream optimization pass; it has no development-signing entitlement requirement. Re-sign with Signulous. **Use the same signing identity/application identifier as your previous Yoru installation, and do not uninstall the old app first**, to preserve its iOS data container. Actual Signulous signing and a physical iPhone installation have not been tested here.

Original developer iCloud/CloudKit entitlements are not usable in this re-signable integration. Aidoku’s iCloud option stays unavailable; local persistence, downloads, and backups remain available. This update targets iPhone/iPad; the previous Yoru Mac release is unchanged.

## Source and licensing

The combined application is GPLv3; preserve `LICENSE`, original authorship headers, and the bundled open-source notices. Translations and dependencies retain their separate terms. Aidoku upstream: https://github.com/Aidoku/Aidoku . The current restricted AidokuRunner source is not included in this project or release.

`Integration/LegalNotices.txt` is accessible inside Aidoku Settings → About → Open-source notices. `DEPENDENCIES.json` records resolved revisions. `INTEGRATION.md` records integration changes. The source archive includes build scripts/project files, original resources, and source snapshots/licenses of dependencies in `CorrespondingSources/` (the project resolves its pinned dependencies normally).

## Validation

Foundation regression checks: `python3 Validation/run_checks.py`. Isolation check instructions and build/smoke-test results are recorded in `VALIDATION.md`. Successful builds do not guarantee that every provider works. Full physical-device, exhaustive reader gesture, tracker-login, and background-download coverage has not been performed.
