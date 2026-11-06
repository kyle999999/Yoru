# Yoru — anime tracker + separate aidoku manga section

Yoru 4.0.1 includes source compatibility fixes and adds an independent native manga section using the GPL Aidoku v0.6.11 implementation, modernized for iOS 26. Anime tracking, journals, collections, and streaks stay separate from manga libraries, reading history, settings, sources, and downloads.

## Downloads

[Releases](https://github.com/kyle999999/Yoru/releases) include the unsigned iPhone/iPad IPA and complete source archive. The IPA requires iOS 26+ and signing with Signulous or another service. Use the same signing identity/application identifier as the prior Yoru installation and do not uninstall it first to preserve its data container. Physical-device installation and Signulous signing have not been tested here.

Source project: [App/](App/README.md). Open App/Aidoku.xcodeproj and select the upstream Aidoku (iOS) scheme; the built app is Yoru. The complete corresponding-source archive also includes dependency source snapshots and licenses. See [validation](App/VALIDATION.md) and [integration details](App/INTEGRATION.md).

## Important source compatibility

This is a modified GPL-compatible integration, not an official Aidoku release or Aidoku 0.9 feature-parity claim. **New-format Aidoku 0.7+ sources are unsupported.** The in-app Source Lists page explains legacy .aix compatibility and can explicitly add the legacy community list. That repository is unmaintained; individual providers can be broken. Komga v3, xkcd v1, WEBTOON v3 and MangaDex v8 were verified through decoded page images. MangaDex browser verification is handled. See [the compatibility report](App/SOURCE_COMPATIBILITY.md) for exact results and remaining limits.

The current restricted AidokuRunner implementation is not included. Aidoku original source/authorship and GPLv3 notices are retained. The manga section’s Settings → About → Open-source notices includes dependency terms. Current combined source is GPLv3; previous release archives predate this integration.

The prior Yoru 3.1 Mac release remains available separately; 4.0 currently targets iPhone/iPad.

Latest patch: [v4.0.1](https://github.com/kyle999999/Yoru/releases/tag/v4.0.1). The actual engine remains 0.6.11; modern 0.7+ sources are unsupported.
