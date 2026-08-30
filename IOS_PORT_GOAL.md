# Nile iOS parity port — long-running Codex goal

Create a long-running Codex goal for the objective below and begin executing it. Continue across goal turns until every completion criterion is genuinely satisfied. Do not mark the goal complete merely because the app compiles, primary screens exist, or mocked tests pass.

## Objective

Build a production-quality native iOS port of Nile, written in Swift, in the current workspace. The iOS app must preserve the Android app’s complete functionality, behavior, state handling, security guarantees, and app-owned visual design.

The immutable Android reference is:

- Repository: https://github.com/nilesjarvis/nile
- Reference commit: `bd5451da891f2d886b9bc35f8ea67d6920df1d98`
- Reference tree: `3b954e5844f05276d34aaee34a7d3f69169ef9f5`
- Pinned Hermes commit: `7441e3395f9db0d8319f43bfe07dfb222777101e`

Clone the Android repository into a temporary or ignored reference directory and detach it at that exact commit. Treat it as read-only. Do not modify or push to the Android repository, and do not silently follow newer Android or Hermes commits.

The current iOS workspace may be empty. Create the complete iOS project, tests, documentation, and test lab here. Use local incremental commits, but do not push unless separately instructed. Preserve any pre-existing user work.

## Non-negotiable result

At completion, Nile must be an installable, launchable native iOS application that can connect to the same unmodified Hermes server and supports the same user journeys as the Android reference.

“Same functionality” means equivalent user-visible behavior, wire requests, event handling, persistence, restoration, error handling, security boundaries, and recovery behavior—not merely screens bearing the same names.

“Same design” means the app-owned content must preserve the Android
reference’s colors, typography, dimensions, spacing, shapes, icon geometry,
layering, motion, state treatments, copy, and interaction hierarchy. Do not
redesign it to look conventionally iOS-like. Native system-owned chrome such
as the status bar, home indicator, permission alerts, keyboard,
text-selection UI, and share sheet may remain native and may be excluded from
cross-platform pixel comparisons. Small rasterization and spacing differences
within the visual gate below are acceptable; missing content, wrong state,
wrong flat colors, or materially different geometry are not.

## Prerequisite gate

Before implementation:

1. Run `xcodebuild -version`, `swift --version`, and `xcrun simctl list`.
2. Require a complete Xcode installation with at least one available iPhone Simulator runtime.
3. If Xcode or Simulator is unavailable, report the exact prerequisite and continue only with work that can be truthfully verified without it. Never claim completion without successful Xcode builds and Simulator test drives.
4. Do not choose a personal Apple development team or commit personal signing data. Simulator builds and unsigned generic-device validation must work without personal signing.
5. Use a stable reverse-DNS bundle identifier such as `com.niles.Nile` unless an existing project configuration establishes another one.

## Durable project records

Create and maintain:

- `AGENTS.md` with the exact build, lint, test, simulator, snapshot, and test-lab commands.
- `docs/PARITY_MATRIX.md` mapping every Android feature, repository operation, stream event, screen, important state, and test suite to its iOS implementation and verification evidence.
- `docs/IOS_PORT_PROGRESS.md` with current phase, completed work, decisions, blockers, and the next concrete action.
- `docs/ARCHITECTURE.md` describing the iOS state, transport, persistence, authentication, audio, notification, and background-execution architecture.
- `docs/VISUAL_PARITY.md` recording source tokens, canonical viewports, screenshot fixtures, allowed masks, comparison metrics, and results.
- `docs/TEST_LAB.md` for the disposable iOS/Hermes validation environment.

These records must survive context compaction and allow another Codex turn to continue without guessing. Update them as work progresses; do not use them as a substitute for implementation.

## Phase 1: establish the Android oracle

Read, inventory, and understand:

- `AGENTS.md`
- `README.md`
- `docs/TEST_LAB.md`
- `docs/PRODUCT_ITERATION_GOAL.md`
- all production Kotlin files
- all unit and Android instrumentation tests
- all resources, vector assets, theme definitions, screenshots, manifests, build configurations, and test-lab scripts

The current reference contains roughly 121 production Kotlin files, 99 unit-test files, and 20 Android emulator-test files. Do not assume the README is exhaustive.

Run the Android reference’s appropriate baseline checks when the environment supports them:

