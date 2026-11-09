# Yoru Rust experiment — iPhone only

Separate copy of Yoru 4.2.2. This is a working, incremental Rust-core experiment,
not a complete rewrite of Yoru or Aidoku in Rust.

The existing SwiftUI/UIKit screens, navigation, reader, resources and animations
are retained. `rust-core` has no third-party dependencies and implements streak
aggregation, bounded episode progress and ordered journal validation. A small
Swift C-ABI bridge passes borrowed integer buffers; local-calendar conversion,
Codable storage, networking, Aidoku's Swift/Go/WebAssembly runtime and platform
services remain native. Existing storage formats are unchanged.

The experimental iPhone bundle identifier is `studio.yoru.RustExperiment`, with a
separate Aidoku defaults domain. It installs alongside the production app and
starts with separate data. It does not copy or modify your production library.
Keep that identifier when signing; replacing it with production Yoru's identifier
would remove the isolation. The on-screen app and UI remain named Yoru.

## Build and check

Requires Xcode/iPhoneOS SDK, Cargo and the `aarch64-apple-ios` target (already
installed on this Mac). From this folder:

```sh
cargo test --manifest-path rust-core/Cargo.toml
cargo build --manifest-path rust-core/Cargo.toml --release
python3 App/Validation/run_checks.py
./build-ipa.sh
```

The check runner links the host Rust library and exercises existing model,
journal, collection, migration, schedule and DST scenarios through the bridge.
The IPA is unsigned and must be signed (e.g. Signulous) before installing on an
iPhone. No physical-device or reader interaction is claimed by these checks.
No Mac app/DMG is built by this experiment.

All original license and attribution files remain under App. This derivative
retains GPL-3.0-only requirements. Upstream dependency corresponding-source
snapshots are also available in the local original release source archives;
keep them when distributing a binary. The restricted Swift AidokuRunner is not
added or used here.
