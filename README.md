# Yoru 3.0 — Journal & Daily Glow

A native SwiftUI anime journal with a midnight palette, full-cover artwork, and iOS Liquid Glass navigation and controls.

## New in 3.0

- **Journal:** dated entries per anime, optional episode number, personal rating, mood, and spoiler flag. A reader hides spoiler bodies until revealed; entries can be edited or deleted.
- **Watch history:** first-watched and finished dates, personal series rating, and planning/watching/completed/paused/dropped status.
- **Collections:** named playlists/categories with a symbol and color. Shows can belong to multiple collections. Renaming preserves membership; deleting a collection preserves notes, shows, and progress.
- **Daily Glow:** a Liquid Glass streak screen with current/best streak, seven-day activity row, and 28-day grid. Log an episode or save a new/changed journal entry to earn a local day. Historical dates do not backfill streaks. Unchanged saves do not earn a new day; undo and note deletion remove the associated credits. A streak ending yesterday remains active for today.
- **Branding:** a 1024×1024 opaque app icon with a crescent moon and “yoru” wordmark. Reusable vector and renderer are in `Brand/`.

Journal text, dates, collections, and activity are kept locally and are not sent to Kitsu. v3 uses a new local storage key and leaves the v2 backup untouched. Earlier progress has no activity timestamps, so it cannot earn retroactive streaks.

## Discover

- This season: automatically selects the current year and season, loading every catalog page.
- Calendar: ongoing titles, including series that began in earlier seasons, grouped by the next release date supplied by Kitsu. Shows Japan time and the local date/time. Unknown dates appear under TBA; All shows all ongoing titles.
- Explore: previous seasons, all airing titles, completed anime, global search, and streaming-provider filters. Archive/search use a Load more button instead of downloading the entire database.
- Title details: real source-listed streaming links, provider names, cover art, synopsis, categories, progress, save/unsave, and undo.
- Library: local watchlist and episode history, including migration of saved v1 progress.

## Data and limitations

Catalog, images, next-release dates, and streaming links come from [Kitsu](https://kitsu.app) through its [public JSON:API](https://kitsu.docs.apiary.io). MyAnimeList IDs are used for cross-version identity where mappings exist. Explicit adult entries are excluded. At validation, Fall 2026 loaded 120 non-explicit titles over seven pages.

Provider listings include Crunchyroll, HIDIVE, Netflix, Hulu, Amazon, YouTube, and others when supplied by Kitsu. They are source listings, not guarantees of current availability in every country. Missing links mean unknown. No licensor-to-provider guessing is used.

The calendar is based on Kitsu next-release timestamps. It does not scrape Crunchyroll, HIDIVE, or Netflix calendars, and does not claim their exact subtitle/dub release times. An official Crunchyroll calendar link and HIDIVE/Netflix links are included for verification. Catalog coverage, release dates, and streaming links can be incomplete or outdated.

Catalog responses are cached for six hours. Pull to refresh fetches again; offline fallback is labeled and retains the retrieval date. Requests are paced, 429 responses are retried, and failed requests show a retry state. Search/catalog requests go to Kitsu; artwork loads from Kitsu image servers. Watchlists stay on-device.

Jikan was evaluated but its live API was unreachable during development. AniList was not integrated because its API terms restrict competing tracker services.

## Build and install

Requires iOS 26.0 or later and Xcode with an iOS 26 SDK. Extract `Yoru-3.0-source.zip` and open `Yoru.xcodeproj`. No API keys, accounts, or third-party packages are needed. Unsigned builds have `CODE_SIGNING_ALLOWED=NO`; use your development team and set it to YES for direct device installation. The IPA must be signed before sideloading.

## Validation and build status

Xcode 26.6 was reinstalled and the **iOS Release device build and Debug simulator build both passed**. The v3 app launched in an iPhone 17 Pro simulator; the redesigned Library and Daily Glow screens were visually checked. Journal, collection, persistence, migration, and streak behavior passed the Foundation checks described below. Full interactive coverage of every editor flow has not been performed.

`Yoru-3.0-unsigned.ipa` is the iPhone/iPad arm64 build, version 3.0 (build 3), requiring iOS 26.0 or later and signing before installation. The packaged IPA passed ZIP integrity checks and includes the moon-and-yoru app icon.

The Foundation model checks run with the installed Command Line Tools. They cover catalog decoding/caching plus journal creation/edit/delete, watch dates, ratings, multi-collection membership, persistence, v1/v2 migration, corruption protection, and streaks across gaps, midnight, and both DST transitions.

```sh
python3 Validation/run_checks.py
# Optional live catalog integration checks:
python3 Validation/run_checks.py --live
```

Extract `Yoru-3.0-source.zip` and open `Yoru.xcodeproj` in Xcode with iOS support to build or run the app. For direct installation, select your own development team and enable signing. No credentials or signing identities are bundled.
