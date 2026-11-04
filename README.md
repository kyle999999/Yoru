# Yoru

A native SwiftUI anime journal with a midnight palette, violet accents, and the native Liquid Glass tab bar.

## Features

- Tonight dashboard and featured series
- Search a curated offline catalog of five anime titles
- Save shows to your library
- Log and undo episodes, with progress stored locally

## Build

Extract `Yoru-source-public.zip` and open `Yoru.xcodeproj` in Xcode with the iOS 26.5 SDK. The deployment target is iOS 26.5; iPhone and iPad are supported. No third-party dependencies or accounts are required.

Code signing is disabled for unsigned builds. To install directly through Xcode, set Code Signing Allowed to Yes and choose your development team under Signing & Capabilities.

## IPA

`Yoru-unsigned.ipa` is the unsigned arm64 device build. It requires signing before installation.

## Validation

The simulator build and device archive succeeded. The IPA archive structure and integrity were checked. Runtime visuals and interactions have not yet been verified because the simulator stalled during startup.

The catalog is a small offline starter collection, not a live anime service. Artwork uses abstract gradients and SF Symbols. The app icon asset is currently a placeholder.
