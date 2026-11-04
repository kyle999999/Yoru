# Yoru 3.1 — A week of stories

A native SwiftUI anime library for iPhone, iPad, and Mac, with a midnight palette and Liquid Glass controls.

## What changed

- Fixed the slow, empty Calendar: one MyAnimeList weekly schedule fetch replaces scanning every Kitsu airing page and guessing weekdays from missing next-release dates. Switching weekdays uses the loaded week immediately.
- Schedule refresh button, six-hour cache, last-retrieved date, labeled offline fallback, and explicit retry errors. Invalid/challenge HTML cannot replace a good week with an empty result.
- Calendar My library filter, Today shortcut, title counts, and links to official streaming calendars.
- One-tap daily check-in with a Liquid Glass popup on the first active visit each local day when today is not already active. Dismissing it avoids repeat prompts that day; Daily Glow always provides a manual button. No journal or episode is required.
- Check-ins persist and count once per local day. Episode logs and changed journal entries still count too. Existing watchlists, journals, collections, and streak history are retained.
- Search saved shows and filter by watch status, within any collection.
- Mac Catalyst app for Apple Silicon and Intel, alongside the iPhone/iPad IPA.

## Keep your stories

Save anime, track episodes, set first-watched/finished dates and ratings, and organize shows into collections with symbols and colors. A show can belong to multiple collections. Write dated journal entries with moods, episode numbers, and optional spoiler flags. View your current/best daily streak, seven-day activity, and 28-day grid.

Library data and daily check-ins stay on the device. v1/v2 progress migrates; the v2 backup is preserved. The v3 storage key is retained for this update. Existing history is not backfilled into streaks. Local day boundaries follow the device time zone; a yesterday-ending streak remains active while today is still available.

## Sources and limits

Catalog/search/detail/streaming-provider data use [Kitsu](https://kitsu.app) and its public API. Calendar uses [MyAnimeList’s public weekly schedule](https://myanimelist.net/anime/season/schedule). Explicit adult genres are excluded. Weekly days are Japan broadcast days, **not** local dates or verified subtitle/dub streaming premieres. Exact times are not supplied by this calendar reader. All includes other and unknown-day listings. Source coverage can be incomplete and schedules can change.

Streaming provider links are supplied by Kitsu, not inferred. Missing links mean unknown; regional availability can differ. Crunchyroll, HIDIVE, Netflix, and other official links are available in the app. If MyAnimeList changes its page format, the app shows an error or a labeled previous cache rather than claiming a quiet day. Calendar refresh uses one request with a 12-second request timeout and no retry loop. Kitsu catalog pagination remains separate.

Search terms/catalog requests go to Kitsu, weekly schedule requests go to MyAnimeList, and artwork loads from those sources’ image hosts. Journal text, watch history, and check-ins are not uploaded. No accounts, API keys, or third-party packages are required.

## Downloads and building

- `Yoru-3.1-Mac.dmg`: open and drag Yoru into Applications. Requires macOS 26+. Universal Apple Silicon/Intel Mac Catalyst app, locally ad-hoc signed, not Apple-notarized.
- `Yoru-3.1-unsigned.ipa`: requires iOS/iPadOS 26+ and signing before installation.
- `Yoru-3.1-source.zip`: clean Xcode project and validation sources. Extract and open `Yoru.xcodeproj` in Xcode 26. For device signing, select your own development team. No signing credentials are bundled.

## Validation

Release iPhone device, Debug iPhone simulator, and universal Release Mac Catalyst builds pass with Xcode 26.6. Calendar was checked against live data on Mac, including switching weekdays and the saved-show filter. Automated Foundation checks cover schedule parsing and malformed responses, persistent cache reuse/offline fallback, prompt suppression/day rollover, duplicate check-ins, streak persistence, journal/collection CRUD, v1/v2 migration, corruption protection, and DST boundaries.

Run `python3 Validation/run_checks.py`. The sanitized schedule fixture retains public structural samples only; no cookies, scripts, or session tokens. The optional `--live` flag also checks Kitsu catalog integration. Full interactive coverage of every journal editor has not been performed.
