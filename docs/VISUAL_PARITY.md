# Visual parity contract

## Oracle

The immutable source is `.reference/android` at
`bd5451da891f2d886b9bc35f8ea67d6920df1d98`.

Mandatory Android screenshots:

| Fixture | Size | SHA-256 |
| --- | --- | --- |
| `nile-chat.png` | 1080 × 2400 | `3fe2913d2d5b9b40f3f3b3aaa73772e03430b0ce85772bb33dba9d32968f43e1` |
| `nile-delegation.png` | 1080 × 2400 | `89314eff0545d3c7e583c19eb10d10b92c8c51a66002d2f78d3e3eee65dd3dd6` |
| `nile-goal.png` | 1080 × 2400 | `556d44c2eaa39c6c6cf8f9036104d5c0be6917643986dab2d42cdf1f7c6f936a` |
| `nile-media.png` | 1080 × 2400 | `87e2aa25b4268eddb90ccaa0f6f7dbaf1b84954f15e2ad3caae3744a175d714c` |
| `nile-onboarding.png` | 1080 × 2400 | `99b69543da73967990146185e8cfac2ebdde839b7525064bcece48f7801138ff` |
| `nile-sessions.png` | 1080 × 2400 | `6ad848c0f6102a1181bcf5c47b49f934cffc272a53dbc89cbfbb7b9d1bf3e388` |

These checked-in images remain immutable historical fixtures. The onboarding
image is not the current pinned-source state: it predates Android commit
`c9cb0c4` (`feat: remove Hermes agent updater`) and still shows both the removed
Hermes Agent updater card and an initially expanded gateway form. At the pinned
commit, `SettingsUi.kt` contains neither updater UI nor text and initializes the
form collapsed unless an onboarding error exists. Source behavior is
authoritative when a historical screenshot conflicts with it. The old image is
therefore retained only by
`scripts/visual/manifests/onboarding-legacy-screenshot.json`; it is never
silently replaced or treated as a current semantic oracle.

## Extracted tokens

The Swift constants in `NileDesignTokens.swift` must stay aligned with
`NileTheme.kt`.

| Role | Value |
| --- | --- |
| canvas | `#181818` |
| panel | `#212121` |
| lowest/code surface | `#0D0D0D` |
| raised/interactive surface | `#242424` |
| border/selected surface | `#2A2A2A` |
| primary text | `#FFFFFF` |
| prose | `#D1D1D1` |
| strong prose | `#E3E3E3` |
| muted | `#BABABA` |
| link/running | `#339CFF` |
| warning/needs input | `#FF8549` |
| error | `#FF6764` |
| complete | `#40C977` |
| syntax keyword | `#339CFF` |
| syntax string | `#85DF7B` |
| syntax value | `#FF66AD` |
| syntax comment | `#8F8F8F` |

Radii are 8, 12, 24, and full pill. Motion durations are 150, 240, and
900 milliseconds; shimmer is 1200 milliseconds.

`NileMark.swift` currently uses the Nile river artwork shared with the native
app icon. The pinned Android N-mark remains the acceptance target under
`AGENTS.md` and `IOS_PORT_GOAL.md`; the river geometry is a recorded,
reproducible divergence until it is aligned or the governing contract is
explicitly amended.

## Canonical iOS capture

- Device: iPhone 17 Pro
- Runtime: iOS 26.5
- Logical viewport: 402 × 874 points
- Captured pixels: 1206 × 2622
- Appearance: dark
- Locale: `en_US`
- Initial inspection: `build/checkpoints/onboarding-foundation.png`
- Session shell inspection:
  `build/checkpoints/session-pin-interaction2/` (1206 × 2622 collapsed and expanded
  captures from selector-driven XCUITest)
- Terminal ownership inspection:
  `build/checkpoints/stored-session-final/` (1206 × 2622 read-only working state
  and blocked Claim confirmation, exported from the final selector-driven
  XCUITest)
