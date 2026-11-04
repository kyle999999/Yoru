# Yoru 2.0

A native SwiftUI anime journal with a midnight palette, full-cover artwork, and iOS Liquid Glass navigation and controls.

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

Requires iOS 26.0 or later and Xcode with an iOS 26 SDK. Download and extract `Yoru-2.0-source.zip`, then open `Yoru.xcodeproj`. No API keys, accounts, or third-party packages are needed. Unsigned builds have `CODE_SIGNING_ALLOWED=NO`; use your development team and set it to YES for direct device installation. The IPA must be signed before sideloading.

## Validation

Simulator and device builds are checked. `Validation/ModelChecks.swift` verifies actual API decoding, provider relationships, HTTPS links, legacy watchlist migration, persistence, episode bounds, Japan time conversion, cache/offline behavior, seasonal pagination queries, and provider filters. Pass `--live` to additionally fetch all pages of the current season and test global search and HIDIVE filtering.

From the extracted project root on macOS:

```sh
xcrun swiftc -swift-version 5 -parse-as-library Yoru/Anime.swift Yoru/Kitsu.swift Yoru/AnimeAPI.swift Yoru/Library.swift Validation/ModelChecks.swift -o /tmp/yoru-checks
/tmp/yoru-checks Validation --live
```

The fixtures are recorded public Kitsu responses; no credentials or account information are included.
