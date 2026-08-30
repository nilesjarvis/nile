# Disposable iOS and Hermes test lab

## Current state

The repository-owned macOS/iOS driver now exists under `scripts/test-lab/`.
It exposes read-only prerequisite inspection plus independent `unit`, `ui`,
`accessibility`, `visual`, `smoke`, `installer`, `drive`, and `full` lanes. Each
executable lane records its own result instead of aborting later `full` evidence
after the first failure. Until `./scripts/test-lab/run.sh full` passes on the
final tree, no full-lab or port-completion claim is valid.

The lab creates a new iPhone 17 Pro/iOS 26.5 Simulator rather than reusing the
developer's canonical device. It uses temporary DerivedData, `HERMES_HOME`,
Hermes checkout, workspace, managed dependencies, and random loopback port.
Cleanup captures app logs and a final screen, stops Hermes, deletes the
Simulator, captures any Nile crash report created after the run starts, scans
every retained file for the exact disposable dashboard token and provider key,
and removes the temporary lab. A captured crash makes the run fail.

The current deterministic transport lane uses actor-backed socket and HTTP
doubles to force handshake timeouts, overlapping connects, out-of-order
responses, cancellations, stale buffered events, a 100-event burst followed by a
close, malformed frames, and authentication/policy failures. This validates the
client state machine but does not replace the required real-Hermes smoke lane.

## Current reproducible checks

Inspect all prerequisites without changing the workspace:

```bash
./scripts/test-lab/doctor.sh full
```

Run the static analysis, 410 unit/protocol tests, and unsigned optimized Release
build in one disposable lane:

```bash
./scripts/test-lab/run.sh unit
```

Run the 38 deterministic selector-driven UI scenarios and export their retained
attachments:

```bash
./scripts/test-lab/run.sh ui
```

Run the dedicated accessibility-extra-large content-size journey. It verifies
scaled custom typography and controls, 44-point-or-larger semantic targets,
reduced-motion propagation, Name → URL → secure-token keyboard actions, and
secure-value redaction before restoring the Simulator's content size:

```bash
./scripts/test-lab/run.sh accessibility
```

The implementation uses Apple's relative custom-font scaling and native Reduce
Motion environment value:

- [Scaling a custom font relative to a text style](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:))
- [Dynamic Type size](https://developer.apple.com/documentation/swiftui/dynamictypesize)
- [Reduce Motion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)

Capture both onboarding states, canonical brand chat and expanded sessions,
the retained pinned media/read-only state, the production-shell
long-history/syntax tail, attachment composer plus transcript media/file cards,
model picker and rename dialog, three standing-goal states, mixed delegation,
the context breakdown, gateway statistics, active-gateway removal, and
running-turn gateway-switch confirmations, loaded Hermes voice settings, and
the Talk listening surface from the disposable Simulator, then execute the
comparer self-test plus all nineteen mandatory Android/iOS comparisons:

```bash
./scripts/test-lab/run.sh visual
```

The accepted zero-mask manifests use the strict default or the user-approved
native-presentation tier, exact flat-color checks, image-derived landmarks, and
native-scale manual review. The current nineteen-state lane at
`build/test-lab-results/20260725T082058Z-97729` reports clean onboarding SSIM
`0.991736` / outlier fraction `0.003976`, expanded-form SSIM `0.972041` /
`0.014974`, gateway-removal confirmation `0.931439` / `0.030375`,
running-turn gateway-switch confirmation `0.906843` / `0.033835`, loaded
Hermes voice settings `0.872254` / `0.085222`, Talk listening `0.987325` /
`0.007053`, canonical chat `0.828341` / `0.071415`, expanded sessions
`0.947338` / `0.023988`, retained media `0.855411` / `0.067721`,
long-history syntax `0.935771` / `0.028354`, attachment composer/media cards
`0.922386` / `0.032650`, model-picker `0.976733` / `0.007045`, rename dialog
`0.929240` / `0.030193`, standing-goal creation `0.848032` / `0.094858`,
active goal card `0.872797` / `0.046814`, active goal details `0.864403` /
`0.080261`, mixed delegation `0.907515` / `0.044526`, context breakdown
`0.837718` / `0.079870`, and gateway statistics `0.862046` / `0.096049`.

Verify only that fresh Hermes installs cleanly at the exact compatibility pin:

```bash
./scripts/test-lab/run.sh installer
```

Run the credentialed production journey or all gates:

```bash
./scripts/test-lab/run.sh smoke
./scripts/test-lab/run.sh full
```

## Implemented lanes

| Lane | Current contract |
| --- | --- |
| `unit` | Debug analysis, 410 Swift unit/protocol tests, including deterministic Android-renderer and adaptive-composer verification, plus an unsigned optimized Release build with warnings as errors |
| `ui` | fresh Simulator, 38 deterministic XCUITests, `.xcresult`, screenshots, and exported attachment manifest |
| `accessibility` | fresh Simulator at accessibility-extra-large, one focused XCUITest for scaling, reduced motion, semantic target sizes, keyboard progression, and secure-value redaction; content size is restored before cleanup |
| `visual` | comparer self-test, fresh clean/form onboarding, canonical brand-chat/expanded-session shell, retained pinned media/read-only state, production-shell long-history/syntax and attachment-composer/media-card states, model-picker and rename dialog, three standing-goal states, mixed-delegation, context-breakdown, gateway-statistics, active-gateway removal, running-turn gateway-switch, loaded Hermes voice-settings, and Talk-listening captures, tracked pinned-Android baselines, normalized inputs, measurements, diffs, heatmaps, masks, and review outcomes |
| `installer` | disposable hash-verified Hermes install at `7441e339…`, clean checkout check, import check, and version |
| `smoke` | pre-build production app; fresh pinned Hermes and CLI-owned session; invalid auth; read-only discovery; observable five-second persisted-history refresh; Claim; model/reasoning acknowledgements; real turn; interrupt; two-turn goal; server outage; reconnect/relaunch restoration; exported result summaries/checkpoints with raw credential-bearing `.xcresult` bundles destroyed |
| `drive` | production app, fresh isolated Hermes, disposable Simulator, and printed one-use local connection details until Ctrl-C |
| `full` | records unit, UI, visual, accessibility, and smoke-build outcomes on one invocation; blocks the paid Hermes fixture/smoke when any deterministic prerequisite is red |

`doctor.sh` must remain read-only. All real-Hermes lanes must use a temporary
`HERMES_HOME`, a random loopback port, and a disposable Simulator/app container.
They must never read the operator's normal Hermes profile.

## Current retained verification

- `build/test-lab-results/20260724T071532Z-66378`: `doctor` and fresh
  hash-verified `installer` passed at the exact Hermes pin.
- `build/test-lab-results/20260725T082723Z-4481`: the current unit lane passed
  `doctor`, disposable setup, analyzer, 410/410 unit/protocol tests, unsigned
  Release build with warnings as errors, all-file secret scan, no-crash check,
  and Simulator cleanup. It includes the pinned Android paragraph-wrap and
  adaptive 56/70.67-point composer regressions plus empty-session creation,
  production repository creation/selection, exact secondary mutation guards, protected
  pre-create text flush/fail-closed behavior, live-session text/photo parking
  and restore, ordinary missing-owner photo promotion before the create RPC,
  exact text transfer, atomic multi-marker prompt/photo migration, migration
  failure/relaunch behavior, a stale-gateway commit race, and the collapsed
  strip's exact claim, resistance, edge, and fling policies.
- `build/test-lab-results/20260724T224854Z-72424`: the rename checkpoint's unit
  lane passed
  `doctor`, disposable setup, analyzer, 373/373 unit/protocol tests, unsigned
  Release build with warnings as errors, all-file secret scan, no-crash check,
  and Simulator cleanup.
- `build/test-lab-results/20260725T083216Z-10354`: the current UI lane passed
  `doctor`, disposable setup, and 38/38 deterministic UI tests. The
  gateway-removal journey proves cancellation preserves the profile,
  confirmation is required, and confirmation reaches the empty saved-gateway
  state through the production model path. The running-turn gateway-switch
  journey separately proves that Stay here preserves Home Hermes and that only
  Switch gateway reaches the Lab Hermes session shell. The media
  journey proves the exact read-only header, deterministic transcript/image
  card, Claim reachability, and absence of an editable composer alongside all
  existing selector-driven scenarios. The production-shell syntax-tail and
  attachment-composer scenarios additionally verify exact copy and state while
  retaining screenshots plus accessibility hierarchies. The Hermes voice
  journey verifies the exact loaded state, disabled-to-enabled Apply
  transition, global summary update, and 46.1-point handle/preset/Apply/Close
  semantic heights. The Talk journey additionally verifies the source-sized
  Close/Transcript/Pause/End targets, private-copy guarantees, pause/resume,
  and return to the ordinary composer. The lane exported the attachment manifest, passed
  the all-file secret scan, and deleted the fresh Simulator.
- `build/test-lab-results/20260725T084227Z-18388`: the current dedicated
  accessibility-extra-large journey passed 1/1 with reduced motion, keyboard
  progression, semantic target sizing, screenshot/hierarchy export, content
  size restoration, secret scan, and fresh-Simulator cleanup.
- `build/test-lab-results/20260725T082058Z-97729`: the current nineteen-state
  visual lane passed comparer self-test and every Android/iOS comparison with
  no masks, accepted native-scale reviews, exact-color and landmark gates,
  no-crash validation, all-file secret scan, and fresh-Simulator cleanup.
  Gateway removal reports SSIM `0.931439`/outliers `0.030375`, with five
  landmarks within `1.34` points and both colors exact. Gateway switching
  reports `0.906843`/`0.033835`, with six landmarks within `0.67` point and
  both colors exact. Hermes voice settings reports `0.872254`/`0.085222`,
  with all eight sheet/card/chip/warning/action landmarks within `2` points,
  all five colors exact, and zero masks. Talk listening reports
  `0.987325`/`0.007053` and MAE `0.916477`, with all six orb/control landmarks
  at zero-point delta, all five colors exact, and zero masks. Canonical chat reports
  SSIM `0.828341`/outliers `0.071415`; expanded sessions
  reports `0.947338`/`0.023988`; retained media reports
  `0.855411`/`0.067721`, with all three container edges within `1.72` points and
  all three colors exact. The new long-history/syntax state reports
  `0.935771`/`0.028354`, with all four landmarks within `1.34` points and all
  three colors exact. The attachment composer/media-card state reports
  `0.922386`/`0.032650`, with all five landmarks within `1.34` points and all
  four colors exact. An earlier integrated attempt at
  `build/test-lab-results/20260725T015545Z-47399` correctly rejected a fixed
  multiline composer height after it shifted one-line goal/delegation states;
  the adaptive 56/70.67-point implementation restored the existing states
  without changing any threshold, source baseline, or mask.
- `build/test-lab-results/20260724T220056Z-3919`: `doctor`, disposable setup,
  analyzer, 369/369 unit/protocol tests, unsigned Release build with warnings as
  errors, all-file secret scan, no-crash check, and Simulator cleanup passed.
- `build/test-lab-results/20260724T220505Z-8871`: `doctor`, disposable setup,
  and 27/27 deterministic UI tests passed; the source-paired model-picker,
  standing-goal, mixed-delegation, and context fixtures plus keyboard-adaptive
  search/pin journey passed, the attachment manifest was exported, the all-file
  secret scan passed, and the fresh Simulator was deleted.
- `build/test-lab-results/20260724T142733Z-21029`: the first post-renderer
  accessibility run correctly failed because the native gateway-name editor's
  semantic frame had collapsed to 37 points while its exact visual raster
  expanded. It retained the failure, screenshot, and clean secret scan.
- `build/test-lab-results/20260724T221130Z-20139`: after making the exact raster
  visual-only and filling the scaled native editor slot, the dedicated
  accessibility-extra-large journey passed 1/1, exported both inspected form
  screenshots plus a masked hierarchy, restored the content size, passed its
  all-file secret scan, and deleted its fresh Simulator.
- `build/test-lab-results/20260724T073108Z-79134`: comparer self-test and fresh
  capture/export completed; the visual lane then failed at the required strict
  legacy whole-screen SSIM/outlier/review gate. The current lane supersedes this
  with clean/form matched-viewport comparisons.
- `build/test-lab-results/20260724T115014Z-89283`: the exact-source XCUITest
  passed, four clean/form screenshot and hierarchy attachments were exported,
  and both strict matched-viewport comparisons retained complete result/diff
  bundles before the lane exited `1` for the documented metric and manual-review
  failures. All 23 image-derived landmark checks and all four flat-color checks
  passed without a mask. Cleanup and the all-file secret scan passed. The clean
  comparison reports SSIM `0.986563` and outlier fraction `0.010324`; the form
  comparison reports SSIM `0.952348` and outlier fraction `0.027576`.
- `build/test-lab-results/20260724T143404Z-28004`: the committed
  exact-renderer and accessibility-corrected tree passed `doctor`, disposable
  setup, comparer self-test, both fresh clean/form captures, every flat-color
  and image-derived landmark check, accepted native-scale manual review,
  no-crash validation, the all-file secret scan, and Simulator deletion. No
  mask was used. Clean reports SSIM `0.998730` and outlier fraction `0.000524`;
  form reports SSIM `0.996220` and outlier fraction `0.001329`.
- `build/test-lab-results/20260724T164959Z-30802`: the expanded three-state
  visual lane passed `doctor`, fresh Simulator setup, comparer self-test,
  onboarding clean/form and production-shell model-picker XCUITest captures,
  every flat-color and image-derived landmark check, accepted native-scale
  reviews, no-crash validation, all-file secret scan, and Simulator deletion.
  No mask was used. Clean reports SSIM `0.998730` / outliers `0.000438`; form
  reports `0.996220` / `0.001113`; model picker reports `0.976389` /
  `0.007127`, with 13 landmarks and four flat-color samples.
- `build/test-lab-results/20260724T175412Z-9023`: the superseding four-state
  lane passed `doctor`, fresh standard-content-size Simulator setup, comparer
  self-test, all captures and comparisons, every landmark and exact flat-color
  sample, native-scale reviews, no-crash validation, all-file secret scan, and
  Simulator deletion. No mask was used. The first three metrics reproduce
  exactly; the goal sheet reports SSIM `0.832805`, outliers `0.098630`, all
  seven landmarks within `0.34` point, and all four exact colors.
- `build/test-lab-results/20260724T202848Z-37346`: the previous seven-state lane
  passed all earlier comparisons plus active-goal card/details and mixed
  delegation, comparer self-test, every exact color and landmark gate,
  native-scale review, no-crash validation, all-file secret scan, and cleanup.
  The mixed-delegation comparison has no masks, reports SSIM `0.888724` and
  outliers `0.050518`, and matches all seven checked landmarks exactly.
- `build/test-lab-results/20260724T210357Z-11708`: the superseding eight-state
  lane passed all seven earlier state contracts plus the context breakdown,
  comparer self-test, exact-color and landmark gates, native-scale review,
  no-crash validation, all-file secret scan, and fresh-Simulator cleanup. The
  context comparison uses no masks, reports SSIM `0.822102` and outliers
  `0.083586`, matches all seven exact colors, and keeps all four checked
  landmarks within `0.67` point.
- `build/test-lab-results/20260724T221324Z-22312`: the superseding nine-state
  lane passed all eight earlier contracts plus gateway statistics, comparer
  self-test, exact-color and landmark gates, native-scale review, no-crash
  validation, all-file secret scan, and fresh-Simulator cleanup. The statistics
  comparison uses no masks, reports SSIM `0.854220` and outliers `0.098091`,
  matches all six sampled colors, and keeps all eight checked landmarks within
  `1.34` points.
- `build/visual-dev-20260724T140426Z`: post-renderer development capture. Both
  clean/form strict comparisons pass with accepted manual review, all
  landmarks and colors green, no masks, and metrics `0.998730`/`0.000524` and
  `0.996220`/`0.001329`, respectively. The disposable result above reproduces
  this development evidence exactly.

Comparer schema 2 extracts 10 clean-state and 13 form-state landmarks from
bounded scans over the native cropped PNG pixels. The manifests provide probe
instructions but no result coordinates, and reference/candidate instructions
must be identical; the self-test proves that moving the candidate pixels makes
the landmark gate fail.

The three-phase production XCUITest bundle compiles through
`build/DerivedData-SmokeCompileFinal`. It has not yet been executed with a
provider credential, so no real-model, goal, outage, reconnect, or complete
`smoke` pass is claimed.

## Android oracle limitation on this host

The Android repository's existing full lab is deliberately Linux-specific. Its
environment scrubber reads `/proc/<pid>/environ`, and later isolation relies on
Linux/KVM/network controls. Running its doctor unmodified on this Mac fails
before prerequisite discovery. Do not weaken that lab to make it appear portable;
run it on its intended isolated Linux runner and retain only sanitized results.
The Android source, tests, screenshots, Gradle unit build, and protocol fixtures
remain available to the iOS work on macOS.

## Android source captures on this host

The macOS host now has the source-capture subset installed and verified:

- OpenJDK 17.0.20
- Android command-line tools `14742923`
- platform tools 37.0.1
- Android SDK 35 and Build Tools 35.0.0/36.0.0
- Android Emulator 36.6.11
- `system-images;android-35;google_apis;arm64-v8a`
- Node.js 26.5.0 with npm/npx 11.17.0

Homebrew's JDK is force-linked so `java`, `sdkmanager`, `adb`, `avdmanager`, and
`emulator` resolve from the ordinary command path. The SDK root is
`/opt/homebrew/share/android-commandlinetools`.

A disposable Pixel 6/API 35 AVD at 1080 × 2400, 420 dpi built and launched the
pinned source APK successfully. The ignored APK is
`.reference/android/app/build/outputs/apk/debug/app-debug.apk` with SHA-256
`0555e430eb6d06708a43cc04d8dc669fd6e40de5f5789ccc2b2aae431bd6400d`.
The tracked matched-viewport clean/form screenshots and UIAutomator hierarchies
are under `scripts/visual/baselines/android/`. Reproduce them without touching
the oracle or normal AVDs with `./scripts/visual/capture-android.sh`.

`assembleDebugAndroidTest` is not currently a passing Android lane: the pinned
repository's existing `SessionSourceLabelTest.kt` does not compile against its
resolved Compose test API because `assertDoesNotExist` and `assertExists` are
unresolved. This does not invalidate the app APK or source captures, but no
Android instrumentation-pass claim is permitted until that pinned-runner issue
is resolved without modifying the oracle.

## Credential handling

- Do not export, echo, log, or commit provider credentials.
- Request a real-model key only after build, Simulator, Hermes installation, and
  public catalog gates pass.
- For non-interactive use, pass a non-symlink, mode-600, one-line handoff through
  `NILE_LAB_OPENROUTER_KEY_FILE`; the runner opens it, removes it before reading,
  and rejects extra lines or malformed keys.
- Interactive runs read silently from `/dev/tty`.
- The public catalog must contain both selected models. The default price cap is
  $0.50 per million input tokens and $2.00 per million output tokens; an
  expensive override must be explicit.
- Redact tokens, cookies, passwords, OAuth state, and audio from all artifacts.
- Scan every retained file for the exact credential before declaring a lane
  successful.

## Artifact contract

Final runs retain sanitized evidence under `build/test-lab-results/<run-id>/`:

- `lane-results.tsv`
- `run.properties`
- build and test logs
- `.xcresult` bundles or exported summaries
- app logs and crash reports
- checkpoint screenshots and accessibility hierarchies
- visual references, candidates, diffs, heatmaps, and metrics
- real-Hermes smoke checkpoints
- secret-scan result

The entire `build/` tree is ignored by Git.