- Transcript inspection:
  `build/checkpoints/transcript-final/` (1206 × 2622 collapsed and expanded tool
  activity, selectable assistant prose, copy action, user bubble, and session
  shell, exported from a selector-driven XCUITest)
- Transcript scroll and syntax inspection:
  `build/checkpoints/transcript-scroll-ui-final/` (1206 × 2622 anchored tail
  with Android syntax colors and restored parked reading position with the
  48-point jump control, exported from a selector-driven XCUITest)
- Paired long-history/syntax inspection:
  `build/test-lab-results/20260725T040036Z-68713/visual-attachments/`
  (1206 × 2622 source-copy messages 32–40, syntax block, final user bubble,
  and connected-session shell)
- Attachment inspection:
  `build/checkpoints/attachments-final/233E6187-6ABE-44C6-9BF0-71FE821D893E.png`
  (1206 × 2622 native media/file cards plus two real pending JPEG thumbnails,
  exported from the 9-test final UI run)
- Retained media-parity inspection:
  `build/test-lab-results/20260725T033820Z-37908/visual-attachments/`
  (1206 × 2622 exact CLI read-only transcript, striped deterministic image
  bytes, attachment card, Claim action, and five-second history footer)
- Model-picker inspection:
  `build/checkpoints/model-picker-final/3AA2EC36-6E0C-4164-91FF-87F8699E9A11.png`
  (1206 × 2622 session model sheet with reasoning, current model, resolved and
  unresolved pins, provider grouping, capability/pricing labels, and independent
  pin controls)
- Goals, telemetry, statistics, and delegation inspection:
  `build/checkpoints/goal-usage-delegation-ui-final/` (1206 × 2622 goal quick
  start and active status, categorized context breakdown, 30-day activity
  statistics and heatmap, active delegated-agent overview/details, and settled
  transcript group)
- Current onboarding calibration:
  `build/checkpoints/onboarding-compose-measurement/` (1206 × 2622 clean and
  expanded iOS captures from selector-driven source-copy fixtures)
- Current pinned-Android captures:
  `scripts/visual/baselines/android/` (1206 × 2478 clean and expanded captures
  plus UIAutomator hierarchies, generated from an APK built directly from the
  pinned source)

The tracked Android captures are immutable source baselines for the pinned
commit, not accepted iOS parity evidence. Their clean/form PNG SHA-256 values
are `41d0873e1f5e4877f39f66169d0348c1300ac94e0bb9d3c52d26553133904db0`
and `9dc1053b3f55d7ce3081efd437641434d4af3130efaed0d3c77cf967fde89065`.
The active-goal card/details PNG SHA-256 values are
`cba47e0f1d6b0bba5392cfac21b19e252246a667d3d41e482c7b4fc7fb2bd8b8`
and `9cadc8b1776a9e74bba8a0bd84f840aa89e2a8c4cbe07c0208740cdd4f8540b2`;
their paired semantics hashes are
`6ad0c98816d13f461a5498c0a1b7b6898e886f4da5d64aa08d8c7f11d5b24813`
and `8671a9a1c6a95061e337aedd29b9c8f39f2c18ffb50cada87806e67713a47f0a`.
The mixed-delegation PNG and semantics SHA-256 values are
`a906fb79dab9931bff46bb66a339186a17804b7d3546e6af32e308f79de1dc8b`
and `a2bee56b190958fb1bd9c47a567be1705897b3fd85ca0808d878a36c8c108042`.
The context-breakdown PNG and semantics SHA-256 values are
`3b45b6a38f25e6e1513373fb4c7a99118d1969933f76347029dea295cd671c44`
and `7444f27828cc4833f8a7de914feed173676ada3f7b5596d33fa0eea61ee82567`.
The rename-dialog PNG and semantics SHA-256 values are
`d3e829044f5caef9e328b3955c2715319ff44a1c454323ea2b83a05eee123719`
and `23ea77c05f131a956bdb418178efa90911be97927a8e14110f7246d48efd0f7c`.
The canonical brand-chat PNG and semantics SHA-256 values are
`e63f354995eaf86a2796336dabaa8103fe1a9fce1b841eb60027f51a96bf87ed`
and `2be8d561b46cf0ec3f5b7e306a4c267eeaaba5c70a97e2848ede47a2ea117abf`.
The expanded brand-sessions PNG and semantics SHA-256 values are
`0ec7441fc8c333031f1a335b46c11df06c6c4c505cf3418268b1654d86b62b1b`
and `a5c3031c66061d8db12e080a80dc4a353179717cd77ce7cab9c8fee736e2a8e0`.
The long-history/syntax PNG and semantics SHA-256 values are
`b2e0a93471f503374cd0ef3b53d995f9a3ca0f0906735e1babffed00d4be44ee`
and `c2c0da3f0638a77d606ad5691c045fa30ea0ae2cc493d96ad7ca0ba3e3f7f0ad`.
`scripts/visual/capture-android.sh` reproduces them in an isolated Pixel 6/API
35 AVD after verifying the pinned APK hash. It uses a 1206 × 2478 display with
deterministic 72-pixel top and bottom system bars, yielding the iPhone
candidate's exact 1206 × 2334 app-owned content viewport.
The app now embeds AOSP's pinned Roboto Classic 3.005 variable font, registers
the regular, medium, semibold, and bold instances, retains its Apache 2.0
notice, and applies the pinned Compose typography metrics to Settings. The
current iOS form also preserves Android's inline cleartext warning, explicit
approval checkbox, and disabled insecure-connect outcome while adapting the
Android emulator host alias to the iOS Simulator loopback address.

