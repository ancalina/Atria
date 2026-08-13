# Atria

Atria is a homescreen layout editor for iOS 15 and newer. It supports per-page
layouts, dynamic widget sizing, dock and floating-dock configuration, page
labels, background styling, and a visual label-script editor.

## Supported packages

- Rootless package: `iphoneos-arm64`
- RootHide package: `iphoneos-arm64e`
- Package identifier: `me.ancal.atria`
- Supported firmware: iOS 15.0 and newer

Rootless and RootHide builds use the same package identifier and version. Do
not install both variants on one device.

## Third-party tweak boundary

Atria implements only its own layout editor. It does not include, link against,
redistribute, or reimplement third-party icon-placement code, preferences, or
saved-position formats.

Compatibility uses a narrow runtime boundary around the external admission
gate that conflicts with the concrete Floating Dock. It is installed only when
the expected method ABIs and host identity can be verified, never changes the
other tweak's preferences or saved state, and fails open for unknown models or
signatures. Suggestion, recents, App Library, and persistence models remain
owned by SpringBoard or their originating tweak.

See [TESTING.md](TESTING.md) for the compatibility regression matrix.

## Label scripts

Page-label scripts can be edited visually or as source in Preferences. The
editor validates before saving and preserves the last valid source when an
edit is rejected. Supported blocks include text, wait, reload, conditionals,
and finite or infinite repeat containers. Conditions include time, weekday,
battery, charging, weather-text search, text-context search, and boolean
composition.

Scripts are bounded by source size, block count, nesting depth, text/query
length, wait duration, repeat count, runtime frame depth, and per-advance work.
`loop: false` now terminates after one root pass; an explicit repeat count of
zero remains the infinite-repeat form.

## Building

Requirements:

- A current Theos checkout with the complete iOS 16.5 SDK (or set
  `ATRIA_SDK_VERSION` to an equivalent newer SDK containing private framework
  link stubs); the deployment target remains iOS 15.0
- RootHide's Theos fork when producing the RootHide variant
- PreferenceLoader and Alderis headers/libraries

Build one package:

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Build both release variants and checksums:

```sh
make release
```

`make release` writes the two packages and `SHA256SUMS` to `release/`. Package
metadata is checked before packaging so the Makefile and `layout/DEBIAN/control`
cannot silently ship different identifiers or versions.

## License

See [LICENSE](LICENSE). No third-party icon-placement implementation is part of
this repository or its license.
