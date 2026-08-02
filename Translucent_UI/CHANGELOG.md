# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-02

### Fixed

- **Sprites whited out / inverted (issue #1)**: the old sgbPalettes hijack added an `sgbPalettes` returning `nil` to screens that never had one. The engine's zone-owner walk (`Game:draw`) stops at the first state exposing `sgbPalettes`, so those screens claimed the SGB zone pass and handed `endFrame` an empty zone list — the shade-remap shader never ran and colour-dependent sprites rendered as raw DMG grays. Native zone ownership is restored: screens that define `sgbPalettes` keep theirs, and screens that never did fall through to the overworld/battle beneath.
- **Translucent boxes erased by the zone pass**: the translucent regions are now marked trueColor via `PaletteFX.markTrueColor` (the same mechanism the engine's DexEntryMenu uses), so the shade-remap pass re-blits them unshaded instead of remapping the alpha-blended pixels into solid zone colours.

## [1.0.0] - 2026-07-28

- Initial release: translucent UI boxes and widescreen fill support.