- `./gradlew --offline lintDebug testDebugUnitTest assembleDebug`
- `./scripts/test-lab/doctor.sh full`
- relevant `unit`, `ui`, `smoke`, `audit`, or `full` lanes

Inspect the actual reports, screenshots, semantics, logs, and retained artifacts—not just exit codes. If the paid real-Hermes lane needs a credential, defer that lane until the deterministic work is ready and request the credential only through the reference test lab’s secure handoff. Never store or echo credentials.

Build the parity matrix before broad implementation. Each row must identify:

- Android source/test evidence
- required iOS behavior
- Swift implementation location
- unit or integration coverage
- UI-test coverage where applicable
- visual fixture where applicable
- current status
- final evidence

## Phase 2: iOS architecture

Use Swift and Apple-supported APIs. Prefer SwiftUI for app-owned UI, but use UIKit, Core Graphics, TextKit, WKWebView, or other native frameworks where SwiftUI alone cannot match the Android design or behavior accurately.

Use Swift concurrency and explicit isolation. Keep UI mutation on the main actor and make cancellation and object lifetimes deterministic. Favor immutable state models, protocol-based dependencies, reducers/coordinators where useful, and testable boundaries.

Mirror the Android separation of concerns:

- domain models and a `HermesRepository` protocol
- isolated REST/WebSocket transport and JSON codecs
- application state and feature coordinators
- encrypted persistence
- authentication and cookie handling
- media, audio, speech, notifications, and background restoration
- app UI and debug/test-only fixture injection

Use `URLSessionWebSocketTask` or an equally appropriate native implementation. Preserve connection generations, ordered event delivery, request correlation, reconnect/backoff behavior, session restoration, cancellation, malformed-frame rejection, and stale-event isolation.

Do not invent Hermes endpoints, patch Hermes, or rely on test-only server behavior. Inspect the pinned Hermes source read-only when the client contract is unclear.

## Phase 3: complete functional parity

At minimum, implement and verify all of the following:

- onboarding for dashboard URL, legacy token, and gated dashboard sign-in
- multiple gateway profiles, switching, removal, retry, and failure recovery
- secure credential persistence using Keychain and appropriate data protection
- explicit per-gateway confirmation for allowed cleartext local connections
- release configuration that rejects unsupported cleartext traffic
- gated sign-in in WKWebView without a JavaScript bridge
- visible current origin and confirmation before external OAuth navigation
- HttpOnly session-cookie retention, fresh single-use WebSocket ticket minting, logout, and safe cookie cleanup
- rejection of unsafe overlapping same-host gateway scopes
- session listing, searching, pinning, creation, opening, renaming, switching, and history
- read-only CLI/TUI session mirroring without accidentally resuming it
- five-second persisted-history refresh and explicit Claim confirmation
- live prompt submission, streaming, steering, stopping, retry, and cancellation
- deterministic transcript ordering and restoration
- Markdown, code, terminal, diff, tool, todo, system, thinking, and media presentation
- tool calls, plans, approvals, clarification prompts, sudo prompts, secret prompts, and “needs input” states
- model catalog, search, provider grouping, model pinning, expensive-model confirmation, session-only model switching, and reasoning effort
- slash-command discovery, completion, policy routing, and execution
- image selection, encoding, queued attachments, replacement/removal recovery, upload, inline preview, authenticated download, and opening/sharing
- standing goals, quick starts, turn budgets, automatic continuation, pause, resume, continue, clear, completion, and audit state
- delegated-agent progress, nested/child states, snapshots, details, session navigation, and interruption
- session usage, context breakdown, context-compaction state and completed-compaction count
- 7/30/90-day profile activity, token statistics, model/provider breakdown, and 13-week contribution heatmap
- voice recording, VAD, PCM/WAV encoding, Hermes transcription, Talk mode, pause/resume, interruption, spoken replies, chunked synthesis, voice selection, and cleanup
- offline, reconnecting, authentication expiry, stale state, malformed response, and partial-failure behavior
- draft persistence, per-session draft ownership, attachment recovery, and process-recreation restoration
- background turn continuity and completion/error notification behavior that reopens the correct gateway and session
- accessibility identifiers, VoiceOver semantics, focus order, contrast, touch targets, reduced motion, large text, and keyboard behavior

Map the Android `NileTestTags` values to stable iOS accessibility identifiers wherever practical so test intent remains comparable.

