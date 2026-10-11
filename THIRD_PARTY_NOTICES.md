# Third-party notices

The application bundles `Nile-Attributions.txt`, `FreeType-FTL.txt`, and
`HarfBuzz-COPYING.txt` from `Resources/ThirdPartyNotices`, plus the Apache
license from `Resources/Fonts/Roboto-LICENSE.txt`. These files are copied as
app resources because the statically linked renderer's framework resource
directory is not embedded in the app. `AppStoreBundleTests` verifies the
packaged notices against the checked-in license texts.

## FreeType

Nile is based in part on the work of the FreeType Team.
<https://www.freetype.org>

The custom renderer statically links FreeType 2.13.2 from upstream commit
`5ab8c8be9c2ce2c42aaa79752bffc89618d39515`.

- Source:
  <https://android.googlesource.com/platform/external/freetype/+/5ab8c8be9c2ce2c42aaa79752bffc89618d39515/>
- License: FreeType Project License
- Complete license text: `Resources/ThirdPartyNotices/FreeType-FTL.txt`

## HarfBuzz

The custom renderer statically links HarfBuzz 8.2.2 from upstream commit
`9a50c421c9ca31c44462ce31785f03ff41631ba5`.

- Source:
  <https://android.googlesource.com/platform/external/harfbuzz_ng/+/9a50c421c9ca31c44462ce31785f03ff41631ba5/>
- License: Old MIT
- Complete copyright notices and license text:
  `Resources/ThirdPartyNotices/HarfBuzz-COPYING.txt`

## Roboto

Nile includes `Resources/Fonts/Roboto-Regular.ttf`, Roboto Classic 3.005 for
Latin, Greek, and Cyrillic text. The file is pinned from upstream commit
`5d982bb4526f3e8a438a776619c060e1daf2f18f`.

- Source:
  <https://android.googlesource.com/platform/external/roboto-fonts/+/5d982bb4526f3e8a438a776619c060e1daf2f18f/>
- Font SHA-256:
  `9ca9debb09459bf4e3e7f826f5cd0f35f253902b85684921fce2ba3f28dd0f50`
- License: Apache License 2.0
- Complete license text: `Resources/Fonts/Roboto-LICENSE.txt`

## Droid Sans Mono

Nile includes `Resources/Fonts/DroidSansMono.ttf` for monospaced source and
terminal content. The checked-in file matches upstream blob
`b7bf5b4aa8ad5a8c8036653734d83006c6a376ee`.

- Source:
  <https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-security-15.0.0_r12/data/fonts/DroidSansMono.ttf>
- Font SHA-256:
  `db19a1fdaba41cc4a2fec0330e5c15e71c6dd68a3ef074f4f28268828b45c862`
- License: Apache License 2.0
- Complete license text: `Resources/Fonts/Roboto-LICENSE.txt`