The session fixture is derived from Android `SessionShellUiTest.brandChatState`.
Current manual comparison confirms the source-defined 96-point collapsed height,
180×68 pill geometry, 8-point pill spacing, 56-point expanded header, 14-point
expanded inset, 10-point row spacing, 12-point card radius, and exact flat token
colors. The shell uses repository-owned Material/custom path geometry for its
app-owned icons rather than SF Symbols. Its final interaction run also proves
that pin/unpin reordering does not activate the adjacent session-open control.
The source-paired canonical chat and expanded-session fixtures now pass the
zero-mask quantitative gate. Chat reports SSIM `0.828341`, outlier fraction
`0.071415`, and mean absolute channel delta `10.009219`; expanded sessions
reports SSIM `0.947338`, outlier fraction `0.023988`, and mean absolute channel
delta `2.612023`. All six combined image-derived landmarks are within `0.67`
point, all six sampled canvas/session/composer colors match exactly, and
native-scale reference/candidate/diff/heatmap review is accepted under the
user-approved native cross-platform presentation tier.

The terminal ownership fixture also confirms the source-defined 24-point
read-only container radius, 56-point action row, 48×48 Claim action, divider,
status row, Android copy, and blocked confirmation state. It remains manual
development evidence because no matching deterministic Android capture or
quantitative comparison exists yet.

The transcript fixture confirms the Android graphite hierarchy, bottom
alignment, right-aligned user bubble, prose colors, compact assistant copy
affordance, consecutive-tool grouping, expanded terminal/code surface, status
colors, inline strong text, exact Android paragraph wrapping, and multiline
composer growth. Its canonical source-paired chat state is the quantitative
pass recorded above. The long-history fixture additionally confirms initial
tail placement, gesture-only anchor release, independent per-session
reading-position restoration, explicit jump-to-bottom, send re-anchoring, and
the exact Android keyword/string/value/comment syntax palette. Its dedicated
production-shell pair passes with zero masks at SSIM `0.935771`, outlier
fraction `0.028354`, and mean absolute channel delta `3.819058`. The selected
session and syntax-block landmarks are all within `1.34` points, and the three
sampled canvas/session/composer colors match exactly.

The attachment fixture confirms Android's 64×64 pending-photo cells, 10-point
corner radius, 8-point spacing, 22-point top-trailing removal controls,
photo-only Send state, and native image/file card hierarchy inside the same
floating composer. The blue and orange thumbnails are valid deterministic JPEG
bytes rather than placeholder surfaces. This is still manual development
evidence; it does not replace the required normalized comparison.