For Android-specific facilities, preserve the user outcome through documented Apple-supported mechanisms. Do not fake parity. In particular, investigate iOS background-execution limitations using current official Apple documentation. If timely background completion notifications cannot be achieved without backend push support or Hermes changes, implement the strongest legitimate behavior available, demonstrate it, and report the precise remaining limitation. Do not claim exact functional parity while an outcome remains impossible or unverified.

## Phase 4: exact visual reproduction

Derive a checked-in design-token specification directly from the Android sources. Important existing values include:

- background `#181818`
- panel `#212121`
- lowest/code surface `#0D0D0D`
- raised surface `#242424`
- border `#2A2A2A`
- primary text `#FFFFFF`
- prose `#D1D1D1`
- strong prose `#E3E3E3`
- muted text `#BABABA`
- link/running blue `#339CFF`
- warning `#FF8549`
- error `#FF6764`
- complete `#40C977`
- radii 8, 12, 24, and pill
- motion durations 150 ms, 240 ms, and 900 ms
- 1200 ms shimmer cycle

Verify all values against the pinned source rather than assuming this list is exhaustive.

Reproduce the Nile mark using the exact geometry in `NileBrand.kt`. Port local vector assets exactly. Do not replace Android icons with SF Symbols when their geometry differs. If Android typography resolves to Roboto, use the matching legally distributable font files and include their license so font metrics remain equivalent; do not silently substitute San Francisco in app-owned UI.

Use the six checked-in Android screenshots as initial mandatory visual oracles:

- `nile-onboarding.png`
- `nile-chat.png`
- `nile-sessions.png`
- `nile-media.png`
- `nile-goal.png`
- `nile-delegation.png`

Add deterministic fixtures for other important screens and states, including model selection, statistics, context details, voice configuration, Talk mode, approvals, blocking prompts, attachments, empty/loading/error/offline/reconnect states, and gateway management.

Create a deterministic cross-platform screenshot comparison tool. It must:

- normalize app-content scale and crop only system-owned chrome
- use fixed locale, timezone, appearance, Dynamic Type size, fixture copy, and animation state
- permit narrow masks only for system chrome, text cursor, timestamps, and genuinely dynamic animation pixels
- never use broad masks, blur, or baseline replacement to hide differences
- produce the candidate, normalized reference, diff image, heatmap, measurements, and machine-readable result
- measure important landmarks, baselines, insets, sizes, radii, and colors
- fail when an app-owned element moves by more than 2 points
- require exact token colors for flat app-owned regions
- require whole-screen app-content SSIM of at least 0.97 and no more than 3%
  of compared pixels exceeding an 18-level RGB-channel difference by default
- for explicitly reviewed native cross-platform presentation differences only,
  permit SSIM as low as 0.82 and at most 10% outliers after the user's approved
  wider margin; exact fixture state, copy, flat colors, 2-point landmarks,
  zero broad masks, and manual visual acceptance remain mandatory
- fail on any plainly visible mismatch even if aggregate metrics happen to pass

CoreText and Skia antialiasing may differ slightly, but font family, size, weight, line height, wrapping, bounding boxes, and baselines must match. Every accepted difference must have an explicit technical reason. Never update an iOS baseline merely to make a failing test green; compare it to the Android oracle first.

## Phase 5: self-verifying iOS test lab

Build an iOS equivalent of the Android disposable test lab with at least:

- `./scripts/test-lab/doctor.sh full`
- `./scripts/test-lab/run.sh unit`
- `./scripts/test-lab/run.sh ui`
- `./scripts/test-lab/run.sh visual`
- `./scripts/test-lab/run.sh smoke`
- `./scripts/test-lab/run.sh full`
- `./scripts/test-lab/run.sh drive`

The doctor command must be read-only. The lab must use a clean disposable Simulator, isolated app data, an isolated `HERMES_HOME`, the pinned Hermes commit, random loopback ports, and no access to the user’s normal Hermes profile.

Retain sanitized artifacts under `build/test-lab-results/<run-id>/`, including:

- `lane-results.tsv`
- toolchain, Simulator, app, Android reference, and Hermes versions
- build and test logs
- `.xcresult` bundles or exported summaries
- app logs and crash reports
- checkpoint screenshots
- accessibility/UI-hierarchy evidence
- visual references, candidates, diffs, heatmaps, and metrics
- real-Hermes smoke checkpoints
- a secret-leak scan result

