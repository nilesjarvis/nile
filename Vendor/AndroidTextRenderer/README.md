# Nile Android text renderer

This private static XCFramework reproduces the pinned Android 15 text path used
by Nile's Compose reference:

- Android FreeType 2.13.2 at `5ab8c8be9c2ce2c42aaa79752bffc89618d39515`
- Android HarfBuzz 8.2.2 at `9a50c421c9ca31c44462ce31785f03ff41631ba5`
- Minikin shaping, word-piece caching, edge spacing, and whole-line placement
- Skia A8 gamma correction with device gamma 1.4 and contrast 0

`scripts/vendor/build-android-text-renderer.sh` fetches only those immutable
source commits and creates the device plus universal-simulator XCFramework.
The checked-in binary is a reproducible build artifact so a normal Nile build
does not require Homebrew, a network connection, or host-specific libraries.

The renderer returns a transparent canvas outside glyph coverage. Covered
pixels are already composited against the supplied Android surface color so
FreeType/Skia edge coverage remains exact without hiding app-owned borders
behind an opaque label rectangle.