The model-picker fixture confirms Android's 720-point maximum-width top sheet,
640-point maximum height, 18-point bottom radius, graphite hierarchy, 48-point
close/provider/model/pin targets, session-only reasoning copy, current-model
surface, pinned shortcuts, unavailable warning treatment, provider expansion,
and capability/pricing line. The XCUITest also mutates an unresolved pin and a
catalog pin by stable selector. A separate exact-source production-shell state
now passes the paired quantitative comparer at SSIM `0.976389`, outlier
fraction `0.007127`, and mean absolute channel delta `0.864652`. All 13
image-derived landmarks and four exact flat-color samples pass with zero masks,
and the native-scale manual review is accepted.

The session-rename fixture uses the production session shell on both
platforms. It proves the selected live session opens the Android-copy dialog,
preserves its current title, exposes semantic Cancel and Save controls, trims a
saved title into the header, and discards a later canceled edit. Its zero-mask
comparison passes at SSIM `0.913306`, outlier fraction `0.036201`, and mean
absolute channel delta `3.491085`. The 320-point panel width matches exactly,
all six panel/field/notice landmarks are within `0.67` point, all three sampled
flat colors match exactly, and native-scale review is accepted under the
user-approved native cross-platform presentation tier.

The goals/telemetry/delegation fixtures confirm the Android graphite hierarchy,
standing-goal quick starts and budget controls, pinned active-goal card,
right-aligned context totals and categorized meter, activity summary cards and
heatmap, compact active delegation overview, expanded hierarchy rail and
controls, and settled transcript placement. The creation sheet now also has a
pinned exact-source Android production-shell checkpoint. Its interaction test
proves the ordinary composer draft survives, applies the source quick start,
selects the 10-turn budget, and enables Start. The paired zero-mask comparison
passes at SSIM `0.832805`, outlier fraction `0.098630`, seven image-derived
landmarks, and four exact flat-color samples under the user-approved native
cross-platform presentation tier. The production-shell active card and its
collapsed details sheet now have pinned Android screenshots and semantics too.
Their zero-mask comparisons pass at SSIM `0.856523`/outlier `0.052735` and
SSIM `0.848625`/outlier `0.084417`, respectively. Three card landmarks, eight
details landmarks, and eight combined exact flat-color samples all pass within
`1.67` points. The selector-driven iOS journey also proves a launchpad quick
start updates the composer, then opens, expands, pauses, and continues the exact
active goal.

The exact-commit mixed-delegation state is now paired too. It preserves one
working, one failed, and one finished agent; the expanded working row exposes
its activity, tool, model, toolset, token, file, Stop, and open-child details.
The zero-mask comparison passes the approved native-presentation tier at SSIM
`0.889339` and outlier fraction `0.049678`. Seven image-derived landmarks
confirm the panel and three agent-row bounds, five exact flat-color samples
confirm the graphite, blue, green, and red state colors, and manual review is
accepted.

The exact-commit context-breakdown state is now paired as well. Both platforms
show 124.0k of 200.0k tokens at 62%, with the same System prompt, Tool
definitions, Rules, Skills, Conversation, and free ordering and values. Its
zero-mask comparison passes at SSIM `0.822102` and outlier fraction `0.083586`.
The sheet edge, stacked-bar edge/height, and first segment width differ by at
most `0.67` point; all seven category/surface colors match exactly, and
native-scale manual review is accepted under the approved cross-platform
presentation tier.

