# Current patch validation

See [SOURCE_COMPATIBILITY.md](SOURCE_COMPATIBILITY.md) for the 4.0.1 live test matrix and limits.

# Historical 4.0 validation

- Xcode 26.6, iOS 26.5 SDK: Debug arm64 simulator and Release arm64 device builds pass. Export uses unsigned Release configuration with Swift optimization disabled and preview/debug dylibs disabled.
- 63 original Foundation checks plus one Aidoku isolation check pass (64 total). They cover anime catalog/cache, migration, journals, collections, date validation, streaks/DST, and reset isolation.
- Updated the existing simulator install without uninstalling. Anime library persistence bytes match their pre-integration SHA-256 after source installation and manga reading; no manga action changed anime streaks or library data.
- Native aidoku section opened with its own pink/light appearance, current native glass tabs, original manga library/browse/history/settings controllers. Settings remained separate and Back to Yoru restored the original anime interface.
- The original anime daily check-in popup still appeared on the current local day through the scene-phase adapter. It was dismissed without adding activity during this check.
- A compatible community repository was added, then the real legacy Komga v3 WASM source was installed. It loaded the public Komga demo catalog and the four chapters of Space Adventures.
- The actual Aidoku reader rendered a 35-page chapter, advanced from page 1 to page 2 with a keyboard command, updated the native accessible slider/page count, rendered page 2, and dismissed with Escape. The series screen changed to Continue Reading.
- Licenses/notices are included in the app; simulator data and accounts are not packaged.

Not exhaustively tested: every legacy provider, every touch gesture, third-party tracker login, long/background download jobs, physical iPhone installation, and Signulous re-signing. New-format Aidoku 0.7+ source packages remain unsupported. The source repository is legacy/unmaintained, so availability of individual providers is not guaranteed.