Never retain credentials, cookies, passwords, audio captures containing real speech, or provider keys.

Testing layers must include:

1. Focused Swift unit tests for models, codecs, reducers, coordinators, persistence, endpoint validation, reconnection, stream ordering, stale generations, drafts, goals, delegation, speech, and attachment recovery.
2. Protocol-contract tests using recorded/sanitized JSON fixtures and a controllable local WebSocket/HTTP server.
3. XCUITests using accessibility identifiers and observable state rather than coordinates or arbitrary sleeps.
4. Snapshot and cross-platform visual tests.
5. Clean-install and process-relaunch restoration tests.
6. Real integration against a fresh unmodified pinned Hermes installation.
7. A manual or automated Simulator test drive of complete user journeys.

The real-Hermes smoke lane must, at minimum:

- prove an invalid credential fails closed
- connect through production transport and persistence
- discover a CLI-owned session
- open it read-only without claiming it
- refresh persisted history
- perform the Claim confirmation and transition
- exercise acknowledged model and reasoning changes
- submit and receive a real turn
- start and finish a multi-turn standing goal
- test stop/cancel and reconnect behavior
- verify app relaunch restores the correct gateway and session
- verify retained artifacts contain no credential material

Test gated dashboard authentication against a disposable real configuration where Hermes supports it. Use deterministic mock servers only for malformed frames, expiry permutations, external OAuth navigation, and failure states that are unsafe or impractical to force against the real server.

## Phase 6: iterative implementation discipline

Work in coherent vertical slices. For every slice:

1. Read the matching Android production and test code.
2. Record the relevant parity-matrix rows and observable acceptance criteria.
3. Implement the Swift behavior and UI.
4. Add focused tests before considering the slice complete.
5. Run the narrowest relevant test-lab lanes.
6. Launch and drive the app in Simulator.
7. Inspect screenshots, UI hierarchy, logs, and network behavior.
8. Review the full diff for regressions, races, leaks, unsupported assumptions, and security errors.
9. Fix every material issue found.
10. Rerun verification on the final form.
11. Commit the cohesive slice with an imperative conventional commit.

Do not create an initial “complete port” followed by months of cleanup. Keep every committed slice buildable and reviewed. Do not weaken assertions to accommodate broken behavior.

Use official Apple documentation to resolve API, accessibility, privacy, Keychain, WKWebView, networking, audio, notification, or background-execution questions. Avoid unnecessary third-party dependencies. Pin and justify any dependency that is introduced.

## Completion criteria

Mark the goal complete only when all of these are true:

- Every Android production feature and important state has a parity-matrix row.
- Every Android repository method, REST endpoint, JSON-RPC method, stream event, and error path is implemented or has a documented, evidence-backed platform impossibility.
- No production screen or control is a stub, placeholder, or test-only simulation.
- No known high-severity correctness, data-loss, security, accessibility, visual, or integration issue remains.
- Unit, protocol, UI, restoration, accessibility, and visual test suites pass.
- The iOS app passes the real-Hermes smoke journey against the pinned unmodified server.
- The exact final commit passes `./scripts/test-lab/run.sh full`.
- Final artifacts and visual heatmaps have been manually inspected.
- All mandatory screenshots pass the defined visual thresholds and show no visible unexplained differences.
- A clean Simulator install launches and completes onboarding and a real session flow.
- Debug and LocalRelease builds succeed.
- Release builds with no unsupported cleartext exception and passes unsigned generic-device compilation.
- The final implementation has no unimplemented production TODOs, secret material, build products, accidental user files, or unrelated changes.
- Documentation contains the actual reproducible commands and final evidence.
- The worktree is clean apart from explicitly identified user-owned changes.
- An independent final code-review pass finds no unresolved material defect.

Do not mark the goal complete if Xcode/Simulator was unavailable, the real integration lane was skipped, visual comparison was not run, tests pass only with mocks, or a claimed feature was not exercised.

## Final report

When genuinely complete, provide a concise report containing:

- final commit SHA
- architecture summary
- Android-to-iOS feature coverage
- any unavoidable platform limitations
- commits created
- exact build/test/test-lab commands executed
- Simulator runtime and device used
- real Hermes and model-backend evidence
- visual comparison metrics for every mandatory fixture
- paths to retained final artifacts
- confirmation that no secrets were retained
- remaining lower-priority risks, if any