The exact-commit 30-day gateway-statistics state is now paired too. Both
platforms show the same selected period, totals, momentum, metric cards,
90-day contribution heatmap projection, latest dates, models, tools, and
skills over the production session shell. Its zero-mask comparison passes at
SSIM `0.854220` and outlier fraction `0.098091`. Eight image-derived landmarks
cover the sheet, momentum card, summary cards, recent-activity divider, and
heatmap cell geometry within `1.34` points; all six sampled sheet, card,
selection, and heatmap colors match exactly. Native-scale manual review is
accepted under the approved cross-platform presentation tier. The iOS
test-only reference date is fixed to the source-capture day, so the tracked
baseline remains deterministic while production statistics continue using
live UTC time.

The mandatory retained `nile-media.png` state is quantitatively paired too.
The iOS fixture uses the exact terminal identifier, prompt, response, filename,
MIME type, and preview PNG bytes from the Android test-lab recipe. It exercises
the production read-only shell and exposed a real parity defect: the workspace
header previously showed only `CLI`; it now shows Android's exact
`CLI · read-only mirror` copy while retaining the Claim action and omitting the
editable composer. Its attachment action is now a muted monochrome symbol
rather than an emoji-rendered arrow tile. The historical Android frame has a
taller responsive viewport, so its manifest crops only the 63-pixel Android
status bar and removes a 227-pixel full-width `#181818` band wholly inside the
source's 535-pixel blank transcript spacer before normalization.
Every removed pixel is validated exactly and every rendered UI pixel remains
compared; no mask is used. The comparison passes at SSIM `0.855411`, outlier
fraction `0.067721`, and mean absolute channel delta `9.255635`. The selected
session, attachment card, and read-only card left edges are within `1.72` points,
and the canvas, selected surface, and read-only surface colors match exactly.

## Quantitative comparer

`scripts/visual/compare.sh` implements the repository-owned comparison gate.
Its self-test proves that a narrow, justified timestamp mask can pass, a visible
layout/color change fails, an oversized mask is rejected, an exact solid
responsive spacer can be removed, and a spacer containing any non-background
pixel is rejected. The comparer:

- decodes both PNGs into sRGB and normalizes them deterministically;
- permits only top and bottom OS-chrome crops and rejects side crops;
- optionally removes an internal full-width flat-color responsive spacer only
  after exact per-pixel validation and a 10%-of-content size bound;
- checks exact flat-color samples before normalization;
- extracts landmark edges, spans, and run sizes from bounded color probes over
  the native cropped source/capture pixels, then compares their deltas;
- emits normalized reference and candidate images, diff, heatmap, mask,
  measurements, and a machine-readable result.

Schema 2 manifests declare the scan axis and bounds, target color, optional
bounded channel tolerance and minimum contiguous-run size, and the measurement
to extract. Reference and candidate must use identical probe instructions, and
the manifest cannot supply either measured coordinate. The self-test changes
candidate pixels and proves that an extracted landmark delta fails.

Allowed masks:

- status bar and home indicator
- text insertion cursor
- explicitly identified timestamps
- genuinely dynamic animation pixels

Broad masks, blur, and oracle replacement are forbidden. Flat app regions must
match exact token colors; important geometry may differ by at most two points.
The strict default remains SSIM 0.97 with at most 3% of pixels exceeding an
18-level per-channel difference. An explicitly reviewed native cross-platform
presentation may use the user-approved SSIM 0.82/10% tier, but only with exact
fixture state, copy, flat colors, 2-point landmarks, no broad masks, and manual
acceptance. No plainly visible functional, content, state, color, or material
geometry mismatch may pass either tier.

