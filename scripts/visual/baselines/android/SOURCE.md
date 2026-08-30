# Pinned Android visual source

These screenshots and UIAutomator hierarchies were generated from the
read-only Android oracle with:

```sh
./scripts/visual/capture-android.sh
```

The canonical chat and expanded-session checkpoints run the pinned repository's
existing
`SessionShellUiTest.capturesDeterministicBrandScreens` test unchanged. The
connected model-picker, session-rename, goal, context-breakdown,
gateway-statistics, gateway-removal, and running-turn gateway-switch
production-shell checkpoints were
generated from a disposable exact-pin clone because they require additional
deterministic connected-session state. The clone changes test source only: it
applies the documented Android-test compile compatibility patch, mounts
`ModelPickerDialogContent` over the real `NileAppContent` shell, makes the
existing goal checkpoints print both Compose roots, opens the production rename
dialog over a deterministic live session, and adds a context capture with exact
usage totals and categories plus a 30-day statistics capture with deterministic
totals, momentum, daily activity, model, tool, and skill rows. It also adds a
long-history checkpoint that renders messages 32–40, the production syntax
block, and the final user bubble on the real connected-session shell, plus an
active-gateway removal checkpoint that opens the production confirmation dialog
without confirming the destructive action, and captures the existing
running-turn switch-confirmation journey before its first dismissal. It also
opens the real loaded Hermes voice sheet over `NileAppContent` with the
connected Edge TTS / Aria fixture and captures the provider, current voice,
presets, custom field, global-impact warning, disabled Apply action, and Close
action. The same test-only overlay renders the real `TalkScreen` in its
listening phase with the deterministic Brand polish session title and captures
the private-transcript-free header, orb, status/detail, and bottom controls.
The mixed-delegation checkpoint
runs the pinned repository's existing
`DelegationUiTest.mixedDelegationKeepsRowsStableAndExposesExpansionAndChildControls`
without altering it. The script verifies the patch only touches
`app/src/androidTest`, then builds the unchanged app-under-test and
instrumentation APK together so their isolated debug certificates match.
Production source and the pinned production APK remain byte-for-byte unchanged.

- Android commit: `bd5451da891f2d886b9bc35f8ea67d6920df1d98`
- Android tree: `3b954e5844f05276d34aaee34a7d3f69169ef9f5`
- APK SHA-256:
  `0555e430eb6d06708a43cc04d8dc669fd6e40de5f5789ccc2b2aae431bd6400d`
- The disposable app/test APK hashes are recorded in each capture's
  `source.txt`; their fresh debug certificate intentionally makes those hashes
  run-specific.
- System image: `system-images;android-35;google_apis;arm64-v8a`
- Display: 1206 by 2478 pixels at 480 dpi
- Cropped system chrome: 72 pixels top and bottom
- Compared app viewport: 1206 by 2334 pixels, or 402 by 778 points at 3x

Tracked capture hashes:

- `onboarding-clean.png`:
  `41d0873e1f5e4877f39f66169d0348c1300ac94e0bb9d3c52d26553133904db0`
- `onboarding-form.png`:
  `9dc1053b3f55d7ce3081efd437641434d4af3130efaed0d3c77cf967fde89065`
- `onboarding-clean.xml`:
  `964357ae9a0cab64b63b558f68a4270ba0d1269fe53d2c35cfeb31364a298444`
- `onboarding-form.xml`:
  `822e146341ff4ea5b812d49e1c53d226f9ebad4a087b458c398e479f3d41bced`
- `brand-chat.png`:
  `e63f354995eaf86a2796336dabaa8103fe1a9fce1b841eb60027f51a96bf87ed`
- `brand-chat-semantics.txt`:
  `2be8d561b46cf0ec3f5b7e306a4c267eeaaba5c70a97e2848ede47a2ea117abf`
- `brand-sessions.png`:
  `0ec7441fc8c333031f1a335b46c11df06c6c4c505cf3418268b1654d86b62b1b`
- `brand-sessions-semantics.txt`:
  `a5c3031c66061d8db12e080a80dc4a353179717cd77ce7cab9c8fee736e2a8e0`
- `model-picker-app-popup.png`:
  `f73039148e3ce52e319d4d6cead7b1c49a091ee673558fbf621b61998f1a06b1`
- `model-picker-app-popup-semantics.txt`:
  `3b7c7f48eeea5588e13862d45f9ab6ed5cbf5b6b61cd41ead942977867dad27d`