The current pinned-source onboarding checkpoint passes at the exactly matched
app-owned viewport. The clean fixture reports SSIM `0.998730` and outlier
fraction `0.000438`; the expanded form reports SSIM `0.996220` and outlier
fraction `0.001113`. All 23 image-derived landmarks, every flat-color sample,
and both manual reviews pass with no mask. Development evidence is retained at
`build/visual-dev-20260724T140426Z/`. The fresh-Simulator visual lane also
captures the model picker, standing-goal creation sheet, active goal card, and
active goal details sheet. It passed all six comparisons, its comparer
self-test, no-Nile-crash check, all-file secret scan, and Simulator cleanup at
`build/test-lab-results/20260724T192044Z-92852/`.
The current nineteen-state lane additionally captures the production-shell
rename dialog, long-history/syntax tail, attachment composer/media cards,
canonical brand chat, expanded brand sessions, retained media, mixed
delegation, the context breakdown, gateway statistics, active-gateway removal,
running-turn gateway switching, the loaded global Hermes voice sheet, and Talk
listening. All nineteen comparisons, the same safety gates, and cleanup pass at
`build/test-lab-results/20260725T082058Z-97729/`. The canonical chat and session
results reproduce the zero-mask metrics above; media reports
SSIM `0.855411` and outlier fraction `0.067721`, syntax tail reports
`0.935771` and `0.028354`, the current rename result is SSIM `0.929240` and
outlier fraction `0.030193`, statistics reports SSIM `0.862046` and
`0.096049`, removal reports `0.931439` and `0.030375`, and switching reports
`0.906843` and `0.033835`. Hermes voice reports SSIM `0.872254`, outlier
fraction `0.085222`, and mean absolute channel delta `7.022960`; its eight
landmarks are within two points, its `#212121`, `#242424`, `#00284D`,
`#0D0D0D`, and `#3C3C3C` samples match exactly, and it uses no masks. Talk
listening reports SSIM `0.987325`, outlier fraction `0.007053`, and mean
absolute channel delta `0.916477`; its six orb/control landmarks have exactly
zero-point delta, all five colors match exactly, and it uses no masks. Every
exact-color, landmark, manual-review, no-crash, secret-scan, and
disposable-Simulator cleanup gate passes.

The calibration now reproduces Compose's greedy wrapping for the two affected
multiline labels through a `UILabel` whose paragraph line-break strategy is
empty. UIKit's default standard strategy can push a fitting final word onto the
next line to avoid an orphan. It also preserves the 64-point Material
OutlinedTextField layout/semantics slot around a 56-point bottom-aligned visible
outline, prevents disabled-state environment dimming from changing Android's
explicit colors, uses inside borders, and applies small cross-renderer tracking
and glyph-coverage corrections. Those are general renderer/geometry
calibrations; the two onboarding production strings contain no forced
fixture-only line break. The rename notice separately uses the same deterministic
line division Compose produces inside the canonical 320-point dialog while its
accessibility label preserves the uninterrupted source sentence. The form panel
uses an 11.5-point SwiftUI raster radius to reproduce the visible edge of
Compose's 12-point rounded path at this pixel phase while retaining the 12-point
design token.

Apple documents the relevant label and paragraph behavior:

- [UILabel line-break strategy](https://developer.apple.com/documentation/uikit/uilabel/linebreakstrategy)
- [Standard line-break strategy](https://developer.apple.com/documentation/uikit/nsparagraphstyle/linebreakstrategy-swift.struct/standard)
- [No line-break strategy](https://developer.apple.com/documentation/uikit/linebreakstrategy/nslinebreakstrategynone)

Settings and gateway onboarding now use a checked-in, reproducibly built static
renderer based on Android's pinned FreeType 2.13.2 and HarfBuzz 8.2.2 sources.
It reproduces Minikin word-piece and tracked-line shaping, Compose baseline
steps, and Skia A8 gamma correction. Pixels outside glyph coverage remain
transparent so precomposited Android glyph edges do not obscure SwiftUI
borders. The build script, source pins, source, headers, licenses, device slice,
and universal Simulator slice live under `Vendor/AndroidTextRenderer/` and
`scripts/vendor/`.

`scripts/visual/manifests/onboarding.json`,
`scripts/visual/manifests/onboarding-form.json`,
`scripts/visual/manifests/model-picker-app-popup.json`,
`scripts/visual/manifests/rename-session-dialog.json`,
`scripts/visual/manifests/goal-quick-start-sheet.json`,
`scripts/visual/manifests/goal-active-card.json`,
`scripts/visual/manifests/goal-active-details-sheet.json`,
`scripts/visual/manifests/delegation-mixed.json`,
`scripts/visual/manifests/context-breakdown-sheet.json`,
`scripts/visual/manifests/gateway-stats-sheet.json`,
`scripts/visual/manifests/gateway-removal-dialog.json`,
`scripts/visual/manifests/gateway-switch-dialog.json`,
`scripts/visual/manifests/hermes-voice-settings.json`,
`scripts/visual/manifests/talk-listening.json`,
`scripts/visual/manifests/brand-chat.json`,
`scripts/visual/manifests/brand-sessions.json`,
`scripts/visual/manifests/transcript-syntax-tail.json`,
`scripts/visual/manifests/attachment-composer-and-media-cards.json`, plus the
retained-oracle `scripts/visual/manifests/media.json`, bind Android baselines
to disposable XCUITest captures. The visual lane runs all nineteen
comparisons and retains their normalized inputs, diffs, heatmaps,
measurements, and machine-readable outcomes.

The separately retained historical onboarding fixture reports SSIM `0.710951`
and outlier fraction `0.232190` with the corrected OS crop. Its much larger
failure records the source/screenshot conflict; it is not a target for the
current implementation.

## Remaining fixture inventory

Deterministic iOS fixtures now cover both onboarding states, approvals, each
blocking-prompt kind, attachments, model selection, session rename, Hermes
voice configuration, and Talk mode. Onboarding, the production-shell model
picker and rename dialog, standing-goal creation/active states, and the
mixed-delegation state have paired Android quantitative passes. Canonical chat,
expanded sessions, and the retained media/read-only state now have paired
Android quantitative passes too. The long-history/syntax tail is now paired;
gateway removal, running-turn gateway switching, and the loaded Hermes voice
sheet are paired; Talk listening is now paired too. Other transcript and
gateway-management states still need pairs.
Gateway statistics now has one paired 30-day state, while its
loading/error/alternate-period states and the other surfaces still need paired
coverage. The full-screen Talk capture now has a quantitative source pair for
the graphite surface, 64-point Material header, 188/172/132/84-point orb stack,
status hierarchy, and 92-by-75-point bottom controls. Its authoritative Android
PNG and all-root semantics hashes are
`93e65e8191936ab69426b82aac98ad88d09fab69b3f0fdd84c3e9f83eb5d66c1`
and `026ccd3956661be8047df9c804425af96323b5e940bc4f0208e5330b0352069c`.
The Hermes voice capture covers provider summary, current voice, preset chips,
custom identifier field, global-change warning, and apply/close states. Its
authoritative exact-commit Android PNG and all-root semantics hashes are
`61c7c77ca4e48a557d180bc83a3c3fbc692d61794b4e6467bb2ce7ea24ba0e27`
and `bf8a4eef859851c55c50348a7b2ea31a40bd680937a3b7d2b4a0b3da4c5c0a4d`.

Current speech captures are exported under
`build/checkpoints/speech-talk-ui-full/`; the authoritative XCTest bundle is
`build/TestResults/SpeechTalkUIFull.xcresult`. Goals, statistics, context, and
delegation captures are under
`build/checkpoints/goal-usage-delegation-ui-final/`. Add paired Android/iOS
fixtures for statistics empty/loading/error and alternate-period states, plus
the remaining gateway-management states. The iOS
offline, reconnecting, and restoring fixtures are verified in the full
`build/ReconnectUIFullFinal3.xcresult` regression, with inspected focused-lane
captures under `build/checkpoints/reconnect-ui/`. The gated sign-in iOS fixture is under
`build/checkpoints/auth-ui-final/`; its paired Android capture and quantitative
comparison remain. The Android-copy notification education fixture is verified
by selectors and manually inspected under
`build/checkpoints/background-notification-ui/`; its paired Android capture and
quantitative comparison remain. The transcript scroll/syntax fixture is under
`build/checkpoints/transcript-scroll-ui-final/`; its production-shell
long-history tail pair is retained under
`build/test-lab-results/20260725T040036Z-68713/`.