- `rename-session-dialog.png`:
  `d3e829044f5caef9e328b3955c2715319ff44a1c454323ea2b83a05eee123719`
- `rename-session-dialog-semantics.txt`:
  `23ea77c05f131a956bdb418178efa90911be97927a8e14110f7246d48efd0f7c`
- `goal-quick-start-sheet.png`:
  `af3af49dfc67655cab779d671c23bba02af8ac13dd5b5148c3d4584f2558c8ae`
- `goal-quick-start-sheet-semantics.txt`:
  `8b0c179fc9810fae03b7aa98e31e442d45d2bd64bdb3f3296dea234db2420824`
- `goal-active-card.png`:
  `cba47e0f1d6b0bba5392cfac21b19e252246a667d3d41e482c7b4fc7fb2bd8b8`
- `goal-active-card-semantics.txt`:
  `6ad0c98816d13f461a5498c0a1b7b6898e886f4da5d64aa08d8c7f11d5b24813`
- `goal-active-details-sheet.png`:
  `9cadc8b1776a9e74bba8a0bd84f840aa89e2a8c4cbe07c0208740cdd4f8540b2`
- `goal-active-details-sheet-semantics.txt`:
  `8671a9a1c6a95061e337aedd29b9c8f39f2c18ffb50cada87806e67713a47f0a`
- `transcript-syntax-tail.png`:
  `b2e0a93471f503374cd0ef3b53d995f9a3ca0f0906735e1babffed00d4be44ee`
- `transcript-syntax-tail-semantics.txt`:
  `c2c0da3f0638a77d606ad5691c045fa30ea0ae2cc493d96ad7ca0ba3e3f7f0ad`
- `delegation-mixed.png`:
  `a906fb79dab9931bff46bb66a339186a17804b7d3546e6af32e308f79de1dc8b`
- `delegation-mixed-semantics.txt`:
  `a2bee56b190958fb1bd9c47a567be1705897b3fd85ca0808d878a36c8c108042`
- `context-breakdown-sheet.png`:
  `3b45b6a38f25e6e1513373fb4c7a99118d1969933f76347029dea295cd671c44`
- `context-breakdown-sheet-semantics.txt`:
  `7444f27828cc4833f8a7de914feed173676ada3f7b5596d33fa0eea61ee82567`
- `gateway-stats-sheet.png`:
  `5acfa133d6809940a8f96a24a56ad6adaed91cd28216366709b257ece1f9eec3`
- `gateway-stats-sheet-semantics.txt`:
  `1b5373e8d16688822ef4f8637fcdd32a5c32f2324a67efe1f86dc1980dbeeeb8`
- `gateway-removal-dialog.png`:
  `a5690303736d94c121cd75d23f14b20faa45f529b61c2a6be0605bc34b40144e`
- `gateway-removal-dialog-semantics.txt`:
  `88ab66c7c6f21a2691485cf956c8819f42d2e063704405038329f9b6c6e94239`
- `gateway-switch-dialog.png`:
  `3e0c1a25e85552fa3954ece060bf482d5b7874c5f0cfb455c42a1971dbc2920c`
- `gateway-switch-dialog-semantics.txt`:
  `e5d8d93583505b22dbb66de10c39d0ec74055807b8b0219c0164f7c0d9c2440c`
- `hermes-voice-settings.png`:
  `61c7c77ca4e48a557d180bc83a3c3fbc692d61794b4e6467bb2ce7ea24ba0e27`
- `hermes-voice-settings-semantics.txt`:
  `bf8a4eef859851c55c50348a7b2ea31a40bd680937a3b7d2b4a0b3da4c5c0a4d`
- `talk-listening.png`:
  `93e65e8191936ab69426b82aac98ad88d09fab69b3f0fdd84c3e9f83eb5d66c1`
- `talk-listening-semantics.txt`:
  `026ccd3956661be8047df9c804425af96323b5e940bc4f0208e5330b0352069c`

The status-bar clock is system-owned and is cropped. The model-picker baseline
must begin directly below the canonical 72-pixel status bar; an extra inset
introduced by changing emulator density without a fresh AVD is not app-owned
geometry. Never replace these baselines from an iOS candidate. Regenerate them
only from the verified pinned source recipe, inspect the source hierarchy and
screenshot, and record the new source hashes.
