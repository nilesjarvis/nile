# Nile iOS port progress

Last updated: 2026-08-13

## Current phase

`main` follows the governing Android parity contract in `AGENTS.md` and
`IOS_PORT_GOAL.md`, including app-owned visual design. The historical
[`IOS_NATIVE_DESIGN.md`](IOS_NATIVE_DESIGN.md) records a branch-era decision
and current implementation divergences; it is not a waiver. Strict Android
screenshot comparisons remain acceptance gates, and red redesigned surfaces
remain incomplete until aligned or the governing contract is explicitly
amended.

Phase 1 oracle establishment is complete enough to support verified vertical
slices. Phase 2 architecture and Phase 3 repository/session work are in
progress. The immutable domain inventory, repository contract, authenticated
legacy connection path, secure profile store, generation-safe WebSocket
transport, session codecs, ordered event projection, working session-list shell,
legacy-authenticated read-only terminal history/Claim slice, live/stored
transcript, composer send/steer/stop/protected-draft slice, blocking-input
slice, image-attachment/recovery slice, slash-command slice, and
model/reasoning/pin slice, speech/transcription/voice-settings/Talk slice,
standing-goal lifecycle, usage/statistics surfaces, and delegated-agent
lifecycle, gated dashboard sign-in/cookie/ticket isolation, and transcript
scroll-position/anchor plus code-highlighting parity are ported; the overall
goal remains active and far from completion.

## Authoritative pins

- Android commit: `bd5451da891f2d886b9bc35f8ea67d6920df1d98`
- Android tree: `3b954e5844f05276d34aaee34a7d3f69169ef9f5`
- Hermes commit: `7441e3395f9db0d8319f43bfe07dfb222777101e`
- Local ignored oracle: `.reference/android`

`./scripts/reference/verify-android.sh` verifies all three pins and rejects a
modified oracle.

## Completed foundation

- Extracted ticket/logout paths, bounded POST construction, safe 401 handling,
  retry classification, and fail-closed ticket decoding from the 278-line
  authentication actor into a 90-line transport-free HTTP policy. The resulting
  237-line actor retains serialized cookie-rotation I/O, status discovery,
  managed request authentication, saved-profile scope checks, expiry events,
  and session cleanup without parsing untrusted ticket JSON or constructing
  control requests. Three direct policy regressions cover exact prefixed paths,
  method/body/cache/timeout/cookie fields, the retained 64 KiB limit, unchanged
  nonblank ticket bytes, 400/503 classification, safe 401 fallback, oversized
  responses, and malformed bodies. Architecture guards enforce unique HTTP-
  contract ownership, actor/policy exclusions, 35/255/110/105/95/205-line
  source caps, and a sub-725-line authentication aggregate. All 14 existing
  authentication regressions, the three policy tests, and the ownership guard
  pass in
  `build/DerivedData-GatewayAuthenticationHTTPPolicyFocused/Logs/Test/Test-Nile-2026.08.09_23-22-28-+0200.xcresult`.
  The frozen tree `d751113fa232c5b896facf23e5b38efb2ba7875d`
  passes all 719 unit/protocol tests without failures or skips in
  `build/DerivedData-GatewayAuthenticationHTTPPolicyExactFinal/Logs/Test/Test-Nile-2026.08.09_23-26-49-+0200.xcresult` and an unsigned generic-device
  Release build with Swift and Clang warnings treated as errors in
  `build/DerivedData-Release-GatewayAuthenticationHTTPPolicyExact`; the
  packaged `Info.plist` is valid and contains no `NSAppTransportSecurity` key.
- Extracted regex-heavy goal and compaction interpretation from the 268-line
  gateway event projector into a 143-line stateless status projector without
  changing event names or domain outcomes. The 136-line
  `GatewayEventProjector` remains the sole repository-facing ordered dispatcher
  and continues to own message, tool, review, session-info, and error routing;
  blocking and subagent payloads retain their existing dedicated projectors.
  Architecture guards enforce unique status-parser ownership, exclude payload
  families from the wrong projectors, cap the four sources at
  155/155/180/165 lines, retain the sub-620-line aggregate, and prove that the
  repository constructs exactly one dispatcher. Nine event regressions covering
  active, achieved, parked, paused, generic, both compaction forms, blocking,
  subagent, tool, message, and unknown-event behavior plus the ownership guard
  pass in
  `build/DerivedData-GatewayStatusProjectorFocused/Logs/Test/Test-Nile-2026.08.09_23-11-28-+0200.xcresult`.
  The frozen staged tree passes all 716 unit/protocol tests without failures or
  skips in
  `build/DerivedData-GatewayStatusProjectorExact/Logs/Test/Test-Nile-2026.08.09_23-13-24-+0200.xcresult`
  and an unsigned warnings-as-errors Release device build in
  `build/DerivedData-Release-GatewayStatusProjectorExact`. The packaged Release
  plist is valid and contains no `NSAppTransportSecurity` override.
- Separated the 285-line bidirectional delegation snapshot codec into a
  155-line strict decoder and a 131-line outbound encoder without changing the
  service API or wire format. Untrusted list/load parsing, terminal-status
  normalization, and output-tail recovery now remain independent from outbound
  field validation, optional-field construction, and terminal-status encoding;
  both directions continue to share the existing 232-line primitive boundary.
  Architecture guards enforce unique entry-point ownership, exclude save
  construction from the decoder and load/list parsing from the encoder, cap the
  four delegation codec sources at 60/175/150/250 lines, and retain the
  sub-590-line aggregate. The three focused snapshot RPC, mutation-failure, and
  malformed-payload regressions plus the ownership guard pass in
  `build/DerivedData-DelegationSnapshotDirectionsFocused/Logs/Test/Test-Nile-2026.08.09_23-00-29-+0200.xcresult`.
  The frozen staged tree passes all 715 unit/protocol tests without failures or
  skips in
  `build/DerivedData-DelegationSnapshotDirectionsExact/Logs/Test/Test-Nile-2026.08.09_23-03-39-+0200.xcresult`
  and an unsigned warnings-as-errors Release device build in
  `build/DerivedData-Release-DelegationSnapshotDirectionsExact`. The packaged
  Release plist is valid and contains no `NSAppTransportSecurity` override.
- Isolated session-facing launch-fixture precedence from app-graph composition
  without changing accepted arguments or their ordering. The former 280-line
  `NileAppGraphFixturePlan` falls to 173 lines and retains filtered global flags
  plus fixture admission; the new 74-line pure `NileSessionFixturePolicy`
  exclusively maps session-catalog, streaming-transcript, and recovery values.
  The two sources total 247 lines, 33 fewer than the former mixed plan, and both
  remain Debug/LocalRelease-only. Two direct policy regressions cover composer,
  streaming, recovery, every session-catalog argument, and unknown fail-closed
  behavior. Architecture guards enforce unique ownership, construction and
  argument exclusions, 210/110-line caps, and the retained sub-1,450-line
  app-graph aggregate. The focused 10-test policy/composition run passes in
  `build/DerivedData-SessionFixturePolicyFocused/Logs/Test/Test-Nile-2026.08.09_22-45-51-+0200.xcresult`.
  The frozen staged tree passes all 715 unit/protocol tests without failures or
  skips in
  `build/DerivedData-SessionFixturePolicyExact/Logs/Test/Test-Nile-2026.08.09_22-54-27-+0200.xcresult`
  and unsigned warnings-as-errors Release and LocalRelease device builds in
  `build/DerivedData-Release-SessionFixturePolicyExact` and
  `build/DerivedData-LocalRelease-SessionFixturePolicyExact`. The packaged
  Release plist is valid and contains no `NSAppTransportSecurity` override;
  binary scans find no representative session-policy arguments in Release and
  find all four probes plus the permitted performance-stress argument in
  LocalRelease.
- Consolidated the model picker's pure catalog projection without changing its
  state or interaction boundaries. The stateful `ModelPickerCatalogView` falls
  from 310 to 280 lines and retains query/focus, provider disclosure, rendering,
  and session-model integration. The expanded 97-line Foundation-only
  `ModelPickerCatalogPolicy` now owns normalized provider/model filtering,
  deterministic pinned grouping and unresolved-pin sorting, scope notices,
  catalog ordering, and capability/pricing labels. Three direct policy tests
  cover case-insensitive trimmed queries, provider-versus-model matches,
  resolvable and unresolved pin ordering, and scope-notice precedence.
  Architecture guards enforce unique ownership, 290/105-line catalog/policy
  caps, UI/state exclusions from the policy, projection exclusions from the
  catalog, and the retained sub-1,050-line seven-source aggregate. The exact
  staged tree passes all 713 unit/protocol tests without failures or skips in
  `build/DerivedData-ModelPickerCatalogProjectionExact/Logs/Test/Test-Nile-2026.08.09_22-36-07-+0200.xcresult`
  and an unsigned warnings-as-errors Release build in
  `build/DerivedData-Release-ModelPickerCatalogProjectionExact`; its packaged
  Release plist is valid and contains no `NSAppTransportSecurity` override.
- Split the 307-line typography role/measurement source without changing its
  public API or visual metrics. The 188-line `NileTypography` now owns only the
  Roboto role catalog and SwiftUI font factory without importing UIKit; a
  125-line `NileTypographyMetrics` extension owns the immutable `TextStyle`
  contract, Android-weight resolution, native-spacing policy, and Dynamic Type
  bridge without visual-role or Android-renderer authority. The design-system
  contract enforces unique ownership, platform-role exclusions, 200/140-line
  caps, the retained aggregate, and sole renderer-import ownership. The exact
  staged tree passes all 710 unit/protocol tests without failures or skips in
  `build/DerivedData-TypographyMetricsExact/Logs/Test/Test-Nile-2026.08.09_22-27-04-+0200.xcresult`
  and an unsigned warnings-as-errors Release build in
  `build/DerivedData-Release-TypographyMetricsExact`; its packaged Release plist
  is valid and contains no `NSAppTransportSecurity` override.
- Split gateway setup's synchronous presentation policy from its retained state
  and connection lifecycle. The 248-line core retains dependency construction,
  callback installation, authentication observation, initial connection, and
  pending-switch authority; a task-free 65-line extension now solely owns form
  mutation plus checking, error, connection, cleartext, endpoint, and root-shell
  projection. The architecture contract enforces unique ownership, capability
  exclusions, 260/80-line caps, and a bounded seven-source aggregate. The exact
  staged tree passes all 710 unit/protocol tests without failures or skips in
  `build/DerivedData-GatewaySetupPresentationExact/Logs/Test/Test-Nile-2026.08.09_22-18-55-+0200.xcresult`
  and an unsigned warnings-as-errors Release build in
  `build/DerivedData-Release-GatewaySetupPresentationExact`; its packaged
  Release plist is valid and contains no `NSAppTransportSecurity` override.
- Split the session-list model's remaining synchronous surface responsibilities
  without adding capability, task, persistence, or event authority. The 233-line
  core now retains observable/fixture state, runtime construction, teardown, and
  private ownership projection; 118-line runtime forwarding, 171-line workspace
  projection, 33-line lifecycle, and 58-line blocking-prompt bridges own their
  respective feature-facing adapters. The sole ordered event path is unchanged,
  and its cadence/helper projection is reduced from 133 to 106 lines. Exact
  staged tree `35a0bf29b225e2cd9a72515bff8091ac88249a1e` passes 710/710 tests
  and the warnings-as-errors unsigned Release gate with no packaged ATS override.
- Split the former 302-line mixed attachment-persistence runtime without adding
  another capability or state owner. Its 121-line core now exclusively declares
  the protected draft/marker mirrors, revision/timestamp state, restoration and
  quarantine flags, and sole `AttachmentDraftStoring` reference. A 226-line
  same-runtime transaction extension is the only source that invokes that
  capability for draft writes, marker CAS, snapshot restoration, guarded
  migration, and best-effort quarantine persistence. The reduced 187-line
  recovery lifecycle composes those primitives for promotion, missing-owner
  migration, recovered-marker editing, and disconnect quarantine; the existing
  121-line recovered-edit subordinate remains store-free. Architecture guards
  enforce unique capability/state declarations and transaction-call ownership,
  exclude repositories and event streams, cap the four sources at
  140/240/200/140 lines, retain a sub-660-line aggregate, and keep the global
  architecture-test ceiling unchanged. All 14 focused architecture,
  persistence, and relaunch-recovery regressions pass at
  `build/DerivedData-AttachmentPersistenceTransactions/Logs/Test/Test-Nile-2026.08.09_21-50-33-+0200.xcresult`.
  The exact staged tree `dd5eaedc04329addfd3274bf46aeffa8ef9d7165`
  passes all 710 unit/protocol tests with zero failures or skips at
  `build/DerivedData-AttachmentPersistenceTransactions-Exact/Logs/Test/Test-Nile-2026.08.09_21-53-49-+0200.xcresult`.
  Its optimized unsigned Release device build passes with Swift and Clang
  warnings treated as errors in
  `build/DerivedData-Release-AttachmentPersistenceTransactions-Exact`, and the
  packaged Release app contains no ATS override.

- Split the gateway-wide connection-loss teardown transaction out of the former
  303-line mixed visible-event projection without changing event consumption or
  stage order. The 240-line `SessionListModelVisibleEventProjection` now owns
  ordinary visible message, tool, goal, error, and completion effects, while a
  70-line `SessionListModelConnectionLossProjection` exclusively owns cached-
  timeline capture, voice/Talk/attachment/turn settlement, blocking-prompt
  uncertainty or finalization, gateway/display fencing, feature-runtime reset,
  visible-session clearing, connection phase, and loss notification. The
  existing 48-line event core remains the sole private ordered application
  boundary and `SessionEventRuntime` remains the only stream consumer.
  Architecture guards enumerate all five event sources, enforce unique teardown
  ownership, exclude repositories, capabilities, competing streams, and private
  consumers, cap them at 60/140/250/85/140 lines, retain the sub-625-line event
  aggregate, and keep the global architecture-contract ceiling unchanged. All
  200 focused architecture and session-model tests pass with zero failures or
  skips. The exact staged implementation snapshot passes all 710 unit/protocol
  tests with zero failures or skips. Its optimized unsigned Release build also
  passes with Swift and Clang warnings treated as errors, and the packaged app
  contains no ATS override.

- Split the former 307-line mixed `HermesVoiceInput` without changing its public
  API, event stream, or one-at-a-time microphone gate. A 151-line runtime now
  exclusively owns availability, start/stop/cancel, active-capture and generation
  fencing, lifecycle-event publication, and terminal admission. A separate
  206-line immutable `SpeechCaptureOperation` owns PCM source execution, Android
  RMS VAD, bounded accumulation, silence/maximum-duration decisions, canonical
  WAV construction, transcription handoff, and safe failure projection. The
  existing capture source is reduced to a 112-line owner of the serial async gate
  and lock-backed stop/cancel/source/task/terminal state; the 43-line contracts
  source remains capability-only. The transcription-failure regression now
  records the microphone state inside the Hermes callback and proves capture is
  already closed before private audio crosses that boundary. Source guards
  enforce unique runtime/operation/state ownership, exclude event, gate,
  generation, VAD, WAV, and task authority from the wrong components, cap the
  four sources at 55/175/225/125 lines, and hold their aggregate below 540 lines.
  All 13 focused speech-core tests and the exact staged 710-test unit/protocol
  suite pass with zero failures or skips. The exact staged unsigned Release build
  also passes with Swift and Clang warnings treated as errors, and its packaged
  app has no ATS override.

- Split the platform speech boundary without changing microphone, transcription,
  playback, or Talk APIs. The former 308-line mixed microphone source is now a
  204-line `AVAudioEngine` lifecycle/sample-queue owner plus a 93-line PCM
  converter that exclusively creates and drives `AVAudioConverter`. The former
  303-line output source is now a 264-line native-player lifecycle and a 28-line
  output contract/null implementation. One 34-line `SpeechAudioSession` policy
  now exclusively owns the previously duplicated recording/playback category,
  preferred-capture, activation, and deactivation calls. A deterministic direct
  conversion regression verifies Float32 input becomes 16 kHz mono Int16, while
  source guards enforce unique declarations, exclude conversion/session/task
  authority from the wrong components, cap the five sources at
  220/110/50/285/45 lines, and hold their aggregate below 660 lines. All 13
  focused speech-core tests and the exact staged 710-test unit/protocol suite
  pass with zero failures or skips. The exact staged unsigned Release build also
  passes with Swift and Clang warnings treated as errors, and its packaged app
  has no ATS override.

- Split the former 310-line mixed attachment-delivery coordinator without
  changing its API or the single ordered runtime/event path. A 222-line
  coordinator now owns prompt-response/start/completion/error batch
  correlation, a 49-line immutable contracts source owns batch, lease,
  uncertainty, resolution, and inspection values, and a 92-line `Sendable`
  quarantine state solely stores lease-to-mutation ownership, in-flight upload
  ambiguity, and owner-scoped uncertainty. Direct state coverage verifies
  lease removal and mutation-owner isolation; bounded architecture guards
  exclude transport, task, repository, and runtime authority, enforce
  240/60/110-line component caps plus a sub-380-line aggregate, and keep the
  global architecture inventory at 5,437 physical lines (5,447
  component-counted) beneath its unchanged 5,450-line ceiling. The five
  focused coordinator tests, all 63 architecture-boundary tests, and the exact
  staged 708-test unit/protocol suite pass with zero failures or skips. The
  exact staged unsigned Release build also passes with Swift and Clang warnings
  treated as errors, and its packaged app has no ATS override.

- Split transcript position decisions from UIKit execution without adding a
  second delegate, scroll owner, or offset path. The 285-line
  `TranscriptViewportPositionRuntime` remains the sole collection-view delegate
  and performs view layout/offset work, while the new 165-line
  `TranscriptViewportSettlementState` exclusively owns pending-position retry
  limits, anchoring, detached-offset retention, resize preservation, top-inset
  decisions, and stale-layout generations. The existing 65-line geometry policy
  remains CoreGraphics-only. Direct regressions now fence retry exhaustion,
  automatic-tail admission, detached content changes, retained inset behavior,
  and generation invalidation. Architecture guards require the pure state to
  exclude UIKit, coordinators, and dispatch; enforce 300/180/80-line
  runtime/state/policy caps; and bound the 23-source transcript surface at 3,257
  physical (3,280 component-counted) lines below its explicit 3,290-line
  ceiling. The global architecture inventory is 5,435 physical (5,445
  component-counted) lines below the unchanged 5,450-line ceiling. All nine
  position tests and the complete 63-test architecture suite pass in
  `build/DerivedData-TranscriptViewportSettlement/Logs/Test/Test-Nile-2026.08.09_20-47-16-+0200.xcresult`.
  The exact staged tree passes all 708 unit/protocol tests without failures or
  skips in
  `build/DerivedData-TranscriptViewportSettlement-Exact/Logs/Test/Test-Nile-2026.08.09_20-49-38-+0200.xcresult`;
  its long-history restore/reanchor and populated-transcript keyboard-resize
  journeys pass 3/3 in
  `build/DerivedData-TranscriptViewportSettlement-UI-Exact/Logs/Test/Test-Nile-2026.08.09_20-50-48-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-TranscriptViewportSettlement-Exact`, and the
  packaged Release plist contains no ATS override.
- Extracted delayed Talk relistening from reply/Stop settlement without changing
  Talk phase, speech, or owner-validation behavior. The 270-line
  `SessionTalkRuntime` core now retains mode, voice, and submission admission;
  the 223-line `SessionTalkResponseLifecycle` retains message/completion/error
  settlement, Stop recovery, and speech playback; and a new 122-line
  `SessionTalkRelistenLifecycle` contains the sole
  `SessionTalkRelistenRuntime` delay, task, generation, replacement,
  cancellation, and teardown authority plus the same-type relisten decision and
  resume coordination. Direct tests fence cancelled and replaced operations,
  while architecture guards require unique task ownership, exclude prompt
  transport and Hermes events, enforce 290/240/140-line core/response/relisten
  caps and the unchanged 950-line Talk aggregate, and retain one ordered model
  event application boundary. The global architecture inventory is 5,434
  physical (5,444 component-counted) lines, below the unchanged 5,450-line
  ceiling. The focused six runtime and two architecture tests pass in
  `build/DerivedData-SessionTalkRelistenRuntime/Logs/Test/Test-Nile-2026.08.09_20-31-16-+0200.xcresult`.
  The exact staged tree passes all 704 unit/protocol tests without failures or
  skips in
  `build/DerivedData-SessionTalkRelistenRuntime-Exact/Logs/Test/Test-Nile-2026.08.09_20-35-02-+0200.xcresult`;
  its Talk pause/resume/end and automatic spoken-reply journeys pass in
  `build/DerivedData-SessionTalkRelistenRuntime-UI-Exact/Logs/Test/Test-Nile-2026.08.09_20-36-10-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionTalkRelistenRuntime-Exact`, and the packaged
  Release plist contains no ATS override.
- Replaced the mixed 313-line Claim/Rename session-management boundary with
  independent capabilities and lifecycles. `HermesSessionClaimServing` and
  `HermesSessionRenaming` now occupy separate slots in the 19-slot repository
  capability bundle; the 178-line `SessionClaimRuntime` owns advisory status,
  Claim recheck/open, immutable ownership, and status/Claim fencing, while the
  136-line `SessionRenameRuntime` independently owns title normalization,
  mutation, dialog/error state, immutable ownership, and Rename fencing. Their
  131-line Claim and 101-line Rename model bridges keep presentation and
  settlement separate without adding a repository or event-stream path, and
  the obsolete catch-all protocol, runtime, bridge, test-double surface, and
  unused Claim settlement method are gone. Architecture guards require the two
  capability slots and construction paths, reject the former mixed boundary,
  enforce 190/150-line runtime and 145/115-line bridge caps plus 330/250-line
  aggregates, and retain the sole ordered event router. The global architecture
  inventory is 5,431 physical (5,441 component-counted) lines, below the
  unchanged 5,450-line ceiling. All 63 architecture tests pass in
  `build/DerivedData-SessionClaimRenameCapabilities-Architecture-Exact/Logs/Test/Test-Nile-2026.08.09_20-22-09-+0200.xcresult`.
  The exact staged tree passes all 702 unit/protocol tests without failures or
  skips in
  `build/DerivedData-SessionClaimRenameCapabilities-Final-Exact/Logs/Test/Test-Nile-2026.08.09_20-23-22-+0200.xcresult`;
  its idle Claim, busy Claim, and Rename semantic journeys pass in
  `build/DerivedData-SessionClaimRenameCapabilities-UI-Exact/Logs/Test/Test-Nile-2026.08.09_20-15-10-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionClaimRenameCapabilities-Exact`, and the
  packaged Release plist contains no ATS override.
- Split the former 312-line Hermes Voice editor at its stateless support
  boundary without moving bindings, focus, validation, provider/preset
  selection, or Apply behavior. The 241-line `HermesVoiceEditorView` remains the
  sole draft, focus, provider, preset, and mutation renderer; a 72-line
  `HermesVoiceEditorSupport` source now owns loading, failure, notice, and
  pressed-state components without a setup model, binding, focus state, voice
  config, draft, or Apply callback. Architecture guards enumerate all 14
  Gateway feature sources, enforce unique editor/support ownership,
  175/260/85/125-line sheet/editor/support/policy caps, the unchanged 1,350-line
  settings subset and 2,100-line complete Gateway-surface ceilings, and the
  global architecture ceiling. The complete Gateway surface is 2,064 physical
  (2,078 component-counted) lines, while the global architecture inventory is
  5,435 physical (5,445 component-counted) lines. All 63 architecture tests pass
  in `build/DerivedData-HermesVoiceEditorSupport/Logs/Test/Test-Nile-2026.08.09_19-51-24-+0200.xcresult`,
  and the selector-driven load/change/apply/global-summary journey passes in
  `build/DerivedData-HermesVoiceEditorSupport/Logs/Test/Test-Nile-2026.08.09_19-52-05-+0200.xcresult`.
  The exact staged tree passes all 702 unit/protocol tests without failures or
  skips in
  `build/DerivedData-HermesVoiceEditorSupport-Exact/Logs/Test/Test-Nile-2026.08.09_19-53-38-+0200.xcresult`;
  its warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-HermesVoiceEditorSupport-Exact`, and the packaged
  Release plist contains no ATS override.
- Split the model picker at its remaining presentation boundary without moving
  state or changing model/reasoning behavior. The 228-line `ModelPickerView`
  remains the sole sheet, dismissal, catalog-focus, loading, error, and catalog
  composition owner; its store-free 107-line
  `ModelPickerReasoningControl` extension now owns reasoning options,
  availability, labeling, footnote, and session-scoped mutation rendering
  without declaring `@State`, `@Bindable`, a model instance, catalog loading,
  or another picker. Architecture guards enforce unique sheet/reasoning/catalog
  ownership, 250/125/325/200/75/50/140-line component caps, and the unchanged
  1,050-line picker ceiling; the seven-source surface is 1,034 physical (1,041
  component-counted) lines, while the global architecture inventory falls to
  5,433 physical (5,443 component-counted) lines. All 63 architecture tests pass
  in `build/DerivedData-ModelPickerReasoningControl/Logs/Test/Test-Nile-2026.08.09_19-40-25-+0200.xcresult`,
  and both selector-driven picker search/pin/dismiss and provider/model
  interaction journeys pass in
  `build/DerivedData-ModelPickerReasoningControl/Logs/Test/Test-Nile-2026.08.09_19-41-04-+0200.xcresult`.
  The exact staged tree passes all 702 unit/protocol tests without failures or
  skips in
  `build/DerivedData-ModelPickerReasoningControl-Exact/Logs/Test/Test-Nile-2026.08.09_19-44-09-+0200.xcresult`;
  its warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-ModelPickerReasoningControl-Exact`, and the
  packaged Release plist contains no ATS override.
- Split the former 322-line standing-goal modal at its remaining presentation
  boundary without moving state or changing UI behavior. The 87-line
  `GoalView` remains the sole owner of the modal, dismissal, draft/budget state,
  error presentation, and active-versus-creation routing; its store-free
  242-line `GoalSheetCreation` extension now owns quick-start, objective,
  budget, and submit rendering without declaring `@State`, `@Bindable`, a model
  instance, or another modal. The existing 201-line active-details source,
  128-line persistent status card, and 36-line pure presentation policy remain
  independent. Architecture guards enforce unique creation/state ownership,
  100/250/210/140/45-line core/creation/details/card/policy caps, and the
  unchanged 700-line goal-surface ceiling; the surface is 694 physical (699
  component-counted) lines and the global architecture inventory remains 5,437
  physical (5,447 component-counted) lines. Both selector-driven creation and
  active-details journeys pass in
  `build/DerivedData-GoalCreationSurface/Logs/Test/Test-Nile-2026.08.09_19-29-14-+0200.xcresult`.
  All 702 unit/protocol tests pass in
  `build/DerivedData-GoalCreationSurface/Logs/Test/Test-Nile-2026.08.09_19-30-34-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-GoalCreationSurface`, and its packaged plist
  contains no ATS override.
- Split the former 326-line standing-goal mutation extension at its remaining
  task-authority boundary. The 246-line `SessionGoalMutations` source now owns
  only start/pause/resume/clear command flows and the full goal mutation
  capability, while one independently typed 129-line
  `SessionGoalMutationLifecycle` exclusively owns task replacement,
  cancellation, mutation generation, and lifecycle/token validation. The
  256-line `SessionGoalRuntime` remains the sole observable goal authority and
  no longer stores a mutation task or mutation generation. A direct regression
  proves replacement cancellation and both generation fences; architecture
  guards enforce unique task/token authority, command/lifecycle exclusions,
  290/260/140/55/280/125-line core/command/lifecycle/contracts/policy/status
  caps, the retained 1,070-line goal-runtime ceiling, and the single ordered
  event router. The global architecture inventory remains under its unchanged
  5,450-line ceiling at 5,437 physical (5,447 component-counted) lines. All 702
  unit/protocol tests pass in
  `build/DerivedData-GoalMutationLifecycle/Logs/Test/Test-Nile-2026.08.09_19-18-45-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-GoalMutationLifecycle`, and its packaged plist
  contains no ATS override.
- Split the former 397-line transcript viewport controller at its remaining
  UIKit ownership boundary. The 98-line `TranscriptViewportController` now
  retains only row-host/update ordering, signposting, and accessibility
  projection; one 350-line `TranscriptViewportPositionRuntime` is the sole
  collection-view delegate and owns the collection view, scroll owner and
  coordinator reference, pending offsets, resize/inset preservation, layout
  settlement, UIKit offset application, and anchor publication. The expanded
  63-line collection source exclusively owns layout/configuration factories,
  root constraints, and layout observation. A direct regression proves delegate
  and owner activation stay in the runtime, architecture guards enforce
  115/360/80/80/190-line controller/runtime/collection/policy/row-host caps and
  unique authority, and the 22-source transcript surface remains below its
  3,190-line ceiling at 3,157 physical (3,179 component-counted) lines. The
  global architecture inventory is 5,426 physical (5,436 component-counted)
  lines under its 5,450 ceiling. All 701 unit/protocol tests pass in
  `build/DerivedData-TranscriptPositionRuntime/Logs/Test/Test-Nile-2026.08.09_18-58-47-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-TranscriptPositionRuntime`, and its packaged plist
  contains no ATS override.
- Split the former 317-line telemetry runtime and broad usage capability into
  independently typed owners without changing the model-facing API or request
  semantics. The 132-line `SessionUsageRuntime` now owns only session polling,
  retry, and context state through `HermesSessionUsageServing`; the 202-line
  `GatewayStatsRuntime` owns only sheet/period/loading/error state and its
  gateway-fenced request through `HermesGatewayStatsServing`. The composition
  bundle now has 18 explicit slots, the 130-line model bridge forwards both
  observable owners, and architecture guards enforce capability/task/state
  separation with a 350-line runtime aggregate. The global architecture-test
  inventory is 5,424 physical (5,434 component-counted) lines, below its 5,450
  ceiling. All 239 focused architecture/model/domain/gateway tests pass in
  `build/DerivedData-TelemetryRuntimes/Logs/Test/Test-Nile-2026.08.09_18-38-28-+0200.xcresult`,
  all 700 unit/protocol tests pass in
  `build/DerivedData-TelemetryRuntimes/Logs/Test/Test-Nile-2026.08.09_18-39-13-+0200.xcresult`,
  and the warnings-as-errors unsigned Release build passes from
  `build/DerivedData-Release-TelemetryRuntimes` with no Release ATS override.
- Split media rendering out of the former 337-line mixed transcript-message
  source. The 227-line `TranscriptMessageRows` now owns only central entry/role
  dispatch, assistant Markdown/copy state, and the user bubble, while a 112-line
  `TranscriptMediaRows` exclusively owns cached/fallback image presentation and
  tappable attachment cards. Every moved view body, dimension, color, label,
  cache call, and accessibility identifier is byte-identical; only the two
  top-level media declarations shed file-private visibility for cross-source
  composition. Architecture guards enforce 250/130-line caps, mutually exclude
  dispatch/copy/Markdown and media declarations, and keep the 21-source
  transcript surface below a 3,110-line aggregate at 3,081 physical (3,102
  component-counted) lines. The global architecture inventory remains below its
  5,450-line ceiling at 5,436 physical (5,446 component-counted) lines. All 95
  focused architecture, transcript projection, media-runtime, Markdown, and
  payload-cache tests pass in
  `build/DerivedData-TranscriptMediaRows/Logs/Test/Test-Nile-2026.08.09_18-23-39-+0200.xcresult`.
- Split stable authentication contracts out of the former 299-line mixed
  gateway actor without changing their declarations or any actor method body.
  A 22-line Foundation-only source now exclusively owns the session-cleaning
  capability, cookie-scope conflict error, and authentication-expiry event,
  while the 278-line actor retains ticket minting, managed requests, cookie I/O,
  saved-profile checks, expiry publication, logout, and rotation coordination.
  Architecture guards reject transport, cookie-store, cookie-policy, request,
  WebKit, task, and actor authority from the contract source; enforce
  35/290/105/95/205-line caps across contracts, actor, rotation, store, and
  policy; keep their aggregate below 680 lines at 661 physical (666
  component-counted) lines; and retain the global architecture inventory below
  its 5,450-line ceiling at 5,435 physical (5,445 component-counted) lines. All
  77 focused authentication and architecture tests pass in
  `build/DerivedData-AuthenticationContracts/Logs/Test/Test-Nile-2026.08.09_18-15-52-+0200.xcresult`.
- Split the 319-line Markdown parser/cache/contract catch-all without changing
  its declarations or method bodies. A 21-line dependency-free contracts source
  now exclusively owns immutable block/table values, a 42-line Foundation cache
  exclusively owns `NSCache`, locking, parse accounting, and settled-content
  reuse, and the 256-line parser retains only pure block parsing mechanics.
  Architecture guards enforce 35/55/275-line caps, forbid cache state and
  rendering authority from crossing those boundaries, retain the 1,825-line
  complete design-system aggregate at 1,791 physical (1,803 component-counted)
  lines, and keep the architecture-contract inventory below its 5,450-line
  ceiling at 5,430 physical (5,440 component-counted) lines. All 77 focused
  Markdown and architecture tests pass in
  `build/DerivedData-MarkdownBoundary/Logs/Test/Test-Nile-2026.08.09_18-06-21-+0200.xcresult`.
- Split security-sensitive model/provider argument admission out of the former
  313-line mixed `GatewayModelCodec`. The 260-line codec now owns only response
  decoding, while a separate 52-line Foundation-only
  `GatewayModelArgumentPolicy` retains the exact whitespace, control-scalar,
  reserved-flag, and Unicode-dash rejection behavior before transport. Four
  direct policy regressions cover safe values and every rejection family,
  including exact non-retryable errors that cannot report a possibly completed
  request. Architecture guards enforce 275/65-line source caps, a 330-line
  aggregate, policy/codec responsibility exclusions, and keep the complete
  architecture inventory below its 5,450-line ceiling at 5,426 physical (5,436
  component-counted) lines. All 100 focused policy, repository-model, and
  architecture tests pass in
  `build/DerivedData-GatewayModelArgumentPolicy/Logs/Test/Test-Nile-2026.08.09_17-55-58-+0200.xcresult`.
- Deleted the dormant custom-path renderer from `NileMaterialIcon`. The live
  50-line SF Symbol wrapper, nine-case compatibility vocabulary, symbol mapping,
  modifier chain, and every call site are unchanged; 281 lines of dormant
  private `Path`/CoreGraphics baggage were removed from the former 331-line
  source. The design-system architecture inventory now includes the
  previously unguarded icon source, requires its live view/kind/symbol owner,
  rejects private paths, path factories, `Path` builders, and point/rect geometry,
  enforces a 60-line source cap, and keeps all ten design sources below a
  1,825-line aggregate at 1,791 physical (1,801 component-counted) lines. The
  complete architecture inventory remains bounded at 5,414 physical (5,424
  component-counted) lines. All 83 focused architecture, typography, tactile,
  and Markdown tests pass in
  `build/DerivedData-MaterialIconDeadPath/Logs/Test/Test-Nile-2026.08.09_17-47-15-+0200.xcresult`.
  Exact implementation tree `169447e3a815102ec4747b1761e01f9cdcf22ee9`
  passes all 695 unit/protocol tests without failures, skips, expected failures,
  or warnings, plus a warnings-as-errors optimized unsigned Release build that
  compiles the reduced icon source and packages no ATS override. Retained
  evidence is under `build/material-icon-exact-169447e3a815/`.
- Removed stateless tool-row mutation policy from the live assistant-segment
  coordinator. The former 336-line `LiveTranscriptCoordinator` is now a
  277-line owner of assistant chronology, authoritative completion, system/tool
  boundaries, media finalization, and cache delegation; a separate 97-line
  `LiveTranscriptToolProjector` exclusively owns live-tool input/projection
  values, stable tool IDs, kinds, label fallback, timestamps, incremental field
  replacement, and active-todo projection. New tools still close and finalize
  the active assistant segment before insertion, while updates retain the open
  segment and every existing content/metadata fallback. Architecture guards
  reject assistant/parser/cache/task/Hermes authority in the tool projector,
  enforce 290/110/65-line caps across the coordinator, projector, and payload
  cache, and keep their aggregate below 435 lines; the complete architecture
  inventory is 5,408 physical (5,418 component-counted) lines. All 94 focused
  architecture/coordinator/timeline/presentation/cache tests pass in
  `build/DerivedData-LiveTranscriptToolProjection/Logs/Test/Test-Nile-2026.08.09_17-39-57-+0200.xcresult`.
  Exact implementation tree `fb92f77f97f1491a6b126379f9c954852e1aef6d`
  passes all 695 unit/protocol tests without failures, skips, expected failures,
  or warnings, plus a warnings-as-errors optimized unsigned Release build that
  compiles all three live-transcript sources and packages no ATS override.
  Retained evidence is under `build/live-tool-exact-fb92f77f97f1/`.
- Split collection-layout construction and invalidation observation out of the
  436-line `TranscriptViewportController`. The controller is now a 397-line
  scroll/settlement/accessibility authority, while a 38-line
  `TranscriptViewportCollectionView` source owns only the unchanged
  compositional-layout tokens/factory and layout callback; explicit main-actor
  isolation is retained. Architecture enforcement gives those sources
  410/50-line caps, rejects layout authority in the controller and
  scroll/row/accessibility authority in the collection source, and keeps the
  20-source transcript surface at 3,079 physical (3,099 component-counted)
  lines; the complete architecture inventory remains bounded at 5,403 physical
  (5,413 component-counted) lines.
  All 83 focused architecture/projection/scroll/position-policy tests pass in
  `build/DerivedData-TranscriptCollectionLayoutSplit/Logs/Test/Test-Nile-2026.08.09_17-29-15-+0200.xcresult`.
  Exact implementation tree `ea6a58165f39dd02198913ebefd04dccd88fc46e`
  passes all 695 unit/protocol tests with no failures or skips, plus a warnings-
  as-errors optimized unsigned Release build that compiles both viewport
  sources and packages no ATS override. Retained evidence is under
  `build/transcript-layout-exact-ea6a58165f39/`.
- Split the unguarded 337-line `NileAccessibilityID` catch-all into a one-line
  namespace plus seven feature-owned app/gateway, composer/talk, delegation,
  goal/prompt, model/command, session, and transcript extensions ranging from
  27 to 83 lines. The complete 185-declaration contract is retained exactly:
  149 constants, 34 dynamic factories, two private key helpers, and all 183
  external `niles.*` templates match the pre-split inventory; the Java-style
  voice hash and length-framed model-pin key bodies are unchanged and now have
  focused value regressions. Architecture enforcement requires unique feature
  markers, 95/60/40/40/90/60/55-line caps, and a 370-line aggregate; the full
  architecture inventory remains bounded at 5,402 physical (5,412 component-
  counted) lines. All 63 architecture contracts and three stable-ID behavior
  tests pass in
  `build/DerivedData-AccessibilityIDSplit/Logs/Test/Test-Nile-2026.08.09_17-18-14-+0200.xcresult`.
  Exact implementation tree `e7e3641eb5b38621b83fa7314275a223abfadb5b`
  passes all 695 unit/protocol tests with no failures, skips, or expected
  failures, plus a warnings-as-errors optimized unsigned Release build that
  compiles all eight identifier sources and packages no ATS override. Retained
  evidence is under `build/accessibility-id-exact-e7e3641eb5b3/`.
- Removed the dashboard core's mixed transport/security ownership and duplicate
  authenticated GET pipeline. The former 319-line `GatewayDashboardClient` is
  now a 197-line JSON transport that funnels ordinary reads, queried reads, and
  mutations through one bounded request/response path; the new transport-free
  86-line `GatewayDashboardResponsePolicy` exclusively owns safe error-detail
  extraction, Android-aligned retry classification, and exact profile-scoped
  login URL admission for dashboard, authentication, and download consumers.
  The existing credential, proxy-prefix, response-bound, default-port, and
  fail-closed cross-origin/path behavior is retained, with a focused queried-
  request regression proving sorted encoding and legacy-token attachment. The
  complete dashboard boundary shrank from 806 to 771 physical lines, and its
  architecture contract now enforces unique response-policy ownership,
  100/220/100/140/255/45-line caps, and a 790-line aggregate; the complete
  architecture inventory remains bounded at 5,366 physical (5,376 component-
  counted) lines. All 14 dashboard, 14 authentication, and 62 architecture
  contracts pass in
  `build/DerivedData-DashboardResponsePolicy/Logs/Test/Test-Nile-2026.08.09_17-04-39-+0200.xcresult`.
  Exact implementation tree `30f8a62369b4b3185b0ef584abd3f63b85c88d35`
  passes all 691 unit/protocol tests with no failures, skips, or expected
  failures, plus a warnings-as-errors optimized unsigned Release build that
  compiles the response-policy source and packages no ATS override. Retained
  evidence is under `build/dashboard-response-exact-30f8a62369b4/`.
- Closed the gateway-domain architecture blind spot by splitting the former
  322-line `GatewayEndpoint` source at its security boundaries. The 88-line
  `GatewayEndpoint` now owns only the immutable endpoint/error surface and URL
  construction/encoding; the 173-line `GatewayEndpointParser` exclusively owns
  canonicalization, origin/path/port validation, and legacy migration; and the
  66-line `GatewayConnection` exclusively owns profile credentials plus build-
  gated cleartext permission. Error text, default-port normalization, reverse-
  proxy preservation, credential encoding, and fail-closed cleartext behavior
  are unchanged. The domain architecture contract now enforces unique
  endpoint/parser/permission/connection ownership, 105/190/85-line caps, a
  350-line aggregate, and keeps the complete architecture inventory at 5,359
  physical (5,369 component-counted) lines. All six endpoint contracts and all
  62 architecture contracts pass in
  `build/DerivedData-GatewayDomainSplit/Logs/Test/Test-Nile-2026.08.09_16-54-11-+0200.xcresult`;
  57 authentication, request-factory, dashboard, WebSocket, and protected-
  profile regressions pass in the same derived-data directory at
  `Test-Nile-2026.08.09_16-55-11-+0200.xcresult`. Exact implementation tree
  `af40ade5d836697f2753804e2cb166dc315fb171` passes all 690 unit/protocol tests
  with no failures, skips, or expected failures, plus a warnings-as-errors
  optimized unsigned Release build that compiles both new sources and packages
  no ATS override. Retained evidence is under
  `build/gateway-domain-exact-af40ade5d836/`.
- Split the former 326-line mixed `GatewaySessionCodec` at the actual Hermes
  schema boundary. The 137-line codec now owns only session-list, live-session,
  active-status, and session-info decoding; the new 156-line
  `GatewayStoredSessionCodec` exclusively reconstructs persisted messages,
  correlates tool calls/results, and flattens multimodal content; and the
  transport-free 37-line `GatewaySessionMessagePolicy` shares private standing-
  goal filtering and model-switch notice projection without depending on wire
  or domain types. `GatewaySessionService` injects the live and stored codecs
  independently. Its obsolete, uncalled context-category decoder and duplicate
  test were removed; the authoritative `GatewayUsageCodec` path retains its
  existing invalid-category coverage. The architecture contract enforces
  unique ownership, 150/175/50-line caps, a 350-line codec aggregate, and keeps
  the complete inventory at 5,384 physical (5,394 component-counted) lines.
  All 62 architecture contracts and seven focused session-codec tests pass in
  `build/DerivedData-SessionCodecSplit/Logs/Test/Test-Nile-2026.08.09_16-44-19-+0200.xcresult`.
  Exact implementation tree `ecb1cf94857f9a3460518f30783914b78c090df5`
  passes all 690 unit/protocol tests with no failures, skips, or expected
  failures, plus a warnings-as-errors optimized unsigned Release build that
  compiles both new sources and packages no ATS override. Retained evidence is
  under `build/session-codec-exact-ecb1cf94857f/`.
- Closed the Add Gateway architecture blind spot and removed its unreachable
  rendering remnants. The former 351-line mixed source is now a 216-line
  `AddGatewayView` that retains the sole observable model binding, focus/form
  state, async connect admission, fields, status, and exact call-site layout,
  plus a 77-line model-free `GatewayCleartextControls` source that renders the
  unchanged warning copy, Android/iOS runtime noun, approval action,
  accessibility semantics, colors, padding, and geometry. Dead scaled-height,
  raster button-color, exact-field-text, and private button-style declarations
  with no call sites were deleted. The architecture contract now enumerates all
  13 Swift sources in `Features/Gateway`, enforces unique onboarding ownership,
  rejects those dead markers, applies 235/95-line onboarding caps, replaces the
  incomplete 1,800-line claim with a complete 2,100-line gateway aggregate, and
  keeps the architecture-test inventory below its ceiling at 5,389 physical
  lines. All 30 gateway setup/model tests and all 62 architecture contracts pass
  without failures, skips, or expected failures (92 total) in
  `build/DerivedData-GatewayOnboardingSplit/Logs/Test/Test-Nile-2026.08.09_16-27-53-+0200.xcresult`.
  Exact implementation tree `f3042a9a0c50b47a74910b35f4002d4c12cf4383`
  passes all 691 unit/protocol tests and both clean-onboarding/explicit-cleartext-
  approval XCUITests with zero failures, skips, or expected failures; the UI
  contracts ran on a fresh disposable iPhone 17 Pro/iOS 26.5 Simulator that was
  deleted afterward. Its warnings-as-errors optimized unsigned Release build
  compiles both onboarding sources, and the packaged Release plist contains no
  ATS override. Retained evidence is under
  `build/gateway-onboarding-exact-f3042a9a0c50/`.
- Split rendered transcript reference payloads out of the mixed 332-line
  build-gated session transcript fixture. The 240-line
  `SessionTranscriptFixture` now owns only live/stored repository messages and
  their reusable message builders, while the 97-line
  `SessionTranscriptPresentationFixture` exclusively owns app-level
  `TranscriptEntry` payloads and the embedded visual-media preview. Both remain
  compiled only for Debug and LocalRelease, with the existing fixture
  initializer consuming the unchanged property. Architecture guards enforce
  unique projection and embedded-preview ownership, exclude `HermesMessage`
  and live/stored session state from the presentation source, apply
  270/285/255/110-line caps to the directory/control/repository-transcript/
  presentation sources, retain an 875-line aggregate, and keep the architecture-
  test inventory below its 5,400-line ceiling at 5,384 physical lines. Both new
  payload-preservation regressions, all 136 session-model tests, and all 62
  architecture contracts pass without failures, skips, or expected failures
  (198 total) in
  `build/DerivedData-SessionTranscriptPresentationSplit/Logs/Test/Test-Nile-2026.08.09_16-16-27-+0200.xcresult`.
  Exact implementation tree `69a78332f7fd24ae5fe36b0550c1cae253d811fd`
  passes all 691 unit/protocol tests with zero failures, skips, or expected
  failures. Its warnings-as-errors optimized unsigned Release and LocalRelease
  builds both compile the two transcript fixture sources; representative
  projection text and embedded-preview bytes are present in LocalRelease and
  absent from Release, whose packaged plist also contains no ATS override.
  Retained evidence is under
  `build/session-transcript-presentation-exact-69a78332f7fd/`.
- Split the mixed 353-line navigation runtime behind its unchanged public API.
  The 198-line core retains immutable gateway/display contracts, the sole
  `HermesSessionServing` capability and task/operation-ID state, initial and
  one-shot directory/source/history/open/create/status calls, cancellation,
  owner validation, and reset. Its 166-line same-runtime task lifecycle
  exclusively drives periodic directory/status/read-only-history refresh,
  foreground display reconciliation, and attached-turn authoritative refresh
  without another capability, owner/state declaration, or event path.
  Architecture guards enforce unique state and method ownership, responsibility
  exclusions, 215/180-line component caps, a 380-line runtime aggregate, and the
  retained single ordered model event boundary while keeping the architecture-
  test inventory at 5,373 physical lines. All four direct runtime, 134 model,
  and 62 architecture tests pass without failures, skips, or expected failures
  in
  `build/DerivedData-NavigationTaskSplit/Logs/Test/Test-Nile-2026.08.09_16-04-16-+0200.xcresult`.
  Exact implementation tree `e200bf2be45ce93966f6b883ab06d9a68de3a00f`
  passes all 689 unit/protocol tests with zero failures, skips, or expected
  failures. Its warnings-as-errors optimized unsigned Release build compiles
  both navigation sources, and the packaged Release plist contains no ATS
  override. Retained evidence is under
  `build/navigation-task-exact-e200bf2be45c/`.
- Split the mixed 364-line delegation runtime behind its unchanged public API.
  The 128-line observable core retains live-event admission, transcript/UI
  projection, the sole `HermesDelegationServing` capability, coordinator, task
  registry, lifecycle generation, active-gateway fence, cancellation, and
  reset. Its 247-line same-runtime async lifecycle exclusively drives interrupt,
  snapshot loading, reconciliation, and persistence operations without another
  repository owner, observable-state declaration, or event path. Architecture
  guards enforce unique authority and operation ownership, core/lifecycle
  responsibility exclusions, 145/265-line component caps, and the retained
  1,400-line delegation aggregate while reducing the architecture-test inventory
  to 5,366 physical lines. All 134 model, four coordinator, three reducer, two
  fixture-adapter, and 62 architecture tests pass without failures, skips, or
  expected failures in
  `build/DerivedData-DelegationAsyncSplit/Logs/Test/Test-Nile-2026.08.09_15-55-01-+0200.xcresult`.
  Exact implementation tree `703782569ba6757c0123e789cb8534a797cfd869`
  passes all 689 unit/protocol tests without failures, skips, or expected
  failures. Its warnings-as-errors optimized unsigned Release build compiles
  both runtime sources and contains no `NSAppTransportSecurity` override;
  retained evidence is under
  `build/delegation-async-exact-703782569ba6/`.
- Split the 337-line biometric app-lock catch-all into independently bounded
  state, contract, persistence, and platform boundaries. The 187-line
  `BiometricAppLockModel` retains the observable fail-closed state machine,
  scene/background fencing, and exact presentation copy. The 64-line
  Foundation-only contracts own capability, biometry kind, stable failure, and
  narrow storage/authentication protocols; the 21-line store alone owns the
  non-secret `UserDefaults` flag; and the 97-line platform adapter alone imports
  `LocalAuthentication`, creates `LAContext`, and translates `LAError` before it
  reaches presentation. Architecture guards enforce exclusive declarations and
  platform mechanics, 200/80/35/110-line component caps, and a 390-line
  aggregate while retaining the 5,389-line architecture-test inventory. All
  seven biometric lifecycle tests, including every stable failure class, and
  all 62 architecture tests pass without failures or skips. Exact implementation
  tree `ac334075188d9fa6e6269c766bbb05f32895fa00` passes all 689
  unit/protocol tests without failures, skips, or expected failures. Its
  warnings-as-errors optimized unsigned Release build compiles all three
  extracted sources, preserves `NSFaceIDUsageDescription`, and contains no
  `NSAppTransportSecurity` override; retained evidence is under
  `build/biometric-boundaries-exact-ac334075188d/`.
- Split the security-sensitive response lifecycle out of the former 351-line
  blocking-prompt runtime. The 146-line `SessionBlockingPromptRuntime` retains
  the sole `BlockingPromptCoordinator` and event, binding, status, projection,
  and reset forwarding. A dedicated 247-line
  `SessionBlockingPromptResponseLifecycle` alone stores the narrow blocking-
  prompt capability, one-shot task registry, reset generation, typed RPC
  dispatch, and definite/retryable/uncertain settlement; clarification answers,
  passwords, and secrets remain task-local and never enter runtime fields.
  Architecture guards enforce exclusive task/capability ownership,
  responsibility exclusions, 160/260-line component caps, and a 410-line pair
  aggregate while keeping the complete architecture-test inventory at 5,389
  physical lines. All four direct runtime tests, all 134 model integration
  tests, and all 62 architecture contracts pass without failures or skips. The
  exact implementation tree `e20b0a312885070b914eb39b0e67200f53bfa552`
  passes all 689 unit/protocol tests without failures, skips, or expected
  failures; its warnings-as-errors optimized unsigned Release build compiles
  the new lifecycle from the target Swift file list, and the built Release plist
  contains no `NSAppTransportSecurity` override. Retained evidence is under
  `build/blocking-response-exact-e20b0a312885/`.
- Split interrupt admission and response transitions out of the former 372-line
  delegation coordinator. The 289-line `DelegationCoordinator` retains the sole
  turn-history declaration, live-owner binding, sparse-event grouping, parent
  settlement, and transcript projection. A dedicated 140-line
  `DelegationInterruptLifecycle` now owns the active-request registry, monotonic
  request fencing, delegated-agent lookup, and status mutations; same-type
  forwarding methods preserve the coordinator API, and the existing 185-line
  snapshot lifecycle remains independent. The architecture contract enforces
  unique state ownership, responsibility exclusions, 310/150/200/290/100-line
  component caps, and a 1,000-line aggregate while keeping the complete
  architecture-test inventory at 5,387 physical lines. All four coordinator
  tests, the model interrupt/navigation regression, and all 62 architecture
  contracts pass without failures or skips. Exact implementation tree
  `acf2cb3d4497099a45b82b26fe16c405e35b93c7` passes all 689 unit/protocol
  tests with zero failures, skips, or expected failures. Its warnings-as-errors
  optimized unsigned Release build compiles `DelegationInterruptLifecycle.swift`
  and contains no packaged `NSAppTransportSecurity` dictionary; retained evidence
  is under `build/delegation-interrupt-exact-acf2cb3d4497/`.
- Split the 410-line settings surface into a 262-line `SettingsView`
  orchestration owner and a 188-line model-free `SettingsCards` renderer. The
  orchestration source retains the only `GatewaySetupModel` and
  `BiometricAppLockModel` bindings, async task admission, navigation, gateway
  switch/removal confirmation, and mutable dialog/form state. The extracted
  security and saved-gateway cards receive one narrow security binding,
  immutable render state, and synchronous gateway intents while preserving the
  existing hierarchy, spacing, controls, copy, and accessibility identifiers.
  Architecture guards exclude models, observation, tasks, and service calls
  from the card source, enforce
  275/210-line component caps, a 470-line pair aggregate, and the retained
  1,350-line settings-surface aggregate while keeping the complete architecture
  test inventory at 5,380 physical lines. All 61 architecture contracts pass in
  `build/DerivedData-SettingsCardsSplit/Logs/Test/Test-Nile-2026.08.09_14-58-03-+0200.xcresult`.
  Exact staged tree `fb9bf067723dcdbbb377f49537d1defa1d1dfff1`
  passes all 689 unit/protocol tests and the two fixture-isolated gateway-card
  removal/switch XCUITests with zero failures, skips, or expected failures. Its
  warnings-as-errors optimized unsigned Release build compiles
  `SettingsCards.swift` and contains no packaged `NSAppTransportSecurity`
  dictionary; retained evidence is under
  `build/settings-cards-exact-fb9bf067723d/`.
- Split the 365-line dashboard attachment download extension into a 126-line
  credential-aware transport loop and a 240-line pure
  `GatewayDashboardDownloadPolicy`. The transport alone constructs requests,
  attaches the managed-profile token, strips it on cross-origin redirects,
  enforces the five-hop sequence and byte bounds, and returns response data;
  the policy owns managed/file/external source classification, safe-loopback and
  HTTPS admission, downgrade rejection, and filename parsing without an HTTP
  transport or credential access. A separate 33-line `GatewayURLOriginPolicy`
  now provides the one default-port-aware origin comparison used by both exact
  login-URL validation and redirect credential stripping, shrinking the JSON
  client to 319 lines. Architecture guards enforce unique transport/policy/
  origin ownership, exclude request/token access from both policies, cap the
  five dashboard sources at 100/330/140/255/45 lines and 825 lines in aggregate,
  and keep the architecture-test inventory at 5,375 physical lines. All 75
  focused dashboard and architecture tests, including direct default-port
  normalization coverage, pass with zero failures, skips, or expected failures
  in `build/DerivedData-DashboardDownloadPolicySplit/Logs/Test/Test-Nile-2026.08.09_14-47-55-+0200.xcresult`.
  Exact staged tree `e95364a5708c317831b4fdd0601affb93d692eb9`
  passes all 689 unit/protocol tests with zero failures, skips, or expected
  failures, and its warnings-as-errors optimized unsigned Release build passes
  with both extracted sources compiled and no packaged
  `NSAppTransportSecurity` dictionary; retained evidence is under
  `build/dashboard-download-policy-exact-e95364a5708c/`.
- Split the mixed 355-line command runtime along its catalog/completion versus
  remote-mutation lifecycle. The 185-line observable `SessionCommandRuntime`
  retains catalog state, debounced completions, policy snapshots, the public
  API, and the sole stored `HermesCommandServing` capability. A separate
  224-line non-observable `SessionCommandExecutionLifecycle` receives that
  capability only for an admitted operation and owns per-session exclusion,
  execution tasks, bounded alias validation, uncertainty classification, and
  gateway-reset cancellation. Architecture guards enforce unique state/helper
  ownership, exclude catalog/observation/stored-capability/event authority from
  the lifecycle, cap the sources at 200/240 lines and 420 lines in aggregate,
  and place the command contract in its own 43-line architecture-test source;
  the complete architecture-test inventory remains below its 5,400-line ceiling
  at 5,378 physical lines. All 198 focused command-runtime, complete model, and
  architecture tests pass with zero failures, skips, or expected failures in
  `build/DerivedData-CommandExecutionSplit/Logs/Test/Test-Nile-2026.08.09_14-34-11-+0200.xcresult`.
  Exact staged tree `aa32921ed08d6fcbdefffd160a7fc0cfc3830b00`
  passes all 688 unit/protocol tests with zero failures, skips, or expected
  failures, and its warnings-as-errors optimized unsigned Release build passes
  with `SessionCommandExecutionLifecycle.swift` compiled and no packaged
  `NSAppTransportSecurity` dictionary; retained evidence is under
  `build/command-execution-exact-aa32921ed08d/`.
- Split the mixed model-facing voice/Talk bridge without changing microphone,
  transport, playback, or event authority. The former 336-line
  `SessionListModelVoice` is now a 128-line ordinary dictation, spoken-reply, and
  app/surface lifecycle adapter plus a 218-line `SessionListModelTalk` owner for
  Talk-first voice routing, session/listening gates, controls, callbacks, and
  optimistic submission/failure projection. Architecture guards pin every
  adapter and representative capability call to one source, exclude repository
  and event-stream access from both, retain the single ordered Hermes event
  application boundary, cap the pair at 145/235 lines and 365 lines in
  aggregate, and keep the complete architecture-test inventory below its
  ceiling at 5,373 lines. All 147 focused model, Talk-runtime, voice-input,
  voice-coordinator, and architecture tests pass with zero failures or skips in
  `build/DerivedData-VoiceTalkBridgeSplit/Logs/Test/Test-Nile-2026.08.09_14-21-42-+0200.xcresult`.
  Exact staged tree `26988f2b7c537d52c8ce0f0d61613fb8ac71fb89`
  passes all 688 unit/protocol tests with zero failures, skips, or expected
  failures, and its warnings-as-errors optimized unsigned Release build passes
  with `SessionListModelTalk.swift` compiled and no packaged
  `NSAppTransportSecurity` dictionary; retained evidence is under
  `build/voice-talk-bridge-exact-26988f2b7c53/`.
- Split the near-capacity model-facing turn bridge along its existing
  admission/settlement boundary without changing transport or event ownership.
  The former 347-line `SessionListModelTurn` is now a 221-line admission and
  background-lifecycle adapter plus a 136-line settlement adapter that alone
  owns protected-draft recovery and prompt/steer/Stop visible outcomes.
  Architecture guards enforce unique method and transport/settlement ownership,
  exclude repository and event-stream capabilities from both sources, retain the
  single ordered Hermes event application boundary, cap the sources at 235/150
  lines and 365 lines in aggregate, and keep the complete architecture-test
  inventory below its ceiling at 5,358 lines. The same architecture record now
  reflects the already-landed 260/205-line command admission/settlement split
  instead of its obsolete pre-split count. All 140 focused model, turn-runtime,
  and architecture tests pass with zero failures or skips in
  `build/DerivedData-TurnSettlementSplit/Logs/Test/Test-Nile-2026.08.09_14-13-16-+0200.xcresult`.
  Exact staged tree `f83dc45a0c4b77a1824ceb48f108300b9acea038`
  passes all 688 unit/protocol tests with zero failures or skips and an optimized
  unsigned Release device build with Swift and Clang warnings treated as errors;
  the build compiles the new settlement source and its packaged plist has no ATS
  dictionary. The retained result bundle, logs, and inspection record are under
  `build/turn-settlement-exact-f83dc45a/`.
- Made build configuration—not runtime argument filtering—the hard boundary for
  the complete app/session fixture graph. Roughly 2,000 lines of session
  catalogs, embedded media/sample state, fake profile/connection/voice
  collaborators, fixture selection/assembly/installation, and the model fixture
  initializer now compile only for `DEBUG || NILE_LOCAL_RELEASE`; App Store
  Release retains compact no-op plan, assembly, and installer seams so
  production composition stays branch-free. The LocalRelease-only streaming
  stress lane remains available through the existing filtered argument policy.
  Architecture guards pin the five app-graph and three session-catalog build
  gates, the Release stub branches, a 350-line model-core cap, an 875-line
  session-catalog aggregate, and the existing 1,450-line app-graph aggregate;
  the complete architecture-test inventory remains below its ceiling at 5,329
  lines. All 144 focused model, fixture-plan, and architecture tests pass with
  zero failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_13-59-36-+0200.xcresult`.
  Exact staged tree `7268ee4624fa77bba2f465dde7f75b3b496a7546`
  passes all 688 unit/protocol tests with zero failures or skips, plus
  warnings-as-errors unsigned Release and LocalRelease device builds. Its
  Release binary contains no representative fixture payload strings and no ATS
  dictionary, while LocalRelease retains the permitted stress payload and
  explicit arbitrary-load policy. The retained result bundle, build logs, and
  inspection record are under `build/app-fixture-gate-exact-7268ee46/`.
- Removed delegated-agent sample payloads and fixture mutation from Release and
  from the production runtime/model bridge. The 206-line delegation fixture
  catalog, 40-line runtime adapter, and 31-line model adapter are now entirely
  `#if DEBUG`; the app-graph installer reaches them only through a Debug-gated
  call site. `SessionDelegationRuntime` shrinks from 390 to 364 lines while
  retaining the sole delegation capability, coordinator, task registry,
  lifecycle generation, persistence, reconciliation, and interrupt ownership;
  `SessionListModelDelegation` shrinks from 185 to 158 lines while retaining
  production projection, control, navigation, and ordered-event callbacks. Two
  direct regressions prove the extracted adapter still uses the production
  event/parent-completion and presentation paths. Architecture guards exclude
  fixture contracts from both production owners, enforce all seven source caps
  plus a 1,400-line aggregate, and reduce the global architecture-test inventory
  from 5,338 to 5,311 lines. All 18 focused fixture-plan, delegation,
  integration, and architecture tests pass with zero failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_13-48-04-+0200.xcresult`.
  The exact staged tree `51d4febfeae2582ab5e8b6c043906367e720335c`
  also passes all 688 unit/protocol tests with zero failures or skips in
  `build/DerivedData-DelegationFixtureExact/Logs/Test/Test-Nile-2026.08.09_13-52-51-+0200.xcresult`
  and an optimized unsigned Release device build with compiler warnings treated
  as errors. Its binary contains none of the delegation sample payload strings,
  and its packaged plist has no `NSAppTransportSecurity` dictionary.
- Split gateway-setup construction and Debug fixture ownership out of the
  observable model without changing connection, authentication, voice, or
  fixture behavior. The 306-line `GatewaySetupModel` core now delegates
  production dependency resolution to an 85-line `GatewaySetupDependencies`
  owner and Debug-only launch-fixture setup to a 64-line
  `GatewaySetupModelDebugFixtures` extension; the core no longer imports WebKit,
  constructs the production secure profile/authentication/cookie/WebSocket or
  voice graph, recognizes fixture arguments, or embeds sign-in HTML. A direct
  fixture regression proves that the gateway sign-in fixture suppresses saved
  profile restoration before any store read. Architecture guards enforce unique
  construction/fixture ownership, 320/100/80/310/300/175-line caps across the
  six setup owners, a 1,210-line aggregate, 30 behavior tests across bounded
  test sources, and reduce the global architecture-test inventory from 5,378 to
  5,338 lines. All 46 focused setup, authentication, and architecture tests pass
  with zero failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_13-35-34-+0200.xcresult`.
  The exact staged tree `97c74dcded7aff25fcc7a14aabb193f61850f5ee`
  also passes all 686 unit/protocol tests with zero failures or skips in
  `build/DerivedData-GatewaySetupExact/Logs/Test/Test-Nile-2026.08.09_13-38-53-+0200.xcresult`
  and an optimized unsigned Release device build with compiler warnings treated
  as errors; the packaged Release app has no `NSAppTransportSecurity` dictionary.
- Split the former 355-line mixed transcript parser without changing its public
  API or media behavior. The 13-line `TranscriptParsing` source now owns only
  `ParsedMessageContent` and the `parseMessageContent` entry point; a 122-line
  `TranscriptMessageParser` owns parsed-content assembly, legacy image-marker
  stripping, directives, and attachment classification; a 154-line
  `TranscriptMediaMarkerParser` owns absolute-reference recognition, protected
  Markdown/JSON example masking, path normalization, and supported extensions;
  and a 111-line `TranscriptRegex` source owns only reusable UTF-16-safe regex,
  capture, masking, replacement, and range-removal mechanics. All four sources
  remain Foundation-only or Foundation-free and have no SwiftUI, UIKit, Hermes,
  repository, event-stream, or task dependency. The six direct parser
  regressions now live in a dedicated test source instead of the UIKit-heavy
  transcript-projection suite, which shrinks from 492 to 365 lines.
  Architecture guards enforce unique ownership, 30/135/170/125-line caps, a
  420-line parsing aggregate, and reduce the global architecture-test inventory
  from 5,386 to 5,378 lines under its unchanged 5,400-line ceiling. All 17
  focused parser, projection, and architecture tests pass with zero failures or
  skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_13-18-42-+0200.xcresult`.
  The exact staged tree `f21c545def65bca43f74c603ad956ccb9fba890c`
  also passes all 685 unit/protocol tests with zero failures or skips in
  `build/DerivedData-TranscriptParserExact/Logs/Test/Test-Nile-2026.08.09_13-21-47-+0200.xcresult`
  and an optimized unsigned Release device build with warnings treated as
  errors; the packaged Release app has no `NSAppTransportSecurity` dictionary.
- Extracted live transcript image-payload retention from the transcript
  coordinator. The 53-line Sendable `TranscriptImagePayloadCache` is now the
  sole owner of the path-to-base64 map, recency order, aggregate character
  count, entry/character limits, replacement behavior, oldest-first eviction,
  and reset mechanics. `LiveTranscriptCoordinator` retains its existing cache
  API through one collaborator while its source shrinks from 361 to 336 lines
  and its directly owned raw state stays limited to assistant/tool projection
  plus that single cache collaborator.
  The payload-specific name keeps this bounded value cache distinct from the
  existing UIKit decoded-image cache. The extracted source has no Foundation,
  UIKit, transcript-entry, Hermes, task, repository, or event-stream dependency.
  Three direct cache tests cover entry and character pressure, recency refresh,
  oversized replacement, clearing, and disabled limits; the retained
  coordinator API has a direct delegation regression. Architecture guards
  enforce unique raw-state ownership, 350/65-line caps, a 405-line aggregate,
  and the unchanged global architecture ceiling. All 24 focused cache,
  coordinator, timeline, and architecture tests pass with zero failures or
  skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_13-06-49-+0200.xcresult`.
  The exact staged tree `d1145b12e52176cc9b54abb738fb5d056a8364b6`
  also passes all 685 unit/protocol tests with zero failures or skips in
  `build/DerivedData-TranscriptPayloadCacheExact/Logs/Test/Test-Nile-2026.08.09_13-10-21-+0200.xcresult`
  and an optimized unsigned Release device build with warnings treated as
  errors; the packaged Release app has no `NSAppTransportSecurity` dictionary.
- Split the former 369-line mixed transcript-model source without changing its
  projection behavior. The 248-line `TranscriptModels` source now owns only the
  immutable roles, attachments, messages, tools, blocking prompts, commands,
  delegation anchors, and entry sum type. A byte-identical 122-line
  `TranscriptPresentation` source independently owns display rows, adjacent-tool
  grouping, clarification/empty-assistant filtering, pinned-delegation removal,
  and the last-user, streaming-entry, and actionable-prompt viewport signals.
  Both boundaries remain Foundation-only and contain no SwiftUI, UIKit,
  repository, task, or event-routing authority. Architecture guards enforce
  unique contract/presentation ownership, 270/140-line caps, a 390-line
  aggregate, and the unchanged global architecture ceiling. A new direct
  projection regression covers blank/`null` filtering, media-only visibility,
  and streaming-tail retention; all 17 focused projection and architecture
  tests pass with zero failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_12-55-45-+0200.xcresult`.
  Exact tested implementation tree
  `8d79beed50e9a53d7191515afb2c1dee45275e78` passes all 682 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-TranscriptPresentationExact/Logs/Test/Test-Nile-2026.08.09_12-59-01-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-TranscriptPresentationReleaseExact`, and the packaged
  Release plist contains no ATS override.
- Extracted gateway identity and terminal/Claim provenance from the app-model
  core. The capability-free 104-line `SessionGatewayContextRuntime` is now the
  sole mutable owner of repository availability, loaded production identity,
  fixture identity fallback, remembered terminal sessions, and successful
  Claim overrides; `SessionRuntimeComposition` constructs the exact production
  or fixture context. A bounded 76-line `SessionListModelGatewayContext` bridge
  retains only narrow forwarding and the guarded successful-Claim settlement
  into observable session, transcript, and usage state. This removes the three
  hidden `hasRepository`, `loadedGatewayID`, and ownership state declarations
  plus their cross-feature helpers from `SessionListModel`, reducing its core
  from 399 to 326 lines without adding a repository, transport, refresh task, or
  event consumer. Six direct context tests cover production/fixture identity,
  list classification, partial-page memory, explicit source lookup, Claim
  precedence, and gateway reset. Architecture guards enforce unique context
  state and bridge ownership, 115/90-line caps, construction-root ownership,
  the 410-line core cap, and the existing single ordered event-application
  boundary while keeping the global architecture ceiling unchanged. The pinned
  Android/Hermes oracle verifies at the governing commits, and all 10 focused
  context/architecture tests pass with zero failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_12-40-56-+0200.xcresult`.
  Exact tested implementation tree
  `0edd640e62aac3974021bdc113c87d360556ab4d` passes all 681 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-GatewayContextExact2/Logs/Test/Test-Nile-2026.08.09_12-49-19-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-GatewayContextReleaseExact2`, and the packaged Release
  plist contains no ATS override.
- Split immutable Talk state-machine contracts out of the former 399-line mixed
  coordinator. The 96-line Foundation-only `TalkModeContracts` source owns all
  phase/UI-state values, validated gateway/session/live-runtime owner identity,
  opaque mode/turn/relisten tokens, and recognition/relisten decisions. The
  byte-identical 304-line `@MainActor` `TalkModeCoordinator` now owns only the
  mutable generation/sequence counters, blank-result tracking, active tokens,
  and recognition, turn, pause/resume, invalidation, and relisten transitions;
  the only access change makes token generation/initializers module-internal so
  that sole coordinator can construct and validate them across the source
  boundary. Architecture guards enforce unique contract/coordinator ownership,
  exclude tasks, Hermes capabilities, and `SessionTalkRuntime` from the contract
  source, cap the pair at 325/110 lines and 420 lines in aggregate, retain the
  existing Talk-runtime caps, and keep the global architecture ceiling
  unchanged. All 76 focused coordinator, runtime, submission-policy, and
  architecture tests pass with zero failures or skips in
  `build/DerivedData-TalkCoordinatorContractsFocused`. Exact staged tree
  `7ad7e0d88ee30ff050e60d470792673b63786830` passes all 680 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-TalkCoordinatorContractsExact/Logs/Test/Test-Nile-2026.08.09_12-32-26-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-TalkCoordinatorContractsReleaseExact`, and the packaged
  Release plist contains no ATS override.
- Split the former 404-line mixed transcript-tool surface into a byte-identical
  189-line `TranscriptToolActivityRows` owner for grouped disclosure, current-
  action/status/count presentation, tap-position ripple, and Reduce Motion
  handling, plus a byte-identical 210-line `TranscriptToolRows` owner for the
  one specialized-card dispatcher and default/terminal tool cards. The generic
  six-line non-empty collection helper moved from file-private default-card
  scope into the existing 72-line shared tool-row support boundary so both
  surfaces can consume it without duplicating policy. Architecture guards
  enforce unique activity/ripple/wave and dispatcher/default/header ownership,
  mutual exclusions, 210/230-line caps, the retained sub-3,100 transcript-
  surface aggregate, and the unchanged global architecture ceiling. All 91
  focused architecture, projection, event-timeline, and live-coordinator tests
  pass with zero failures or skips in
  `build/DerivedData-TranscriptToolRowsFocused`; the selector-driven grouped-
  action/active-plan disclosure XCUITest passes in
  `build/DerivedData-TranscriptToolRowsUI`. Exact staged tree
  `49cf49451aad3212388adb3e25462ca7d4727f66` passes all 680 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-TranscriptToolRowsExact/Logs/Test/Test-Nile-2026.08.09_12-25-18-+0200.xcresult`;
  its grouped-action/active-plan XCUITest passes in
  `build/DerivedData-TranscriptToolRowsUIExact/Logs/Test/Test-Nile-2026.08.09_12-26-29-+0200.xcresult`.
  The warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-TranscriptToolRowsReleaseExact`, and the packaged Release
  plist contains no ATS override.
- Split the former 431-line Hermes voice sheet into a 159-line model-bound
  `HermesVoiceSheetView` and a 312-line model-free `HermesVoiceEditorView` that
  owns the unchanged provider card, preset rail, input, status/notice views,
  Apply control, and Material pressed style through explicit retry/apply
  callbacks. The existing Foundation-only `HermesVoicePresentation` now also
  owns whitespace normalization and Apply admission, with a direct regression
  covering disabled, blank, unchanged, trimmed, and changed drafts.
  Architecture guards enforce unique sheet/editor/status ownership, exclude
  `GatewaySetupModel` and its mutations from the editor, cap the three voice
  sources at 175/325/125 lines, retain the sub-1,300 settings aggregate and
  sub-1,800 gateway-surface aggregate, and keep the global architecture ceiling
  unchanged. All 91 focused setup-model and architecture tests pass with zero
  failures or skips in `build/DerivedData-HermesVoiceEditorFocused`. Exact
  staged tree `281d563a01bafa2334245519140196c417cbf3fd` passes all 680
  unit/protocol tests with zero failures or skips in
  `build/DerivedData-HermesVoiceEditorExact/Logs/Test/Test-Nile-2026.08.09_12-12-55-+0200.xcresult`;
  its selector-driven load/change/apply/summary XCUITest passes in
  `build/DerivedData-HermesVoiceEditorUIExact/Logs/Test/Test-Nile-2026.08.09_12-14-08-+0200.xcresult`.
  The warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-HermesVoiceEditorReleaseExact`, and the packaged Release
  plist contains no ATS override.
- Split the former 436-line mixed Talk surface into independently bounded
  orchestration, controls, and presentation-policy owners. The 246-line
  `TalkModeView` alone binds `SessionListModel`, blocking-prompt rendering, and
  all lifecycle/action callbacks. The 118-line `TalkModeControls` source owns
  the existing reduced-motion 188/172/132/84-point orb and 92-by-75-point
  semantic controls without model or blocking-prompt access. The 74-line
  Foundation-only, `Equatable`, `Sendable` `TalkPresentation` policy owns every
  phase/blocking/run-state/working-label copy and primary-action decision
  without SwiftUI or model access. Four direct policy regressions exhaustively
  cover all phases, blocking dominance, active-run Stop admission, working-label
  fallback, and speaking detail. Architecture guards enforce unique ownership,
  275/140/100-line source caps, a 500-line aggregate, and the retained sub-5,400
  global architecture ceiling. All 80 focused presentation, coordinator,
  runtime, submission-policy, and architecture tests pass with zero failures or
  skips in `build/DerivedData-TalkSurfaceSplitFocused`. Exact staged tree
  `83899aa0d8ab43cf4cf2d90a89d6ea23869e13b7` passes all 679 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-TalkSurfaceSplitExact/Logs/Test/Test-Nile-2026.08.09_12-00-48-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-TalkSurfaceSplitReleaseExact`, and the packaged Release
  plist contains no ATS override.
- Split stateful clarification input and reusable prompt controls out of the
  former 450-line blocking-prompt card source. The 221-line
  `BlockingPromptView` remains the sole fail-closed prompt-card frame, kind
  dispatcher, resolved-summary, response-callback, and card-accessibility
  owner. The 230-line `BlockingPromptActions` owns clarification selection/text
  state, Continue/skip admission, status presentation, and reusable buttons
  without prompt policy, response tasks, secure-entry state, permanent-approval
  state, a transcript controller, or another card dispatcher. The existing
  123-line `BlockingPromptOverlays` remains the only privacy-sensitive secure
  response and permanent-approval confirmation surface. Architecture guards
  enforce 240/250/150-line card/action/overlay caps, unique component ownership,
  the retained 3,100-line transcript-surface aggregate, and the global
  architecture ceiling. All 72 focused architecture, coordinator, runtime, and
  model blocking-prompt tests pass with zero failures or skips in
  `build/DerivedData-BlockingPromptActionsSplitFocused`. Exact staged tree
  `59649c7f5eabe4da4ee6180e4e1a58576c5d545c` passes all 674 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-BlockingPromptActionsSplitExact/Logs/Test/Test-Nile-2026.08.09_11-49-31-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-BlockingPromptActionsSplitReleaseExact`, and the packaged
  Release plist contains no ATS override.
- Extracted reusable offset and viewport-resize policy from the transcript's
  UIKit controller. The 436-line `TranscriptViewportController` remains the sole
  collection-view, scroll-delegate, scroll-owner/coordinator, pending-position,
  layout-settlement, UIKit offset-application, anchoring, and accessibility
  authority. The 65-line CoreGraphics-only
  `TranscriptViewportPositionPolicy` owns min/max offset geometry, clamping,
  bottom tolerance, and exact fitting-content/repeated-shrink/expansion
  preservation without UIKit, a controller, row host, scroll coordinator, or
  owner identity. Four direct policy regressions cover adjusted-inset bounds,
  fitting content, repeated shrink preservation, and long-content detachment
  safety. Architecture guards enforce 450/80-line controller/policy caps, unique
  responsibility ownership, the retained 3,100-line transcript-surface
  aggregate, and the global architecture ceiling. All 72 focused policy,
  scroll-coordinator, and architecture tests pass with zero failures or skips in
  `build/DerivedData-ViewportPositionSplitFocused`. Exact staged tree
  `1f523d4b76f83d98c1626cd7a31dc12e324f55c9` passes all 674 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-ViewportPositionSplitExact/Logs/Test/Test-Nile-2026.08.09_11-41-33-+0200.xcresult`.
  Its warnings-as-errors optimized unsigned Release build passes in
  `build/DerivedData-ViewportPositionSplitReleaseExact`, and the packaged
  Release plist contains no ATS override.
- Split the former 440-line gated dashboard sign-in source into independent
  presentation, WebKit, and navigation-policy owners. The 185-line
  `GatewaySignInView` retains visible-origin, loading/error/retry, Continue, and
  explicit external-origin approval state without importing WebKit. The
  159-line `GatewayLoginWebView` exclusively owns persistent cookie-backed
  `WKWebView` setup, loading/reloading, main-frame delegate decisions, HTTP
  failure projection, and approved-navigation resumption without policy/helper
  declarations. The 98-line Foundation-only `GatewayLoginNavigationPolicy`
  retains same-origin path-prefix enforcement, external HTTPS approval,
  credential/malformed-target rejection, and canonical origin/display helpers.
  Architecture guards enforce 210/180/115-line caps, responsibility exclusions,
  unique declaration ownership, the bounded 1,800-line gateway-surface
  aggregate, and the global architecture ceiling. All 75 focused authentication
  and architecture tests pass with zero failures or skips in
  `build/DerivedData-GatewaySignInSplitFocused`. Exact staged tree
  `7bb31aba73d06e0a92227ee77dd9614d8f2a7421` passes all 670 `NileTests` with
  zero failures or skips in
  `build/DerivedData-GatewaySignInSplitExact/Logs/Test/Test-Nile-2026.08.09_11-33-12-+0200.xcresult`.
  Its optimized unsigned generic-device Release build also passes with Swift
  and GCC warnings treated as errors in
  `build/DerivedData-GatewaySignInSplitReleaseExact`, and the built Release
  `Info.plist` contains no `NSAppTransportSecurity` override.
- Split deterministic launch-fixture selection from fake capability assembly.
  The 267-line `NileAppGraphFixturePlan` remains the sole filtered argument and
  precedence authority, now storing a compact gateway-fixture selection instead
  of constructing credential-bearing profiles. The 156-line
  `NileAppGraphFixtureAssembly` extension exclusively constructs selected
  biometric, gateway profile/connection/cleanup, Hermes voice, and session-model
  collaborators without raw launch arguments, production repositories,
  authentication services, or deterministic state installation. Architecture
  guards enforce 285/170-line caps, unique ownership of all seven assembly
  methods, the existing 1,450-line app-graph aggregate, and a sub-5,400-line
  architecture-test aggregate. All 68 focused fixture-plan and architecture
  tests pass with zero failures or skips in
  `build/DerivedData-FixtureAssemblySplitFocused`. Exact staged tree
  `fee5c521e18e1a71af15a93d3b1079af37a34ad5` passes all 669 `NileTests` with
  zero failures or skips in
  `build/DerivedData-FixtureAssemblySplitExact/Logs/Test/Test-Nile-2026.08.09_11-23-47-+0200.xcresult`.
  Its optimized unsigned generic-device Release build also passes with Swift
  and GCC warnings treated as errors in
  `build/DerivedData-FixtureAssemblySplitReleaseExact`, and the built Release
  `Info.plist` contains no `NSAppTransportSecurity` override.
- Split the 401-line slash-command domain policy into independent dispatch and
  discovery authorities. The 281-line `NileSlashPolicy` exclusively owns
  command parsing, native routing, allow/block decisions, profile collision
  handling, and fail-closed user guidance. The 142-line
  `NileSlashCatalogPolicy` owns the curated catalog value, discovery hiding,
  descriptions, and root/nested completion filtering while delegating every
  visibility safety judgment to `NileSlashPolicy.decide`; it cannot execute a
  command or own a repository, task, or event stream. Policy tests are likewise
  separated into 67-line dispatch and 105-line catalog sources. Architecture
  guards enforce 300/155-line caps, a 440-line production aggregate, unique
  declaration ownership, capability exclusions, and both policy dependencies
  in `SessionCommandRuntime`. All 68 focused architecture, policy, runtime, and
  model-integration tests pass with zero failures or skips in
  `build/DerivedData-SlashPolicySplitFocused`. Exact staged tree
  `7f7d90a14eb6bfcec753ae5abbf9e15e2b634bb2` passes all 667 `NileTests` with
  zero failures or skips in
  `build/DerivedData-SlashPolicySplitExact/Logs/Test/Test-Nile-2026.08.09_11-11-31-+0200.xcresult`.
  Its optimized unsigned generic-device Release build also passes with Swift
  and GCC warnings treated as errors in
  `build/DerivedData-SlashPolicySplitReleaseExact`, and the built Release
  `Info.plist` contains no `NSAppTransportSecurity` override.
- Extracted versioned gateway-profile metadata encoding and validation from the
  former 341-line transaction actor. The 207-line `GatewayProfileStore` now
  exclusively owns profile/credential transactions, pointer commits, rollback,
  and persisted cleanup-ledger retry, while the 146-line
  `GatewayProfileStoreCodec` owns deterministic JSON encoding/decoding,
  envelope and persisted-profile schemas, version and identity validation,
  display-name fallback, and domain-profile reconstruction. The codec has no
  actor, storage capability, protected-file, Security, or Keychain dependency;
  the 63-line contracts and 105-line secure adapters remain independently
  bounded. Architecture guards enforce 75/225/160/125-line caps, unique
  transaction/codec/adapter authority, and a 530-line aggregate. All 71 focused
  architecture, transaction-store, codec, and secure-storage integration tests
  pass with zero failures or skips in
  `build/DerivedData-GatewayProfileCodecFocused`. The exact staged
  implementation tree `4bdedff57b6e853c9fa00da2cd40646f7217ce04`
  passes all 666 `NileTests` with zero failures or skips in
  `build/DerivedData-GatewayProfileCodecExact/Logs/Test/Test-Nile-2026.08.09_11-01-47-+0200.xcresult`;
  its optimized unsigned generic-device Release build also succeeds with Swift
  and Clang warnings treated as errors under
  `build/DerivedData-GatewayProfileCodecReleaseExact`, and the generated
  Release `Info.plist` contains no ATS exception.
- Extracted cancellation-safe cookie-rotation admission from the former
  382-line authentication actor. The 299-line `GatewayAuthenticationService`
  remains the sole status/HTTP/cookie/profile/event authority and owns gated
  preflight, ticket minting, managed request/response cookie effects, expiry
  publication, logout, and scope validation. The 91-line
  `GatewayCookieRotationGate` actor exclusively owns lock/waiter state, FIFO
  continuation admission, cancellation shielding for admitted mutations, and
  interruptible bounded-download release. It declares no HTTP transport,
  cookie store, gateway profile, authentication event, URL request, or WebKit
  dependency. The persistent cookie store and stateless cookie policy remain
  independently bounded. Architecture contracts enforce 315/105/95/205-line
  caps, a 680-line aggregate, unique rotation state, and capability exclusion.
  The 116 focused architecture, authentication/cookie-policy, dashboard-client,
  and gateway-setup tests pass with zero failures or skips in
  `build/DerivedData-GatewayCookieRotationFocused`. The exact staged tree
  `9c7019062f1abf2f2e153ef27cc2b85cb819bede` passes all 663 `NileTests`
  with zero failures or skips in the 2026-08-09 10:50:45 +0200 result bundle
  under `build/DerivedData-GatewayCookieRotationExact`; its unsigned generic
  device Release build also succeeds with Swift and Clang warnings treated as
  errors under `build/DerivedData-GatewayCookieRotationReleaseExact`, and the
  generated Release `Info.plist` contains no ATS exception.
- Split exact attachment-draft transactions out of the former 382-line
  protected-file actor source. The 172-line `AttachmentDraftStore` core remains
  the sole declaration authority for `ProtectedAttachmentDraftStore`,
  `ProtectedFileStorage`, the removed-gateway fence, versioned envelope,
  validation/size policy, revision conflict application, and file
  write/remove error mapping. Its 224-line same-actor
  `AttachmentDraftStoreTransactions` extension owns snapshot loads, draft
  updates, mutation begin/advance/recovery/clear, guarded multi-record migration,
  and gateway erasure. The transaction source declares no protected storage,
  removed-gateway state, envelope, size limit, storage capability, or file-
  protection policy. Architecture contracts enforce 185/235-line caps, a
  410-line store aggregate, a 600-line contracts-plus-store aggregate, and sole
  mechanics/transaction ownership. The 218 focused architecture, protected-
  store, attachment-persistence/recovery, creation-draft, and session-model
  tests pass with zero failures or skips in
  `build/DerivedData-AttachmentStoreTransactionsFocused`. Exact staged code tree
  `feba508dad5c927697d0d582427ea406f3bca710` passes all 663 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-AttachmentStoreTransactionsExact/Logs/Test/Test-Nile-2026.08.09_10-43-15-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors from `build/DerivedData-AttachmentStoreTransactionsReleaseExact`, and
  the packaged Release plist contains no ATS override.
- Split image-preview execution out of the former 396-line media runtime. The
  165-line `SessionMediaRuntime` core remains the sole observable runtime and
  declaration authority for `HermesAttachmentReading`, `AttachmentCaching`,
  viewer state/tasks/generation, preview task/failure registries, owner/update
  values, byte limits, and reset coordination. Its 243-line same-runtime
  `SessionMediaPreviewRuntime` extension owns transcript reconciliation,
  two-request scheduling, eight-image retention and pruning, MIME validation,
  base64 projection, UUID fencing, cancellation, and completion callbacks. The
  preview source declares no capability, cache, stored/task state, repository
  type, observable runtime, or event boundary. Architecture contracts enforce
  unique authority declarations, 180/255-line caps, a 420-line aggregate, and
  one model event boundary. The 200 focused architecture, direct media-runtime,
  and session-model tests pass with zero failures or skips in
  `build/DerivedData-MediaPreviewSplitFocused`. Exact staged code tree
  `9158d6b209eea567a0c1cdc21778d6930f70cc4d` passes all 663 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-MediaPreviewSplitExact/Logs/Test/Test-Nile-2026.08.09_10-35-46-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors from `build/DerivedData-MediaPreviewSplitReleaseExact`, and the
  packaged Release plist contains no ATS override.
- Split replaceable and immediate draft-write execution out of the former
  361-line persistence runtime. The 245-line
  `SessionDraftPersistenceRuntime` core remains the sole declaration authority
  for `ComposerDraftStoring`, the protected-record mirror, write-task registry,
  and monotonic timestamp sequencer; it owns restoration, exact claim and
  retirement transactions, missing-owner migration CAS, tombstones, and record
  creation. Its 122-line same-runtime `SessionDraftPersistenceWrites`
  extension owns text writes, full flushes, recovered-draft persistence,
  debounce scheduling/cancellation, store execution, and failure delivery. The
  write source declares no second store, record/task/timestamp state,
  repository, or event boundary, and `SessionDraftLifecycleRuntime` continues
  to compose the same authority. Architecture contracts enforce unique
  authority declarations, 260/135-line caps, a 390-line aggregate, and one
  model event boundary. The 217 focused architecture, draft-store,
  persistence, lifecycle, attachment-recovery, and model tests pass in
  `build/DerivedData-DraftPersistenceWritesFocused`. The exact staged code tree
  passes the full 663-test unit/protocol suite with zero failures or skips in
  `build/DerivedData-DraftPersistenceWritesExact/Logs/Test/Test-Nile-2026.08.09_10-26-56-+0200.xcresult`; its warnings-as-errors optimized unsigned
  Release build passes from
  `build/DerivedData-DraftPersistenceWritesReleaseExact`, and the built Release
  app contains no `NSAppTransportSecurity` override.
- Split attachment upload/prompt execution out of the former 431-line transport
  runtime. The 158-line `SessionAttachmentRuntime` core remains the sole
  declaration authority for the exact mutation, prompt, and disconnect
  capabilities, `AttachmentDeliveryCoordinator`, delivery and confirmation task
  registries, timeout configuration, and lifecycle generation; it owns stream-
  event correlation callbacks, lease cleanup, quarantine, retirement, and
  reset. Its 279-line same-runtime `SessionAttachmentDelivery` extension owns
  preparation, sequential upload, marker handoff, prompt submit/response
  resolution, buffered-start acceptance, confirmation timeout/disconnect,
  generation validation, task completion, and fail-closed uncertainty policy.
  The delivery source declares no capability, coordinator, task registry,
  generation, repository, or event-stream authority, while protected state
  remains in the persistence runtimes. Architecture contracts enforce unique
  authority declarations, 175/290-line caps, a 470-line aggregate, transport-
  capability exclusions, and one model event boundary. All architecture,
  delivery-coordinator/runtime, and session-model checks pass without failures
  or skips (205 focused tests) in
  `build/DerivedData-AttachmentDeliveryFocused/Logs/Test/Test-Nile-2026.08.09_10-17-16-+0200.xcresult`.
  Exact staged tree `67ff596e7e574fab50a1608de55561f46a5798c1`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-AttachmentDeliveryExact/Logs/Test/Test-Nile-2026.08.09_10-19-12-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split recovered composer reconstruction out of the former 425-line relaunch-
  recovery runtime. The 264-line `SessionAttachmentRecoveryRuntime` core keeps
  immutable outcomes/contracts, the single dependency set, read-only runtime
  and durable-history acceptance proof, missing-owner resolution, exact commit
  guards, marker transitions, and quarantine decisions. Its 163-line same-
  runtime `SessionAttachmentRecoveryComposer` extension owns ordinary-text and
  marker consolidation, deduplicated photo reconstruction, recovered-edit
  scheduling/fallback, in-memory projection restore, and protected ordinary-
  draft retirement. The extension has no navigation capability, stored state,
  task registry, storage protocol, repository, or event path; dependency
  declarations remain unique in the core and the existing persistence/edit
  runtimes retain CAS and task authority. Architecture contracts enforce
  280/175-line caps, a 440-line aggregate, unique dependency ownership, exact
  responsibility placement, and one model event boundary. All architecture,
  attachment-persistence/recovery, creation-handoff, and session-model checks
  pass without failures or skips (210 focused tests) in
  `build/DerivedData-AttachmentRecoveryComposerFocused/Logs/Test/Test-Nile-2026.08.09_10-08-50-+0200.xcresult`.
  Exact staged tree `9c13e23aec80de346f5e87f7935d8e058c500187`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-AttachmentRecoveryComposerExact/Logs/Test/Test-Nile-2026.08.09_10-11-13-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Decomposed the former 408-line ordered model event core into explicit stages
  without adding another consumer or router. The 48-line
  `SessionListModelEvents` extension retains routing startup and the sole
  private `consume(_:)` method, which orders cached projection,
  delegation/lifecycle settlement, blocking-input interception, terminal
  resource settlement, and visible projection exactly once. The 128-line
  `SessionListModelEventSettlement` extension owns delegation/lifecycle,
  blocking-prompt, Talk, attachment-error, and terminal cleanup effects; the
  302-line `SessionListModelVisibleEventProjection` extension owns connection-
  loss reset and visible message/tool/goal/error/session projection; and the
  existing 133-line `SessionListModelEventProjection` extension retains
  assistant-delta cadence helpers, hidden-session projection, attached-turn
  refresh, and shared goal/tool/blocking-input helpers. None owns a repository,
  event task, or stream; `SessionEventRuntime` remains the only stream consumer.
  Architecture contracts enforce the exact stage order, one private consumer,
  60/140/315/140-line source caps, a 625-line event aggregate, a transparent
  2,050-line model-orchestration aggregate, and the global 5,400-line contract
  ceiling. All architecture, event-runtime/projector, and session-model checks
  pass without failures or skips (204 focused tests) in
  `build/DerivedData-EventPipelineFocused/Logs/Test/Test-Nile-2026.08.09_10-01-22-+0200.xcresult`.
  Exact staged tree `b6fc408c045965b04f85c226bcef8702dcca5648`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-EventPipelineExact/Logs/Test/Test-Nile-2026.08.09_10-04-01-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split authenticated production-session opening out of the former 412-line
  navigation bridge. The 267-line `SessionListModelNavigation` extension keeps
  public selection admission, cross-feature reset/cancellation, fixture and
  cached-switch presentation, pins, display-owner/status/overlay helpers, and
  goal projection. The 173-line `SessionListModelSessionOpening` extension owns
  an immutable Sendable opening request, exact gateway/display fencing, stored
  source and terminal/live routing, attachment-recovery quarantine, live open,
  cached-timeline restore, usage/goal synchronization, and success,
  cancellation, and error settlement. The selection source contains no route
  switch or stored/live transport calls, while the opening source has no
  fixture, reset, pin, owner-helper, active-status, or selected-overlay
  authority. Neither source constructs a repository or consumes Hermes events;
  the navigation runtime retains transport/task capabilities and the model
  retains one ordered event boundary. Architecture contracts enforce
  285/190/125-line selection/opening/refresh caps, a 560-line navigation
  aggregate, and participates in the transparent 2,050-line model-orchestration
  aggregate. All
  navigation, ownership, attachment-recovery, usage, session-model, and
  architecture checks pass without failures or skips (203 focused tests) in
  `build/DerivedData-SessionOpeningFocused/Logs/Test/Test-Nile-2026.08.09_09-50-34-+0200.xcresult`.
  Exact staged tree `25efcfcbc74686f0b59541680653ad465a1f26e7`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-SessionOpeningExact/Logs/Test/Test-Nile-2026.08.09_09-52-54-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split post-execution command settlement out of the former 425-line model
  bridge. The 260-line `SessionListModelCommands` extension retains catalog and
  completion projection, mobile-policy admission, native actions, exact draft
  claims, command-row creation, background-turn admission, and the sole
  `startExecution` call. Its 205-line
  `SessionListModelCommandSettlement` extension owns the immutable Sendable
  settlement context, runtime-outcome switch, definite/uncertain protected-draft
  recovery, successful claim retirement, visible/offscreen output delivery, and
  command-row mutation. The admission source contains no outcome cases or
  settlement helpers, while the settlement source has no policy decision,
  capture, task-start, claim-admission, or outbound-task authority. Neither
  source owns repository capabilities or consumes Hermes events; the command
  runtime retains transport/task/policy ownership and the model retains one
  ordered event application boundary. Architecture contracts enforce 275/225-
  line source caps, a 500-line command-bridge aggregate, a 425-line core-model
  cap, and a 900-line model-plus-command aggregate. All command policy,
  runtime cancellation/alias, protected-draft recovery, session-model, and
  architecture checks pass without failures or skips (200 focused tests) in
  `build/DerivedData-CommandSettlementFocused/Logs/Test/Test-Nile-2026.08.09_09-39-24-+0200.xcresult`.
  Exact staged tree `89e89fd10625b0ef7260bbbd7de02412dc0e1961`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-CommandSettlementExact/Logs/Test/Test-Nile-2026.08.09_09-41-09-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split offscreen event projection out of the former 421-line timeline runtime.
  The 163-line `SessionTimelineRuntime` remains the sole bounded-cache authority
  for the eight-session limit, live/stored indexes, LRU order, capture routing,
  removal, and reset. Its 262-line `SessionTimelineProjectionState` owns the
  mutable transcript/coordinator state for one parked live session, synchronous
  hidden-event projection, active-status outcomes, observed-event restore gate,
  and switch presentation. The core contains no event cases, tool projection,
  or runtime-state replacement, while the projection state contains no cache
  limit, indexes, recency, or eviction. Neither source consumes a stream,
  constructs a repository, or adds an event router. Architecture contracts
  enforce 175/275-line source caps, a 440-line aggregate, capability exclusions,
  and the single private model application boundary. All timeline cache,
  hidden-session restoration, live projection, complete session-model, and
  architecture checks pass without failures or skips (213 focused tests) in
  `build/DerivedData-TimelineProjectionFocused/Logs/Test/Test-Nile-2026.08.09_09-29-35-+0200.xcresult`.
  Exact staged tree `8dea7eceb1dcb35799f547c5a0a76cb1fec8d595`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-TimelineProjectionExact/Logs/Test/Test-Nile-2026.08.09_09-31-47-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split diffable row hosting out of the former 603-line transcript viewport
  controller. The current 436-line `TranscriptViewportController` remains the
  sole owner of the collection view, scroll delegate, UIKit content-offset
  application, anchor transitions, pending-position settlement, keyboard layout,
  and `TranscriptScrollCoordinator`, while a 65-line pure policy now owns only
  reusable offset geometry and viewport-resize preservation.
  Its 173-line `TranscriptViewportRowHost` collaborator exclusively owns item
  snapshots, hosted SwiftUI child containment, reusable-cell installation,
  targeted row reconfiguration, and row accessibility while receiving the one
  existing collection view and parent controller. It has no scroll owner,
  coordinator, content-offset, user-scroll, projection, or event authority.
  Architecture contracts enforce unique scroll, position-policy, and row-hosting
  ownership, 450/80/190-line controller/policy/helper caps, the retained 3,100-line transcript-surface
  aggregate, and the retained 5,400-line global architecture-contract ceiling.
  All viewport projection/diffing, host-transfer, scroll-anchor, live-transcript,
  and architecture checks pass without failures or skips (96 focused tests) in
  `build/DerivedData-ViewportRowHostFocused/Logs/Test/Test-Nile-2026.08.09_09-18-58-+0200.xcresult`.
  Exact staged tree `67987df821e283a80157aaeae08c86c13e195e84`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-ViewportRowHostExact/Logs/Test/Test-Nile-2026.08.09_09-22-21-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split model-row rendering out of the former 486-line stateful catalog. The
  310-line `ModelPickerCatalogView` remains the sole owner of query/focus state,
  provider expansion, filtered and pinned grouping, current-provider disclosure,
  and catalog composition. Its 180-line same-view `ModelPickerCatalogRows`
  extension isolates available and unresolved rows, selection and pin actions,
  capability/pricing presentation, physical hit regions, and accessibility IDs;
  the moved 176-line body is otherwise byte-for-byte unchanged. No second view
  state, model instance, runtime, task, repository, or event path was introduced.
  Architecture contracts enforce unique catalog-state and row-action ownership,
  350/325/200/75/50/140-line component caps, the retained 1,050-line picker
  aggregate, and the retained 5,400-line global architecture-contract ceiling.
  All model catalog, policy, pin-runtime, mutation/owner-fencing, and architecture
  checks pass without failures or skips (87 focused tests) in
  `build/DerivedData-ModelCatalogRowsFocused/Logs/Test/Test-Nile-2026.08.09_09-10-01-+0200.xcresult`.
  Exact staged tree `13ec0ad2b38b4e7ecd226e6a760377ae2f998d67`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-ModelCatalogRowsExact/Logs/Test/Test-Nile-2026.08.09_09-13-06-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split inbound WebSocket processing and terminal cleanup out of the former
  506-line transport actor. The 255-line `TuiGatewayClient` core remains the
  sole actor and owns connection admission, credential and socket creation,
  generation fencing, current-attempt state, the raw signal continuation, and
  receive-task installation. Its 256-line same-actor
  `TuiGatewayClientReceiveLifecycle` extension isolates the receive loop, frame
  dispatch, readiness, callback identity checks, protocol violations, failure
  emission, socket actions, and pending-call teardown. The existing 140-line
  request lifecycle retains request IDs, correlation, send, deadline, and
  response settlement without another actor, socket owner, connection state,
  or signal path. Architecture contracts enforce 275/275/155/75/175/70-line
  caps, a 975-line aggregate, the retained 5,400-line global ceiling, and unique
  actor, receive-loop, terminal-effects, signal-continuation, connection-attempt,
  and pending-call ownership. All 16 transport regressions and the complete 60-
  test architecture suite pass without failures or skips (76 focused tests) in
  `build/DerivedData-GatewayReceiveSplit/Logs/Test/Test-Nile-2026.08.09_08-59-40-+0200.xcresult`.
  Exact staged tree `e4c07b067776ca657e1663e161a36026a10f62e7`
  passes all 663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-GatewayReceiveExact/Logs/Test/Test-Nile-2026.08.09_09-02-10-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split model/reasoning mutation admission and settlement out of the former
  502-line model-control runtime. The 227-line `SessionModelControlRuntime` core
  remains the sole `@Observable` state, `HermesModelMutationServing` capability,
  control-task, generation, session-owner, pending-switch, and reset declaration
  owner while retaining catalog and protected-pin coordination. Its 285-line
  same-runtime `SessionModelControlMutationLifecycle` extension isolates model
  selection, session-scoped reasoning, expensive-model confirmation, owner-
  fenced completion, and fail-closed uncertain outcomes without another runtime,
  repository owner, or event path. `ModelOptionsRuntime`, `ModelPinRuntime`, pure
  `ModelControlPolicy`, and stable contracts retain their existing independent
  authorities. Architecture contracts enforce unique mutation-state ownership,
  240/290-line runtime caps, the retained 1,090-line model-control aggregate,
  and the global 5,400-line architecture-contract ceiling. All 20 focused
  model, reasoning, pin, command, event-ownership, and architecture tests pass
  without failures or skips in
  `build/DerivedData-ModelMutationSplitFocused/Logs/Test/Test-Nile-2026.08.09_08-20-29-+0200.xcresult`.
  Exact staged tree `c1ae642bf3fe0574cd35dbd683d695faf97c1ce4` passes all
  663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-ModelMutationSplitExact/Logs/Test/Test-Nile-2026.08.09_08-22-39-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split post-admission attachment settlement and relaunch recovery out of the
  former 475-line model bridge. The 293-line `SessionListModelAttachments`
  extension retains visible photo-draft intake, protected add/remove writes,
  optimistic transcript admission, mutation-marker preparation, and the sole
  `startDelivery` call. Its 192-line same-model
  `SessionListModelAttachmentSettlement` extension applies typed preparation,
  acceptance, failure, uncertainty, quarantine, and process-recovery outcomes
  without another task registry, mutation store, repository, or event stream.
  The attachment transport, persistence, and recovery runtimes remain the only
  lifecycle authorities, and `SessionListModelEvents` retains the sole private
  ordered application method. Architecture contracts replace loose historical
  bounds with 310/200-line source caps, a retained 500-line bridge aggregate,
  a 425-line core-model cap, and a 900-line model-plus-bridge aggregate while
  reducing the global architecture-contract source total. All 28 focused
  attachment-delivery, process-recovery, event-ownership, and architecture tests
  pass without failures or skips in
  `build/DerivedData-AttachmentSettlementFocused/Logs/Test/Test-Nile-2026.08.09_08-08-40-+0200.xcresult`.
  Exact staged tree `23b2e63428d6a2c7f92e604ff98e5a5b7a90c77e` passes all
  663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-AttachmentSettlementExact/Logs/Test/Test-Nile-2026.08.09_08-11-00-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split projection helpers out of the former 536-line ordered model event file.
  That intermediate revision left a 408-line `SessionListModelEvents` core with
  routing startup, the sole private `consume(_:)` application method, strictly
  ordered cross-feature dispatch, and terminal settlement. Its 133-line same-model
  `SessionListModelEventProjection` extension isolates goal synchronization,
  visible assistant deltas, hidden-session cache effects, completed attached-
  turn refresh, tool/todo projection, and blocking-prompt presentation without
  another stream consumer, event task, or router. `SessionEventRuntime` remained
  the only `HermesEventStreaming` owner. Architecture contracts then enforced
  425/140-line source caps, a 550-line event aggregate and 1,940-line
  model-orchestration aggregate, and reduced the global architecture-test source
  total while proving one private application boundary. Nineteen focused event,
  goal, blocking-prompt, model, and architecture tests pass without failures or
  skips in
  `build/DerivedData-EventProjectionSplit/Logs/Test/Test-Nile-2026.08.09_07-56-07-+0200.xcresult`.
  Exact staged tree `071376234a43ffa50389274f4a8ec0dba3f0e941` passes all
  663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-EventProjectionExact/Logs/Test/Test-Nile-2026.08.09_08-01-25-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split JSON-RPC request correlation out of the former 643-line WebSocket actor.
  The 506-line `TuiGatewayClient` core remains the sole actor and declaration
  owner for the current connection attempt, generation fencing, socket receive
  loop, ordered signals, and terminal effects. Its 140-line same-actor
  `TuiGatewayClientRequestLifecycle` extension isolates request admission,
  positive ID allocation, pending-call records, encoding/send, deadline and
  cancellation cleanup, and response settlement. Request send failures cross
  one narrow core operation so socket termination and failure emission remain
  with the existing transport authority; there is no second actor, socket,
  connection state, or signal path. Existing contracts, credential-redacting
  failure policy, and generic async primitives remain independently bounded.
  Architecture contracts enforce 525/155/75/175/70-line caps, retain the
  940-line aggregate and 5,400-line global ceiling, and prove unique connection-
  attempt and pending-call ownership. All 16 transport regressions plus the
  focused ownership and global-inventory guards pass without failures or skips
  in
  `build/DerivedData-GatewayRequestSplit/Logs/Test/Test-Nile-2026.08.09_07-43-53-+0200.xcresult`.
  Exact staged tree `ded48b1ec99bf175ceec11180e2f2313b39dda62` passes all
  663 unit/protocol tests with zero failures or skips in
  `build/DerivedData-GatewayRequestExact/Logs/Test/Test-Nile-2026.08.09_07-45-27-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split response-side Talk orchestration out of the former 596-line runtime.
  The 279-line `SessionTalkRuntime` core remains the sole observable and stored-
  state declaration owner and retains mode start/pause/resume/end, voice capture,
  recognition transitions, submission admission, and presentation projection.
  Its 324-line same-type `SessionTalkResponseLifecycle` extension isolates
  message/completion/error handling, Stop recovery, speech playback, and
  relisten scheduling without another runtime, microphone owner, submission
  authority, or event path. The existing submission runtime, stable contracts,
  and pure policy remain independently bounded. Architecture contracts enforce
  300/340-line core/lifecycle caps, the existing 950-line Talk aggregate, and
  one ordered model event-application boundary. Fifteen focused Talk, model,
  policy, and architecture tests pass without failures or skips. Exact staged
  tree `2755f709fb25c12f22025e5d1403e1878a47078d` passes all 663 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-TalkResponseExact/Logs/Test/Test-Nile-2026.08.09_07-35-01-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split the former 556-line delegated-agent coordinator into one mutable
  authority with two cohesive source owners. The bounded 372-line
  `DelegationCoordinator` core retains the sole turn-history declaration,
  live-owner binding, sparse-event grouping, parent settlement, interrupt state,
  and transcript projection. Its 185-line same-type
  `DelegationSnapshotLifecycle` extension isolates snapshot loading,
  reconciliation generations, persistence claiming, and settled-history
  trimming without another coordinator, store, or event path. The architecture
  contract now enforces the split, individual source caps, and the unchanged
  delegation aggregate cap. Nine focused coordinator/reducer/architecture tests
  pass with zero failures or skips. Exact staged tree
  `e2184669f1d7c57526a9cb351488c95718ab34fd` passes all 663 unit/protocol
  tests with zero failures or skips in
  `build/DerivedData-DelegationSnapshotExact/Logs/Test/Test-Nile-2026.08.09_07-24-15-+0200.xcresult`.
  Its optimized unsigned Release build passes with Swift and Clang warnings as
  errors, and the packaged Release plist contains no ATS override.
- Split security-sensitive blocking-prompt response transitions out of the
  former 535-line coordinator. The 258-line `BlockingPromptCoordinator` core
  remains the sole declaration owner of safe prompt records and retains event
  intake, live-to-stored binding, deduplication, status-poll watermarks, expiry,
  finalization, and transcript/attention projection. Its same-type 281-line
  `BlockingPromptSubmissionLifecycle` extension owns response admission,
  approval-FIFO actionability, secret-safe summaries, async settlement, and
  retry/unavailable/uncertain transitions without another record store or event
  path. Architecture contracts enforce 300/285-line caps and the existing
  850-line blocking-prompt aggregate. Sixteen focused coordinator, runtime,
  policy, and architecture tests pass without failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_07-14-23-+0200.xcresult`.
  Exact staged candidate `e1d553867748c1cf732584428e3c1af93becf403`
  passes all 663 unit/protocol tests without failures or skips in
  `build/DerivedData-BlockingSubmissionExact/Logs/Test/Test-Nile-2026.08.09_07-16-00-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the standing-goal mutation commands out of the former 588-line runtime.
  The 265-line `SessionGoalRuntime` remains the single observable authority and
  retains owner synchronization, progress/status reconciliation, presentation
  state, and the narrow status child. The bounded 326-line
  `SessionGoalMutations` extension owns start, pause, resume, continue, and
  clear commands plus the one mutation task and its generation/token fencing;
  it introduces no second observable runtime or event router. Goal architecture
  contracts now enforce 290/350-line caps, their existing 1,070-line goal
  aggregate, and one ordered event router. Eighteen focused architecture,
  policy, status, and model-goal tests pass without failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_07-02-12-+0200.xcresult`.
  Exact staged candidate `6f9f7b49c2e08c4c97b435e4326d4e7ee32073f3`
  passes all 663 unit/protocol tests without failures or skips in
  `build/DerivedData-GoalMutationsExact/Logs/Test/Test-Nile-2026.08.09_07-05-15-+0200.xcresult`
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split SwiftUI row-root dispatch out of the 649-line UIKit transcript viewport
  controller. The 603-line `TranscriptViewportController` retains the one
  diffable data source, hosted-row reuse, child-controller lifecycle, offset and
  anchor state, keyboard resizing, accessibility propagation, and layout
  settlement. The stateless 62-line `TranscriptViewportRowFactory` maps only an
  immutable `TranscriptViewportItem` plus `TranscriptViewportActions` into the
  exact launchpad, entry, or grouped-tool root with the existing Reduce Motion
  environment. It owns no controller, collection view, projection, cache, or
  scroll state, so the extraction does not create a second rendering path. The
  transcript architecture contract now enforces 625/80-line caps and unique
  row-factory ownership while retaining the 3,100-line surface aggregate and
  one authoritative viewport. Twenty-three focused architecture, projection,
  diffing, hosting-transfer, and scroll-policy tests pass without failures or
  skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.09_06-52-19-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-TranscriptRowFactoryExact/Logs/Test/Test-Nile-2026.08.09_06-53-57-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors under `build/DerivedData-TranscriptRowFactoryReleaseExact`; its
  packaged Release plist contains no ATS exception.
- Split the 443-line app-entry catch-all along routing, security, and permission
  presentation boundaries. The 169-line `NileApp` source remains the sole app,
  graph, root-routing, scene-lifecycle, fail-closed fallback-shield, and loading
  owner. The 210-line `BiometricAppLockOverlay` exclusively owns the scene-bound
  alert-plus-one modal accessibility window, key-window restoration, and lock
  surface, while the 73-line `NotificationEducationView` owns permission
  education without app-graph or biometric authority. The strengthened
  composition contract enforces unique surface declarations, critical lock-
  window security markers, 190/225/85 source caps, and a 480-line aggregate cap
  while reducing the global architecture-contract footprint. Eighty focused
  architecture, biometric fail-closed lifecycle, notification controller/policy,
  and app-graph fixture-plan tests pass without failures or skips in
  `build/DerivedData-AppSurfaceFocused/Logs/Test/Test-Nile-2026.08.09_08-49-50-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-AppSurfaceExact/Logs/Test/Test-Nile-2026.08.09_08-52-36-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors under `build/DerivedData-AppSurfaceReleaseExact`; its packaged Release
  plist contains no ATS exception.
- Split standing-goal details out of the modal creation source and consolidated
  duplicate status presentation. The 322-line `GoalView` remains the sole modal
  and creation-state owner; its 201-line same-sheet `GoalSheetDetails` extension
  owns active-goal objective, status, and action rendering without stored state,
  model ownership, or transport. The stateless 36-line
  `GoalPresentationPolicy` now owns the one phase-to-label/color mapping used by
  both details and the reduced 128-line persistent `GoalStatusCard`. The
  strengthened architecture contract enforces exclusive responsibility markers,
  policy use, 330/210/140/45 source caps, and the existing 700-line aggregate
  cap without growing the global architecture-contract budget. Two hundred ten
  focused architecture, goal policy/status/codec, and complete session-model
  tests pass without failures or skips in
  `build/DerivedData-GoalSurfaceFocused/Logs/Test/Test-Nile-2026.08.09_08-40-58-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-GoalSurfaceExact/Logs/Test/Test-Nile-2026.08.09_08-44-19-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors under `build/DerivedData-GoalSurfaceReleaseExact`; its packaged Release
  plist contains no ATS exception.
- Split recovered attachment coordination out of the protected-state core.
  The 302-line `SessionAttachmentPersistenceRuntime` remains the sole
  declaration authority for `AttachmentDraftStoring`, protected draft/marker
  mirrors, revisions and timestamps, restoration/quarantine flags, and exact-
  marker CAS primitives. Its 219-line same-runtime
  `SessionAttachmentPersistenceRecoveryLifecycle` extension owns ordinary-
  photo promotion, missing-owner migration, recovered-marker editing, and
  disconnect quarantine without introducing another object, state owner, task
  registry, repository, or event path; the 121-line store-free recovered-edit
  subordinate remains independently bounded. The architecture contract
  enforces unique state declarations, exclusive method placement, 320/230/140
  source caps, a 675-line aggregate cap, and event/repository exclusion.
  Seventy-five focused architecture, attachment-persistence, relaunch-recovery,
  and creation-draft tests pass without failures or skips in
  `build/DerivedData-AttachmentRecoveryLifecycleFocused/Logs/Test/Test-Nile-2026.08.09_08-29-37-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-AttachmentRecoveryLifecycleExact/Logs/Test/Test-Nile-2026.08.09_08-33-32-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors under `build/DerivedData-AttachmentRecoveryLifecycleReleaseExact`; its
  packaged Release plist contains no ATS exception.
- Split recovered attachment-edit task lifecycle out of the 592-line protected-
  persistence catch-all. The 512-line `SessionAttachmentPersistenceRuntime`
  remains the sole owner of `AttachmentDraftStoring`, protected draft/marker
  mirrors, revisions and timestamps, restoration/quarantine flags, exact-marker
  transitions, and multi-record migrations. The new 121-line
  `SessionAttachmentRecoveredEditRuntime` owns only replaceable per-owner task
  identity, cancellation, and the bounded three-attempt CAS retry loop through
  parent-supplied migration/load operations and marker source/sink callbacks; it
  cannot retain the store or protected projection. Existing retry, migration,
  transition, restoration, and quarantine tests exercise the unchanged public
  persistence boundary, while the architecture contract enforces the 525/140-
  line caps, sole store ownership, event/repository exclusion, and one ordered
  event router. The exact staged tree passes all 663 unit/protocol tests without
  failures or skips in
  `build/DerivedData-AttachmentEditExact/Logs/Test/Test-Nile-2026.08.09_06-46-30-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors under `build/DerivedData-AttachmentEditReleaseExact`; its packaged
  Release plist contains no ATS exception.
- Split periodic projection out of the 515-line displayed-session navigation
  bridge. The 412-line navigation source retains selection, fail-closed source
  lookup, live/history opening, fixture routing, pin actions, display-owner
  checks, selected-live directory overlay, and goal synchronization; the new
  107-line refresh source owns only five-second directory/status/history sink
  wiring and application, blocking-prompt status reconciliation, and completed-
  turn repair scheduling. The two shared gateway-owner checks are module-internal
  while every refresh callback remains private; neither source constructs a
  repository, consumes Hermes events, or introduces another event router.
  Restoring those owner checks' former `private` modifiers and reinserting the
  refresh body before selected-live overlay reconstructs the original byte-for-
  byte at SHA-256
  `3f67bf71e20b85d77326ed98be0da8fcf4a0848e64230497b6659558d3e01d3d`.
  The architecture contract enforces unique selection/refresh ownership,
  425/125-line caps, a 550-line aggregate, capability exclusions, and the single
  ordered event router. Four runtime lifecycle/order tests, three model
  selection/refresh fencing tests, that boundary, and the global architecture
  inventory pass without failures or skips in
  `build/DerivedData-SessionListModelRefreshFocused/Logs/Test/Test-Nile-2026.08.09_06-31-54-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-SessionListModelRefreshExact/Logs/Test/Test-Nile-2026.08.09_06-34-42-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the 482-line mixed voice-input source into a 43-line contracts boundary,
  a 307-line Hermes capture runtime, and a 134-line capture-mechanics boundary.
  Contracts own the event/protocol/null-input surface, PCM capability/factory,
  and permission error; the runtime retains configuration, event publication,
  capture-loop/VAD/WAV/transcription orchestration, and generation fencing; and
  the module-internal mechanics own failure projection, endpoint outcome, the
  serial async gate, and lock-backed synchronous stop/cancel/terminal state.
  Concatenating the contracts and runtime, then restoring the extracted
  mechanics' former `private` modifiers, reconstructs the original byte-for-byte
  at SHA-256
  `0335bf1fdc1f1e9b5b55122f44362249e33231f78448c235a252044471c2f410`.
  A source-ownership regression enforces unique declarations, 55/325/150-line
  caps, a 500-line aggregate, and no concrete runtime in the contracts boundary.
  That guard plus all ten existing PCM, VAD, WAV, microphone-close, capture,
  cancellation, and transcription regressions pass without failures or skips in
  `build/DerivedData-VoiceInputBoundariesFocused/Logs/Test/Test-Nile-2026.08.09_06-23-55-+0200.xcresult`.
  The exact staged tree passes all 663 unit/protocol tests without failures or
  skips in
  `build/DerivedData-VoiceInputBoundariesExact/Logs/Test/Test-Nile-2026.08.09_06-25-06-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split pure projection and the shared text bridge out of the 576-line
  `ModelPickerCatalogView`. The 486-line catalog retains query/focus state,
  provider expansion, model selection, pin mutation, physical hit targets, and
  accessibility; the 59-line Foundation policy owns stable model ordering plus
  capability/pricing labels; and the 34-line component source owns only
  `ModelPickerText` and its `NileComposeText` bridge. Reversing the three
  qualified policy calls, restoring the extracted helpers' former private
  names, reinserting them before the catalog's closing brace, and appending the
  text declaration reconstructs the original byte-for-byte at SHA-256
  `1aa1270e9e037eb89d8a11b17d6a4ad61bb0948cef173f0ffc9f09ada4f82d4e`.
  Three direct policy tests pin deduplicated provider order, sorted unavailable
  models, combined Fast/Reasoning/paid pricing, free labels, and blank metadata.
  The feature-surface contract enforces unique overlay/catalog/policy/text/
  confirmation ownership with 350/500/75/50/140-line caps, the existing
  1,050-line aggregate, and the 5,400-line global architecture ceiling. Those
  three policy tests plus the focused ownership and global-inventory guards pass
  without failures or skips in
  `build/DerivedData-ModelPickerCatalogBoundariesFocused/Logs/Test/Test-Nile-2026.08.09_06-11-27-+0200.xcresult`.
  The exact staged tree passes all 662 unit/protocol tests without failures or
  skips in
  `build/DerivedData-ModelPickerCatalogBoundariesExact/Logs/Test/Test-Nile-2026.08.09_06-14-14-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the immutable WebSocket connection/signal surface out of the 690-line
  `TuiGatewayClient`. The resulting 643-line actor retains every mutable
  generation, connection attempt, pending request, receive task, and terminal
  effect, while the 67-line contract source owns `GatewayFailure`,
  generation-tagged signals, the filtered async sequence, and
  `GatewayConnecting`. The sequence now accepts the actor's private `@Sendable`
  generation predicate rather than depending on the concrete actor. Reversing
  that adapter, restoring the former concrete-client fields and file-private
  predicate, removing the explicit cross-file initializer, and removing the
  repeated import reconstructs the original byte-for-byte at SHA-256
  `ee756c24aed5c53205bcef58a6b97c8cdc50edc3960691c724ff0f6566fa255e`.
  The gateway-client architecture contract enforces unique contract/actor
  ownership with 650/75/175/70-line caps, a 940-line aggregate, and the
  5,400-line global architecture ceiling. All 16 transport ordering, fencing,
  failure, cancellation, and malformed-frame regressions plus the focused
  ownership and global-inventory guards pass without failures or skips in
  `build/DerivedData-TuiGatewayClientContractsFocused/Logs/Test/Test-Nile-2026.08.09_06-02-47-+0200.xcresult`.
  The exact staged tree passes all 659 unit/protocol tests without failures or
  skips in
  `build/DerivedData-TuiGatewayClientContractsExact/Logs/Test/Test-Nile-2026.08.09_06-05-33-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the 409-line mixed app-graph fixture namespace into a 229-line
  build-filtered state/sample-data source and a 183-line fake-collaborator
  extension. Removing the collaborator source's repeated import and extension
  wrapper, reinserting its store/connection/cleanup declarations before the
  composer state and its voice declarations after the statistics builders, and
  restoring the former namespace comment reconstructs the original
  byte-for-byte at SHA-256
  `c4c8397db60967ac2b11cc65e437559a049996c740f5538a833f64ec728fc261`.
  The app-composition architecture contract now enforces unique state versus
  collaborator ownership, 250/200-line caps, the existing 1,450-line app-graph
  aggregate, and the 5,400-line global architecture ceiling. All five fixture
  selection/production-absence regressions plus the focused composition and
  global-inventory guards pass without failures or skips in
  `build/DerivedData-AppGraphFixtureCollaboratorsFocused/Logs/Test/Test-Nile-2026.08.09_05-54-11-+0200.xcresult`.
  The exact staged tree passes all 659 unit/protocol tests without failures or
  skips in
  `build/DerivedData-AppGraphFixtureCollaboratorsExact/Logs/Test/Test-Nile-2026.08.09_05-57-17-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the 504-line mixed transcript entry source into a 337-line central
  dispatcher and message/media renderer, an 85-line expandable command-output
  source, and an 84-line system/standing-goal notice source. The dispatcher
  still selects exactly one existing row family and remains the only entry point
  used by the UIKit viewport. Re-inserting the command declarations between the
  dispatcher and message declarations, appending the notice declarations, and
  restoring only the three moved rows' former `private` modifiers reconstructs
  the source byte-for-byte at SHA-256
  `679e3fac03468b14bb5de8ca5a76ce5522040028e0dfdf5bdbbf7b8a150f4b2b`.
  The transcript-surface architecture contract enforces unique command,
  message/media, and notice ownership with 110/375/110-line caps while retaining
  the 3,100-line surface aggregate and 5,400-line global architecture ceilings.
  All 14 transcript projection/viewport regressions plus the focused surface
  and global-inventory guards pass without failures or skips in
  `build/DerivedData-TranscriptMessageRowSplitFocused/Logs/Test/Test-Nile-2026.08.09_05-42-28-+0200.xcresult`.
  The exact staged tree passes all 659 unit/protocol tests without failures or
  skips in
  `build/DerivedData-TranscriptMessageRowSplitExact/Logs/Test/Test-Nile-2026.08.09_05-47-35-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the 558-line mixed delegation wire codec into a 43-line status decoder,
  285-line snapshot decoder/encoder, and 232-line shared validation/encoding
  primitive source. Status parsing no longer owns snapshot persistence shapes,
  snapshot handling retains all terminal/output-tail and save validation, and
  the primitive boundary depends only on JSON/error mechanics rather than
  delegation domain models. Concatenating the three sources, removing repeated
  imports, and restoring only the primitives' former file-private markers
  reconstructs the source byte-for-byte at SHA-256
  `f8d77c0d5c178a2357e4bc92196f3b59156f103f37a81d0638b19799e5374c5b`.
  The gateway-service architecture contract now enforces unique entry-point and
  primitive ownership, responsibility exclusions, 60/310/250-line caps, and a
  590-line aggregate cap. The four exact delegation RPC/order/malformed-payload
  regressions and the focused ownership guard pass in
  `build/DerivedData-DelegationCodecSplitFocused/Logs/Test/Test-Nile-2026.08.09_05-31-31-+0200.xcresult`;
  the final ownership and global-inventory guards pass in
  `build/DerivedData-DelegationCodecSplitFocused/Logs/Test/Test-Nile-2026.08.09_05-35-14-+0200.xcresult`.
  The exact staged tree passes all 659 unit/protocol tests without failures or
  skips in
  `build/DerivedData-DelegationCodecSplitExact/Logs/Test/Test-Nile-2026.08.09_05-36-32-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the 390-line mixed notification infrastructure source into four
  capability-owned Core boundaries: 65-line `TurnNotificationRouting.swift`
  owns minimal route validation and bounded buffering; the 156-line
  `TurnNotificationController.swift` retains finite background execution,
  expiration/requeue coordination, and generic completion scheduling; the
  127-line `NotificationEducation.swift` owns permission translation,
  one-time persistence, and presentation state; and the 47-line
  `NileAppDelegate.swift` owns only notification-center delegate installation
  and response forwarding. Removing repeated imports and restoring the three
  original blank separators reconstructs the source byte-for-byte at SHA-256
  `e3a22e8f47b860817d725a40e6876b63595696f5075960f6910006fc9e811d9b`.
  The app-composition architecture contract enforces unique declaration
  ownership, 80/180/150/70-line caps, and a 430-line aggregate cap. The 8
  focused notification regressions plus that architecture guard pass in
  `build/DerivedData-NotificationBoundariesFocused/Logs/Test/Test-Nile-2026.08.09_05-19-32-+0200.xcresult`.
  The exact staged tree passes all 659 unit/protocol tests without failures or
  skips in
  `build/DerivedData-NotificationBoundariesExact/Logs/Test/Test-Nile-2026.08.09_05-22-07-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release plist contains no ATS exception.
- Split the dashboard capability seam and its fail-closed defaults out of the
  424-line `GatewayDashboardClient`. The resulting 88-line
  `GatewayDashboardContracts.swift` owns only the independently injectable read,
  query, mutation, and download contract; the 337-line client retains bounded
  JSON transport, structured error decoding, retry classification, and safe
  sign-in URLs; and the existing 365-line download extension retains all
  credential, redirect, downgrade, response-size, and filename policy.
  Restoring the extracted declarations ahead of the client reconstructs the
  original source byte-for-byte at SHA-256
  `6624f7b3d80a488d611e728cfc3a164486d5153a0c5b6b533a0737b9e0501686`.
  The gateway-client architecture contract pins each responsibility to its
  owner and caps the three sources at 100/350/380 lines and 825 lines in
  aggregate. The exact staged tree passes all 659 unit/protocol tests without
  failures or skips in
  `build/DerivedData-GatewayDashboardContractsExact/Logs/Test/Test-Nile-2026.08.09_05-12-22-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Split the 507-line mixed gateway-profile persistence source into independently
  bounded contracts, transaction, codec, and secure-adapter authorities. The
  current 207-line `GatewayProfileStore.swift` transaction actor delegates
  versioned metadata encoding and validation to the independent 146-line
  `GatewayProfileStoreCodec.swift`; the 63-line contracts and 105-line
  protected-file/Keychain adapter remain unchanged. Reassembling the earlier
  three extracted chunks reconstructed that prior source byte-for-byte at SHA-256
  `e29129ae690eed2e8124e95e9b75f707eaccf55b303b44e37a3bba9730772fc6`.
  The persistence architecture contract keeps Security and protected-file
  mechanics out of the capability, transaction, and codec sources, pins each
  actor, schema, validator, and adapter to its owner, and now caps the four
  sources at 530 lines in aggregate. The earlier exact staged tree passed all
  659 unit/protocol tests without
  failures or skips in
  `build/DerivedData-GatewayProfileSplitExact/Logs/Test/Test-Nile-2026.08.09_05-03-34-+0200.xcresult`,
  including the real Simulator Keychain integration, plus strict unsigned
  Release compilation with Swift and Clang warnings as errors; its packaged
  Release `Info.plist` contains no ATS exception.
- Split the 678-line mixed standing-goal presentation into a 535-line
  `GoalView.swift` modal creation/details surface and a 144-line
  `GoalStatusCard.swift` persistent status/action surface with the shared target
  glyph. Reassembling the extracted chunks reconstructs the original source
  byte-for-byte at SHA-256
  `75fcfa1bd686a48a89177a2edaab0ae4a14f77292c71a415024a82fad6ee7fc4`.
  The feature-surface architecture contract enforces declaration ownership,
  550/175-line caps, and a 700-line aggregate cap while the global inventory
  remains below 5,400 logical lines. The exact staged tree passes all 659
  unit/protocol tests without failures or skips in
  `build/DerivedData-GoalSurfaceSplitExact/Logs/Test/Test-Nile-2026.08.09_04-54-38-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Split the 561-line mixed attachment-draft persistence source into a 180-line
  `AttachmentDraftContracts.swift` value/protocol/error boundary and an initial
  382-line `AttachmentDraftStore.swift` protected-file actor with its private
  envelope.
  Restoring the original blank separator and concatenating the contract source
  with the store declarations after removing its repeated import reconstructs
  the original byte-for-byte at SHA-256
  `5df9ea9eddbbdc3e4c2ce26f9448845bf210560f092d8327a17611cc6f5efa7c`.
  The initial persistence architecture contract excluded protected-file
  mechanics from the capability source, pinned the actor/envelope to the
  implementation, and capped the sources at 200/400 lines and 575 lines in
  aggregate. The exact staged
  tree passes all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-AttachmentDraftContractsSplitExact/Logs/Test/Test-Nile-2026.08.09_04-42-33-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 580-line mixed `HermesVoiceSettingsView.swift` with a 59-line
  settings entry, a 431-line modal sheet/button source, and a 92-line
  Foundation-only provider-label/preset policy. Removing repeated imports and
  restoring the two original blank separators reconstructs the source
  byte-for-byte at SHA-256
  `b6eb8c28a3ffaa6f20934ba119b79f48fd9b8302ef9b9f96b36db36cd43676a7`.
  The gateway-settings architecture contract now pins all six orchestration,
  voice, and confirmation sources to unique owners with individual ceilings and
  a 1,300-line aggregate cap; the existing catalog regression continues to pin
  Android provider labels and preset order. The exact staged tree passes all 658
  unit/protocol tests without failures or skips in
  `build/DerivedData-HermesVoiceSurfaceSplitExact/Logs/Test/Test-Nile-2026.08.09_04-31-49-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Split the secure modal surfaces out of the 572-line mixed
  `BlockingPromptView.swift`. The 450-line row source now owns fail-closed prompt
  presentation and its private action/status controls, while the 123-line
  `BlockingPromptOverlays.swift` owns secure-value entry and explicit permanent
  approval confirmation without broadening either declaration's visibility.
  Rejoining the extracted declarations after the original blank separator
  reconstructs the source byte-for-byte at SHA-256
  `fda0dc06f91335ccf13536a22bbb8ce47c1cea6d7713c974b1969df3b877a538`.
  The transcript-surface architecture contract now pins both prompt owners,
  requires privacy-sensitive marking on the overlay source, and caps all twelve
  presentation sources at 3,100 lines in aggregate. The exact staged tree passes
  all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-BlockingPromptOverlaySplitExact/Logs/Test/Test-Nile-2026.08.09_04-21-58-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Split the empty-session launchpad out of the 642-line mixed
  `TranscriptMessageRows.swift` source. The 139-line `SessionLaunchpad.swift`
  now owns safe catalog discovery, fallback quick starts, and empty-state
  selection while the 504-line message-row source owns only transcript entry
  dispatch and message-family rendering. Concatenating the launchpad declarations
  between the retained imports and message rows reconstructs the original source
  byte-for-byte at SHA-256
  `dcdff61e4533665221f00b8eca0e22d6415c891968c7619040a357484bca04a2`.
  The transcript-surface architecture contract pins both responsibilities to
  one bounded source and retains its 2,500-line aggregate cap. The exact staged
  tree passes all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-SessionLaunchpadSplitExact/Logs/Test/Test-Nile-2026.08.09_04-13-14-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 607-line mixed `GatewayStatsSheet.swift` with a 149-line sheet
  lifecycle shell, 74-line content router, 113-line summary-card source,
  113-line reusable row/section source, 125-line heatmap renderer, and 38-line
  shared formatter source. Restoring the extracted declarations and formatters'
  former `private` modifiers and removing repeated imports reconstructs the
  original source byte-for-byte at SHA-256
  `f39ea69fd0199a9a26abf8eee26d90f07da5be1d4cc01d5bde842597c49cfe1f`.
  The usage architecture contract now pins every statistics component to one
  bounded owner, retains a 650-line presentation aggregate, and keeps UTC
  momentum/heatmap projection in the existing Foundation-only source. The exact
  staged tree passes all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-GatewayStatsViewSplitExact/Logs/Test/Test-Nile-2026.08.09_04-02-03-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 638-line mixed `DelegationView.swift` with a 164-line group
  orchestration source, a 109-line agent-summary row, a 204-line expanded
  output/control detail, and a 164-line shared status/duration/text source.
  Restoring the extracted declarations and helpers' former `private` modifiers
  and removing repeated imports reconstructs the original source byte-for-byte
  at SHA-256
  `86d833fd6a787ac34305839d6267fa7c85ae83a105b8996e33a54e3777f30390`.
  The delegation architecture contract now pins every group, row, detail, and
  support declaration to one bounded owner and retains a 675-line aggregate cap.
  The exact staged tree passes all 658 unit/protocol tests without failures or
  skips in
  `build/DerivedData-DelegationViewSplitExact/Logs/Test/Test-Nile-2026.08.09_03-51-44-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Split the 649-line mixed `SettingsView.swift` into a 410-line settings
  orchestration surface, a 98-line staged gateway-switch confirmation, and a
  143-line protected gateway-removal confirmation. Restoring the two dialogs'
  former `private` modifiers, removing their repeated imports, and placing them
  before the preview reconstructs the original source byte-for-byte at SHA-256
  `ea3713e6fadb96fbf9aa9a764a6c37de533cf4b95afcb32cd3ecb0c734c19b8f`.
  The existing gateway-setup architecture contract now pins each declaration
  to one bounded source and retains a 675-line aggregate cap. The exact staged
  tree passes all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-SettingsViewSplitExact/Logs/Test/Test-Nile-2026.08.09_03-40-50-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 697-line mixed `TranscriptToolRows.swift` with a 404-line
  grouped/default-tool renderer and sole `ToolRow` dispatcher, 110-line diff
  renderer, 123-line todo/active-plan renderer, and 66-line shared row-primitives
  source. Restoring five cross-file declarations' former `private` modifiers
  and removing repeated imports reconstructs the original source byte-for-byte
  at SHA-256
  `ff8f22211e7526e0b7634faa9128eb53c88e77ea44d298e47f845ec0450a3ef0`.
  The transcript-surface architecture contract now pins every grouped/default,
  diff, todo, plan, and shared declaration to one owner, enforces individual
  caps, and retains the 2,500-line aggregate across all nine transcript sources.
  All 14 transcript regressions plus the focused and global architecture
  inventories pass in `build/DerivedData-TranscriptToolRowsSplit`. The staged
  implementation passes all 658 unit/protocol tests without failures or skips
  in `build/DerivedData-TranscriptToolRowsSplitExact/Logs/Test/Test-Nile-2026.08.09_03-30-24-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 810-line mixed `TranscriptViewport.swift` with a 98-line SwiftUI
  bridge/value source, a 649-line UIKit diffing/scroll/anchoring controller, and
  a 68-line reusable hosting-cell source. Removing only the two repeated import
  headers reconstructs the original source byte-for-byte at SHA-256
  `a3c262e9d5aac0b41c11013308ae998265c36726f61f836e853c0aaf017855e0`;
  no declaration visibility changed. The transcript-surface architecture
  contract now pins bridge, controller, hosting, message, and tool declarations
  to one owner, rejects cross-boundary declaration ownership, enforces individual
  caps, and keeps the six sources below 2,500 lines. All 14 transcript projection,
  large-diff, and hosting-transfer regressions plus the focused and global
  architecture inventories pass in `build/DerivedData-TranscriptViewportSplit`.
  The staged implementation passes all 658 unit/protocol tests without failures
  or skips in
  `build/DerivedData-TranscriptViewportSplitExact/Logs/Test/Test-Nile-2026.08.09_03-21-02-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 865-line `NileMarkdown.swift` catch-all with a 191-line public
  view/block/code renderer, 319-line immutable block parser and settled-cache
  owner, 83-line inline/list styling source, and 276-line adaptive table source.
  Restoring the four cross-file declarations' former `private` modifiers
  reconstructs the original source byte-for-byte at SHA-256
  `449e1042f3ddb70ca66fcc9b2941b69b1c5cbeab6c3739b957ca33dc912fe3b4`.
  The design architecture contract now pins all Markdown declarations to one
  responsibility owner, rejects parser/table ownership in the public renderer,
  enforces individual caps, and keeps the combined design/Markdown boundary
  below 1,800 lines. All 14 Markdown regressions and the focused architecture
  boundary pass in `build/DerivedData-NileMarkdownSplit`. The staged
  implementation passes all 658 unit/protocol tests without failures or skips
  in `build/DerivedData-NileMarkdownSplitExact/Logs/Test/Test-Nile-2026.08.09_03-05-25-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 1,463-line `GatewaySetupModelTests.swift` catch-all with a
  6-line XCTest identity, five behavior-owned sources for connection/form,
  staged gateway switching, reconnect/authentication, protected-data cleanup,
  and Hermes voice, plus four bounded helper/fake sources. All 28 existing tests
  retain their XCTest identity and unique names; the former source reconstructs
  byte-for-byte after reversing only cross-file helper/fake visibility. Behavior
  sources range from 110 to 327 lines and support sources from 48 to 166 lines.
  The existing setup-model architecture contract now also pins representative
  behavior ownership, all 13 helper/fake declarations, exact discovery counts,
  individual caps, and a 1,550-line aggregate cap. All 28 focused tests plus the
  setup-model and global architecture inventories pass in
  `build/DerivedData-GatewaySetupModelTestSplit`. The exact staged tree passes
  all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-GatewaySetupModelTestSplitExact/Logs/Test/Test-Nile-2026.08.09_02-52-15-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 2,088-line `TuiGatewayRepositoryTests.swift` catch-all with a
  4-line XCTest identity, seven capability-owned behavior sources for
  session/history, turn/blocking prompts, attachments/commands, models,
  speech/voice, goals/usage, and ordered events/delegation, plus one support
  source for recording transports. All 33 existing contract tests retain their
  original XCTest identity and unique names, and the former source reconstructs
  byte-for-byte after reversing only the support declarations' cross-file
  visibility; behavior sources range from 199 to 360 lines and the support
  source is 275 lines. A new architecture regression
  pins representative ownership, exact per-file discovery counts, all ten fake
  declarations, individual caps, and a 2,150-line aggregate cap. The focused
  33-test suite and both the new boundary and global architecture inventory pass
  in `build/DerivedData-GatewayRepositoryTestSplit`. The exact staged tree
  passes all 658 unit/protocol tests without failures or skips in
  `build/DerivedData-GatewayRepositoryTestSplitExact/Logs/Test/Test-Nile-2026.08.09_02-38-41-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the 1,226-line mixed `SessionListModelTestDoubles.swift` catch-all
  with five capability-owned sources for audio input/output, pin stores,
  protected text/photo stores, attachment caches, and the integrated repository
  double. The sources range from 53 to 734 lines and reconstruct the former file
  byte-for-byte after removing repeated import headers. The model-suite
  architecture contract now rejects the legacy catch-all, requires unique
  ownership of all nine declarations, enforces per-source caps and a 1,275-line
  aggregate cap, and keeps infrastructure declarations out of behavior tests.
  All 134 model tests plus that guard pass 135/135 in
  `build/DerivedData-SessionModelTestDoubleSplit/Logs/Test/Test-Nile-2026.08.09_02-15-53-+0200.xcresult`.
  The exact staged tree also passes all 657 unit/protocol tests with zero
  failures or skips in
  `build/DerivedData-SessionModelTestDoubleSplitExact/Logs/Test/Test-Nile-2026.08.09_02-21-54-+0200.xcresult`,
  plus strict unsigned Release compilation with Swift and Clang warnings as
  errors; its packaged Release `Info.plist` contains no ATS exception.
- Replaced the remaining 3,470-line `SessionListModelTests.swift` core with a
  4-line XCTest identity and eight behavior-owned extensions for creation,
  management/pins/goals, navigation/ownership, ordered events/timelines,
  turns/drafts, blocking prompts, voice/usage/delegation, and background
  lifecycle. Together with the existing attachment and command/model sources,
  all eleven behavior files are between 336 and 847 lines. The 93 moved tests
  reconstruct byte-for-byte in their original order, while all 134 model tests
  retain one discovery identity. The strengthened architecture guard enforces
  representative ownership, unique test names, per-source caps, a 5,650-line
  aggregate cap, and separate helper/doubles boundaries. All 134 model tests
  plus that guard pass 135/135 in
  `build/DerivedData-SessionModelTestSplit/Logs/Test/Test-Nile-2026.08.09_02-04-14-+0200.xcresult`.
  The exact staged tree passes all 657 unit/protocol tests with zero failures or
  skips in
  `build/DerivedData-SessionModelTestSplitExact/Logs/Test/Test-Nile-2026.08.09_02-08-16-+0200.xcresult`,
  and its unsigned Release device build passes with Swift and GCC warnings
  treated as errors; the packaged Release `Info.plist` has no
  `NSAppTransportSecurity` key.
- Split the 5,161-line `ArchitectureBoundaryTests.swift` monolith into a
  now-153-line shared coordinator and eight responsibility-owned extensions for
  app composition, session bridges, feature surfaces, capability runtimes,
  session runtimes, gateway clients, gateway services, and protected
  persistence. The
  extension sources range from 133 to 989 lines, retain the same XCTest class,
  and reconstruct all 57 pre-split contract methods byte-for-byte in their
  original order. The inventory now requires unique ownership for those
  contracts plus the gateway repository-test boundary, representative feature
  placement, per-source caps below 1,000 lines, and a 5,400-line aggregate cap.
  The original 58 focused architecture contracts pass in
  `build/DerivedData-ArchitectureTestSplit/Logs/Test/Test-Nile-2026.08.09_01-53-05-+0200.xcresult`;
  the exact-staged full 657-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-ArchitectureTestSplitExact/Logs/Test/Test-Nile-2026.08.09_01-56-47-+0200.xcresult`.
  A strict warnings-as-errors unsigned Release build passes in
  `build/DerivedData-ArchitectureTestSplitExact-Release`, and its packaged plist
  contains no `NSAppTransportSecurity` override.
- Restored one acceptance source of truth across the durable repository records:
  `AGENTS.md` and `IOS_PORT_GOAL.md` govern functional, security, and app-owned
  visual parity against the pinned Android oracle. The former native-design
  direction remains as historical divergence evidence rather than a waiver;
  strict red comparisons remain incomplete, and the currently divergent river
  app icon is again classified Partial. Moved the build-configuration contract
  out of endpoint behavior coverage into a dedicated 176-line
  `RepositorySourceOfTruthTests` boundary. Its cross-document regression locks
  all three oracle pins, affirmative authority statements, and the absence of
  conflicting override claims. Eight focused source-of-truth and endpoint tests
  pass in
  `build/DerivedData-SourceOfTruth/Logs/Test/Test-Nile-2026.08.09_01-41-34-+0200.xcresult`;
  the exact-staged full 656-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SourceOfTruthExact/Logs/Test/Test-Nile-2026.08.09_01-45-06-+0200.xcresult`.
  A strict warnings-as-errors unsigned Release build passes in
  `build/DerivedData-SourceOfTruthExact-Release`, and its packaged plist contains
  no `NSAppTransportSecurity` override.
- Replaced the 1,062-line `NileDesign.swift` catch-all with bounded
  132-line token/motion/tactile, 307-line typography/Dynamic Type, 209-line
  reusable-modifier, 96-line Compose-text bridge, and 128-line Android text
  measurement sources. The live declaration inventory is unchanged; an
  unreferenced 170-line private renderer label and its private 23-line color
  helper were removed, reducing the aggregate to 872 lines, and only the live
  measurement boundary imports the pinned Android renderer. An architecture
  regression enforces declaration ownership, individual and aggregate source
  caps, catch-all removal, renderer-import isolation, and dead-path exclusion.
  Twelve focused architecture/typography/renderer/tactile tests pass in
  `build/DerivedData-DesignSystemSplit/Logs/Test/Test-Nile-2026.08.09_01-29-53-+0200.xcresult`;
  the exact-staged full 655-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-DesignSystemExact/Logs/Test/Test-Nile-2026.08.09_01-33-09-+0200.xcresult`.
  A strict warnings-as-errors unsigned Release build passes in
  `build/DerivedData-DesignSystemExact-Release`, and its packaged plist
  contains no `NSAppTransportSecurity` override.
- Replaced the 722-line `Models.swift` and 460-line `HermesRepository.swift`
  catch-alls with nine feature-owned gateway, session, event, model, usage,
  media, delegation, command, and goal contract sources. Immutable values,
  narrow capability protocols, convenience overloads, and fail-closed defaults
  now share their feature boundary; every source is at most 196 lines and the
  aggregate drops from 1,243 to 1,237 lines. A declaration-inventory comparison
  against the previous three domain sources is exact, expanded default-contract
  tests cover every optional capability family, and an architecture regression
  enforces unique ownership, individual/aggregate size caps, and removal of both
  grab-bag files. The exact-staged full 654-test unit/protocol suite passes
  without failures or skips in
  `build/DerivedData-DomainContractsExact/Logs/Test/Test-Nile-2026.08.09_01-22-45-+0200.xcresult`.
- Split the 700-line model-control runtime into a bounded 504-line
  model/reasoning mutation and presentation owner, 72-line read-only
  `ModelOptionsRuntime`, 148-line protected `ModelPinRuntime`, 240-line pure
  admission/resolution/failure policy, and 43-line stable contract surface.
  `HermesModelServing` now composes explicit catalog-read and mutation
  capabilities, while `SessionListModel` remains the sole ordered Hermes event
  boundary. Architecture regressions enforce responsibility, capability, and
  source-size bounds. The 25 focused policy/runtime/integration tests pass in
  `build/DerivedData-ModelControlSplit/Logs/Test/Test-Nile-2026.08.09_01-06-46-+0200.xcresult`;
  the exact-staged full 653-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-ModelControlExact/Logs/Test/Test-Nile-2026.08.09_01-09-17-+0200.xcresult`.
- Split the 773-line standing-goal runtime into a bounded 588-line mutation and
  presentation owner, 108-line read-only `GoalStatusRuntime`, 265-line pure
  admission/event/status policy, and 42-line stable contract surface. Goal
  mutations retain `HermesGoalServing`, status work receives only the new
  `HermesGoalStatusServing` capability, independent generations fence stale
  lookups, and the single ordered Hermes event router remains unchanged. Added
  direct policy/status concurrency coverage plus an architectural boundary that
  prevents the responsibilities from collapsing back together.
- Split Talk prompt transport and pure submission decisions out of the 787-line
  `SessionTalkRuntime`. The bounded 596-line parent remains the sole owner of
  voice capture, speech playback, Stop recovery, relisten scheduling, and the
  Talk state machine; the 198-line `TalkSubmissionRuntime` exclusively owns the
  narrow `HermesTalkServing` capability, submission task/generation, and
  acknowledgement/early-terminal correlation. Stable callbacks occupy 38 lines
  and the 85-line pure policy owns admission normalization, queued/steered/early
  settlement, and definite-versus-uncertain failure classification. Architecture
  checks cap each source and preserve one ordered model event-application
  boundary. Fifteen focused Talk/model/policy/architecture tests passed in
  `build/DerivedData-TalkSubmission/Logs/Test/Test-Nile-2026.08.09_00-37-06-+0200.xcresult`;
  the exact staged tree passed all 633 unit/protocol tests in
  `build/DerivedData-TalkSubmissionExact/Logs/Test/Test-Nile-2026.08.09_00-39-27-+0200.xcresult`.
  A strict unsigned Release build with Swift and Clang warnings as errors passed
  in `build/DerivedData-TalkSubmissionExact-Release`, and its generated Release
  plist contains no `NSAppTransportSecurity` override.
- Split Hermes-event interpretation, stable contracts, and pure presentation /
  submission policy out of the 788-line `BlockingPromptCoordinator`. The
  bounded 535-line coordinator remains the sole owner of prompt records,
  live-to-stored binding, request deduplication, approval FIFO state, poll
  generations, expiry application, and submission settlement. The stateless
  147-line `BlockingPromptEventFactory` owns exact actionable-card construction
  and visible fail-closed malformed cards; the 108-line
  `BlockingPromptPolicy` owns timeouts, secret-safe response summaries,
  actionability inputs, uncertain-failure classification, status normalization,
  and transcript-card replacement; stable contracts occupy 37 lines.
  Architecture checks cap those sources at 550/160/120/50 lines and 850 lines
  in aggregate. Eleven focused policy/coordinator/architecture tests passed in
  `build/DerivedData-BlockingPromptPolicy/Logs/Test/Test-Nile-2026.08.09_00-23-52-+0200.xcresult`;
  the exact staged tree passed all 630 unit/protocol tests in
  `build/DerivedData-BlockingPromptExact/Logs/Test/Test-Nile-2026.08.09_00-26-22-+0200.xcresult`.
  A strict unsigned Release build with Swift and Clang warnings as errors passed
  in `build/DerivedData-BlockingPromptExact-Release`, and its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split stable presentation contracts and pure sparse-event reduction out of
  the 883-line `DelegationCoordinator`. The bounded 556-line coordinator remains
  the sole owner of live-session binding, multi-agent turn history,
  interrupt/reconciliation generations, parent settlement, bounded snapshot
  persistence, and transcript anchors. The 85-line `DelegationPresentation`
  source owns UI/owner/request types, while the stateless 272-line
  `DelegationAgentReducer` owns identity normalization, overflow-safe and
  monotonic tool counts, terminal/interrupt fencing, sparse field merges, and
  UI/snapshot conversion without lifecycle authority. Architecture contracts
  cap the sources at 575/290/100 lines and 940 lines in aggregate. Direct
  reducer, coordinator, runtime, domain, and architecture coverage passed 66/66
  in
  `build/DerivedData-DelegationReducer/Logs/Test/Test-Nile-2026.08.09_00-14-26-+0200.xcresult`;
  the exact staged tree passed all 625 unit/protocol tests in
  `build/DerivedData-DelegationReducerExact/Logs/Test/Test-Nile-2026.08.09_00-16-25-+0200.xcresult`.
  A strict unsigned Release build with warnings as errors passed in
  `build/DerivedData-DelegationReducerExact-Release`, and its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split deterministic launch-fixture selection, fixture state installation,
  streaming-stress orchestration, and notification decision policy out of the
  770-line `NileAppGraph`. The 218-line production graph now retains one shared
  repository/WebSocket composition, lifecycle callback installation, and route
  execution without raw fixture arguments or sample payloads. The current
  267-line `NileAppGraphFixturePlan` is the single filtered argument-precedence
  table, while its 156-line assembly extension constructs only selected fake
  collaborators; the 236-line `NileAppGraphFixtureInstaller` applies
  deterministic model state; 229-line state and 183-line collaborator fixture
  sources retain sample data and fakes; and the stateless 84-line
  `TurnNotificationRoutePolicy` owns fail-closed route decisions. Architecture
  contracts cap the seven sources at 250/250/200/285/170/260/100 lines and
  1,450 lines in aggregate, while direct tests cover production absence,
  selection precedence, isolated switch/removal profiles, Hermes voice, and
  performance-stress selection. The original exact staged tree passed all 622
  unit/protocol tests in
  `build/DerivedData-AppGraphExact/Logs/Test/Test-Nile-2026.08.09_00-04-03-+0200.xcresult`;
  six gateway-switch, streaming, usage, statistics, Talk, and notification
  fixture UI contracts passed in
  `build/DerivedData-AppGraphExact/Logs/Test/Test-Nile-2026.08.09_00-05-12-+0200.xcresult`.
  A strict unsigned Release build with warnings as errors passed in
  `build/DerivedData-AppGraphExact-Release`, and its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split session/history/status and prompt/turn transport out of the intermediate
  348-line `TuiGatewayRepository`. The 193-line repository composition root now
  owns only connection and the sole ordered event stream, while the 130-line
  `GatewaySessionService`, 64-line `GatewayTurnService`, and transport-free
  31-line `GatewayTalkService` own their narrow capabilities. Talk composes
  prompt submission with `HermesLiveRuntimeStatusServing`, and session history
  shares the one repository-created `GatewayConnectionState` used by the other
  dashboard-backed services. Architecture contracts prevent transport and event
  projection from drifting across these boundaries and cap the four sources at
  210/145/75/40 lines and 460 lines in aggregate. The exact staged tree passed
  all 617 unit/protocol tests in
  `build/DerivedData-GatewaySessionTurnExact/Logs/Test/Test-Nile-2026.08.08_23-49-05-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-GatewaySessionTurnExact-Release`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- An earlier slice split attachment transport and speech/global-voice transport
  out of the 520-line `TuiGatewayRepository`. The resulting 348-line
  intermediate repository owned connection, ordered events, sessions, and turn
  transport; its two public
  initializers delegate to one designated composition path that creates the
  shared `GatewayConnectionState` exactly once. The 103-line
  `GatewayAttachmentService` contributes reading and mutation capabilities
  directly, while the 124-line `GatewaySpeechService` contributes transcription
  and synthesis to the session bundle and voice configuration to the app graph.
  That slice's architecture contracts prevented the repository from regaining
  those seven methods and capped the three sources at 370/115/140 lines and 610
  lines in aggregate. Its exact staged tree passed all 615 unit/protocol tests in
  `build/DerivedData-GatewayCapabilityExact/Logs/Test/Test-Nile-2026.08.08_23-39-15-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-GatewayCapabilityExact-Release`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split the 552-line gateway event projector behind one bounded 268-line
  repository-facing dispatcher. A stateless 166-line blocking-prompt projector
  retains strict fail-closed parsing and visible malformed-request events, while
  a stateless 149-line subagent projector owns typed payload validation, ANSI
  cleanup, terminal-status mapping, and bounded numeric fields. Tool, session,
  goal, status, and compaction projection remain in the sole ordered dispatcher;
  architecture contracts cap the three sources at 285/180/165 lines and 620
  lines in aggregate. The exact staged tree passed all 614 unit/protocol tests
  in
  `build/DerivedData-GatewayEventExact/Logs/Test/Test-Nile-2026.08.08_23-28-38-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-GatewayEventExact-Release`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split gated authentication into explicit lifecycle, I/O, and policy
  boundaries. The now 299-line `GatewayAuthenticationService` owns fresh ticket
  minting, managed REST requests, expiry/logout effects, and capability/event
  wiring; its independent 91-line rotation gate owns cancellation-safe
  serialized admission and release. The 80-line `WebKitGatewayCookieStore` owns
  only persistent `WKHTTPCookieStore` I/O; and the stateless 190-line
  `GatewayCookiePolicy` consolidates URL containment, scope collisions, cookie
  variant/domain/path/expiry/transport matching, and selective cleanup. Direct
  policy tests cover origin/path confusion, root and prefix
  `__Host-`/`__Secure-` rules, expired/foreign cookies, and host-wide versus
  profile cleanup. Architecture contracts now cap the sources at
  315/105/95/205 lines and 680 lines in aggregate. The earlier exact staged tree
  passed all 613
  unit/protocol tests in
  `build/DerivedData-GatewayCookieExact/Logs/Test/Test-Nile-2026.08.08_23-19-02-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-Release-GatewayCookieExact`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split credential-redacting WebSocket failure classification and generic
  deadline/one-shot mechanics out of the 893-line `TuiGatewayClient`. The
  bounded 690-line actor still privately owns every mutable connection attempt,
  generation fence, pending call, receive task, and terminal effect; the
  stateless 163-line `GatewayConnectionFailurePolicy` preserves explicit
  HTTP/close authentication, host-policy, protocol, redirect, and retry
  semantics while bounding and redacting peer-provided reasons; the 58-line
  `GatewayAsyncPrimitives` owns only gateway deadlines and one-shot
  continuations. Direct policy tests cover all classification families and
  credential redaction, while architecture contracts cap the sources at
  710/175/70 lines and 930 lines in aggregate. The exact staged tree passed all
  609 unit/protocol tests in
  `build/DerivedData-GatewayClientExact/Logs/Test/Test-Nile-2026.08.08_23-10-12-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-Release-GatewayClientExact`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split the security-sensitive attachment download policy out of the 777-line
  `GatewayDashboardClient`. The bounded 424-line JSON/sign-in core now owns
  dashboard requests, structured error decoding, and safe login URLs, while the
  365-line download extension retains managed-path encoding, manual redirect
  validation, cross-origin credential stripping, HTTPS-downgrade rejection,
  response-size bounds, and safe filenames. Both halves share one immutable
  HTTP transport and default-port helper; architecture tests cap them at
  440/380 lines and 810 lines in aggregate. The exact staged tree passed all 605
  unit/protocol tests in
  `build/DerivedData-GatewayDashboardExact/Logs/Test/Test-Nile-2026.08.08_23-00-20-+0200.xcresult`
  and a strict unsigned Release build with warnings as errors in
  `build/DerivedData-Release-GatewayDashboardExact`; its generated Release
  `Info.plist` has no `NSAppTransportSecurity` dictionary.
- Split explicit saved-profile actions, dashboard sign-in/reconnect handling,
  and Hermes voice-settings presentation out of the 1,100-line
  `GatewaySetupModel` monolith. The 390-line core now retains observable form
  state, dependency construction, handler installation, and initial connection;
  bounded 293-line connection, 285-line profile, and 160-line voice extensions
  own their respective state-machine projections without broadening the
  read-only pending-switch setter. Architecture contracts enforce responsibility
  placement, individual source caps, and a 1,150-line aggregate cap. The
  exact-staged full 604-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-GatewaySetupExact/Logs/Test/Test-Nile-2026.08.08_22-50-46-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-GatewaySetupExact`, whose packaged plist is
  valid and contains no `NSAppTransportSecurity` override.
- Split reconnect restoration, gateway reset/loading, protected draft/pin
  restoration, displayed-session selection, fail-closed source lookup,
  live/history opening, pin actions, periodic refresh application, and goal
  synchronization out of the 1,096-line `SessionListModel` core. The bounded
  227-line `SessionListModelGateway` and 515-line
  `SessionListModelNavigation` extensions receive no repository or event-stream
  capability; the now 397-line core retains stored observable state, runtime
  composition, lifecycle adapters, and the private terminal-provenance/Claim
  coordinator behind narrow reset, classification, and recording helpers.
  Architecture contracts enforce bridge ownership, coordinator isolation,
  individual source caps, and an aggregate 1,940-line cap across the core,
  gateway, navigation, timeline, and sole ordered event-application sources.
  The exact-staged full 603-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionNavigationExact/Logs/Test/Test-Nile-2026.08.08_22-39-06-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionNavigationExact`, whose packaged plist
  is valid and contains no `NSAppTransportSecurity` override.
- Split visible-session timeline caching, guarded mid-turn restoration,
  foreground/status reconciliation, live/stored transcript replacement, and
  background/blocking/delegation runtime binding out of the 1,330-line
  `SessionListModel` core into a bounded 241-line
  `SessionListModelTimeline` extension. `SessionTimelineRuntime` retains the
  bounded offscreen cache and hidden-event projection, `SessionEventRuntime`
  remains the sole stream consumer, and the new model-facing source receives no
  repository or event-stream capability. The core is now 1,096 lines;
  architecture contracts enforce timeline ownership and individual plus
  aggregate core/timeline/event caps. The focused architecture/model slice
  passes 180/180 in
  `build/DerivedData-SessionTimelineBridge/Logs/Test/Test-Nile-2026.08.08_22-24-09-+0200.xcresult`;
  the exact-staged full 603-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionTimelineExact/Logs/Test/Test-Nile-2026.08.08_22-25-35-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionTimelineExact`, whose packaged plist is
  valid and contains no `NSAppTransportSecurity` override.
- Split the complete ordered Hermes event-application path out of the
  1,850-line `SessionListModel` core into the bounded 536-line
  `SessionListModelEvents` extension. `SessionEventRuntime` remains the only
  repository-stream consumer and cadence owner; the event extension owns
  visible/offscreen projection, terminal settlement, and blocking-input event
  effects without repository construction, while the now 1,330-line core
  retains shared state and session-ownership coordination. Architecture
  contracts enforce one event decoder, reject stream/capability construction in
  the application source, keep `HermesStreamEvent` out of the core, and cap the
  core and event source independently and together. The focused
  architecture/model slice passes 180/180 in
  `build/DerivedData-SessionEventsBridge/Logs/Test/Test-Nile-2026.08.08_22-12-58-+0200.xcresult`;
  the exact-staged full 603-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionEventsExact/Logs/Test/Test-Nile-2026.08.08_22-17-00-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionEventsExact`, whose packaged plist is
  valid and contains no `NSAppTransportSecurity` override.
- Split session-creation admission, protected text/photo draft handoff,
  immutable display/gateway request fencing, deterministic fixture creation,
  and post-create projection out of the 2,088-line `SessionListModel` core into
  a bounded 255-line `SessionListModelCreation` bridge. Navigation and
  creation-draft runtimes retain create/list transport and protected migration
  authority; the bridge receives no repository capability or Hermes event
  stream, while the now 1,850-line core retains session-ownership coordination
  and its sole ordered event-application method. The architecture contracts
  enforce adapter/runtime ownership, coordinator isolation, event isolation,
  and individual plus combined source caps. The focused architecture/model
  slice passes 180/180 in
  `build/DerivedData-SessionCreationBridge/Logs/Test/Test-Nile-2026.08.08_22-03-00-+0200.xcresult`;
  the exact-staged full 603-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionCreationExact/Logs/Test/Test-Nile-2026.08.08_22-04-32-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-SessionCreationRelease`, whose packaged plist is valid
  and contains no `NSAppTransportSecurity` override.
- Split displayed composer admission, protected text-draft projection,
  restoration callbacks, prompt/steer submission and recovery, Stop settlement,
  and background-turn presentation out of the 2,666-line `SessionListModel`
  core into bounded 247-line `SessionListModelComposer` and 347-line
  `SessionListModelTurn` bridges. Feature runtimes retain protected persistence,
  transport tasks, uncertainty and Stop fencing, Talk state, and blocking-input
  authority; neither bridge receives a repository capability or Hermes event
  stream, and the now 2,088-line core remains the sole ordered event-application
  boundary. Two architecture tests enforce adapter ownership, runtime use,
  event isolation, and individual plus combined source caps. The focused
  architecture/model slice passes 179/179 in
  `build/DerivedData-SessionComposerTurnBridges/Logs/Test/Test-Nile-2026.08.08_21-53-19-+0200.xcresult`;
  the exact-staged full 602-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionComposerTurnExact/Logs/Test/Test-Nile-2026.08.08_21-55-06-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-SessionComposerTurnRelease`, whose packaged plist is
  valid and contains no `NSAppTransportSecurity` override.
- Split photo-draft add/remove projection, delivery admission, protected
  mutation-marker settlement, definite recovery, uncertainty quarantine, and
  relaunch presentation out of the 3,131-line `SessionListModel` core into a
  bounded 475-line `SessionListModelAttachments` bridge. The attachment
  transport, persistence, and recovery runtimes retain task/correlation state,
  protected authority, and reconciliation; the core forwards only typed
  attachment settlement and quarantine effects from its sole ordered Hermes
  event-application method. The now 2,666-line core and bridge receive no new
  repository or event-stream dependency. The strengthened architecture
  boundary enforces adapter ownership, all three runtime integrations, event
  isolation, the single ordered core boundary, and individual plus combined
  source caps. The focused attachment/model/architecture slice passes 177/177
  in
  `build/DerivedData-SessionAttachmentsBridge/Logs/Test/Test-Nile-2026.08.08_21-40-21-+0200.xcresult`;
  the exact-staged full 600-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionAttachmentsBridge-Exact/Logs/Test/Test-Nile-2026.08.08_21-42-35-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionAttachmentsBridge-Exact`, whose
  packaged plist is valid and contains no `NSAppTransportSecurity` override.
- Split delegated-agent observable state, visible transcript projection,
  controls, child navigation, deterministic fixtures, and typed runtime
  callbacks out of the 3,286-line `SessionListModel` core and 262-line general
  presentation extension into a bounded 185-line
  `SessionListModelDelegation` bridge. `SessionDelegationRuntime` retains
  capability requests, persistence, task cancellation, lifecycle generations,
  and coordination state; the core retains ordered Hermes event decoding and
  forwards only typed delegation effects. The bridge receives no repository
  capability or Hermes event stream. The now 3,131-line core retains exactly
  one ordered event-application method, while general presentation is 242
  lines. The strengthened architecture boundary enforces adapter ownership,
  core event handoff, runtime use, event isolation, and individual plus combined
  source caps. The focused delegation/model/architecture slice passes 180/180
  in
  `build/DerivedData-SessionDelegationBridge/Logs/Test/Test-Nile-2026.08.08_21-27-41-+0200.xcresult`;
  the exact-staged full 599-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionDelegationBridge-Exact/Logs/Test/Test-Nile-2026.08.08_21-29-37-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionDelegationBridge-Exact`, whose packaged
  plist is valid and contains no `NSAppTransportSecurity` override.
- Split usage/context and gateway-statistics observable state, actions, period
  options, and immutable owner capture out of the 3,354-line `SessionListModel`
  core and 312-line general presentation extension into a bounded 131-line
  `SessionListModelUsage` bridge. `SessionUsageRuntime` retains authenticated
  polling/statistics requests, retry policy, tasks, independent generations,
  and telemetry state; the core invokes only lifecycle refresh/reset methods.
  The bridge receives no repository capability or Hermes event stream. The now
  3,286-line core retains exactly one ordered event-application method, while
  general presentation is 262 lines. The strengthened architecture boundary
  enforces adapter ownership, runtime use, event isolation, and individual plus
  combined source caps. The focused usage/model/architecture slice passes
  184/184 in
  `build/DerivedData-SessionUsageBridge/Logs/Test/Test-Nile-2026.08.08_21-20-27-+0200.xcresult`;
  the exact-staged full 599-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionUsageBridge-Exact/Logs/Test/Test-Nile-2026.08.08_21-22-27-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionUsageBridge-Exact`, whose packaged
  plist is valid and contains no `NSAppTransportSecurity` override.
- Split Claim/Rename presentation, eligibility, exact-owner capture, and runtime
  callbacks out of the 3,529-line `SessionListModel` core and 332-line general
  presentation extension into a bounded 225-line
  `SessionListModelManagement` bridge. `SessionManagementRuntime` retains
  authenticated status/open/rename requests, tasks, dialogs, and independent
  operation generations; successful Claim still crosses a guarded core method
  before terminal provenance, the live session, transcript, and usage change.
  The bridge receives no repository capability or Hermes event stream. The now
  3,354-line core retains exactly one ordered event-application method, while
  general presentation is 312 lines. The strengthened architecture boundary
  enforces adapter ownership, authoritative projection, runtime use, event
  isolation, and individual plus combined source caps. The focused management,
  model, and architecture slice passes 182/182 in
  `build/DerivedData-SessionManagementBridge/Logs/Test/Test-Nile-2026.08.08_21-11-57-+0200.xcresult`;
  the exact-staged full 599-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionManagementBridge-Exact/Logs/Test/Test-Nile-2026.08.08_21-14-59-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionManagementBridge-Exact`, whose packaged
  plist is valid and contains no `NSAppTransportSecurity` override.
- Split displayed-media state, open/dismiss actions, exact-owner validation,
  preview reconciliation, and attachment forwarding out of the 3,608-line
  `SessionListModel` core and 340-line general presentation extension into a
  bounded 97-line `SessionListModelMedia` bridge. The media runtime's core
  retains authenticated reads, cache access, and all viewer/preview task state,
  while its same-runtime preview extension owns two-preview scheduling,
  eight-entry retention, hydration, and completion fencing; the bridge receives
  no repository capability or Hermes event-stream dependency. The now
  3,529-line core retains the ordered event
  boundary, while general presentation is 332 lines. A new architecture
  boundary enforces adapter ownership, runtime use, event isolation, and
  individual plus combined source caps. The media/model/architecture slice
  passes 176/176 in
  `build/DerivedData-SessionMediaBridge/Logs/Test/Test-Nile-2026.08.08_21-01-05-+0200.xcresult`;
  the exact-staged full 599-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionMediaBridge-Exact/Logs/Test/Test-Nile-2026.08.08_21-04-38-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionMediaBridge-Exact`, whose packaged
  plist is valid and contains no `NSAppTransportSecurity` override.
- Split standing-goal sheet actions, kickoff/resume turn integration, prompt
  failure settlement, and exact-owner fencing out of the 3,791-line
  `SessionListModel` core into a bounded 193-line `SessionListModelGoal`
  extension. `SessionGoalRuntime` retains goal capability tasks, lifecycle
  generations, validation, and progress state; the bridge receives no
  repository-composition or Hermes event-stream dependency. The now
  3,608-line core retains authoritative goal-event reconciliation and exactly
  one ordered Hermes event-application method. A new architecture boundary
  enforces adapter ownership, runtime use, event isolation, and individual plus
  combined source caps. The goal/model/architecture slice passes 175/175 in
  `build/DerivedData-SessionGoalBridge/Logs/Test/Test-Nile-2026.08.08_20-50-57-+0200.xcresult`;
  the exact-staged full 598-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionGoalBridge-Exact/Logs/Test/Test-Nile-2026.08.08_20-55-01-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionGoalBridge-Exact`, whose packaged
  plist is valid and contains no `NSAppTransportSecurity` override.
- Split model-picker, model-selection, reasoning-effort, and pin adapters out of
  the 4,000-line `SessionListModel` core into a bounded 221-line
  `SessionListModelModelControl` extension. The bridge owns UI-facing catalog
  projection, exact-owner fencing, confirmation presentation, and live-session
  updates while `SessionModelControlRuntime` retains capability lookup,
  provider resolution, pin persistence, and mutation execution. Only the
  display-generation fence is shared with the core; the extension has no
  repository-composition or Hermes event-stream dependency, and the now
  3,791-line core retains exactly one ordered event-application method. A new
  architecture boundary enforces source ownership, individual and combined
  size caps, runtime use, and the absence of repository construction or event
  consumption. The model-control/model/architecture slice passes 174/174 in
  `build/DerivedData-SessionModelControlBridge/Logs/Test/Test-Nile-2026.08.08_20-40-20-+0200.xcresult`;
  the exact-staged full 597-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionModelControlBridge-Exact/Logs/Test/Test-Nile-2026.08.08_20-43-43-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionModelControlBridge-Exact`, whose
  packaged plist is valid and contains no `NSAppTransportSecurity` override.
- Split the 413-line model-facing slash-command adapter out of the 4,413-line
  `SessionListModel` into a bounded 425-line `SessionListModelCommands`
  extension. The extension owns completion projection, native-action draft
  claims, remote outcome integration, transcript rows, and definite/uncertain
  recovery while `SessionCommandRuntime` retains repository access, command
  policy, remote completion/execution task ownership, alias validation, and
  cancellation. It has no
  repository-composition or event-stream dependency; the 4,000-line core
  retains exactly one ordered Hermes event-application method. A new
  architecture boundary enforces source ownership, individual and combined
  size caps, and the absence of repository construction or event consumption.
  The command-runtime/model/architecture slice passes 175/175 in
  `build/DerivedData-SessionCommandBridge/Logs/Test/Test-Nile-2026.08.08_20-30-37-+0200.xcresult`;
  the exact-staged full 596-test unit/protocol suite passes without failures or
  skips in
  `build/DerivedData-SessionCommandBridge-Exact/Logs/Test/Test-Nile-2026.08.08_20-33-22-+0200.xcresult`;
  the exact-staged warnings-as-errors optimized unsigned Release build passes
  from `build/DerivedData-Release-SessionCommandBridge-Exact`, whose packaged
  plist contains no `NSAppTransportSecurity` override.
- Split the 325-line model-facing voice/Talk bridge out of the 4,739-line
  `SessionListModel` into a bounded 336-line `SessionListModelVoice` extension.
  The extension owns composer voice presentation, app/surface lifecycle
  responses, Talk owner and listening gates, optimistic Talk submission
  projection, and spoken-completion callbacks while the dedicated runtimes
  retain all capability tasks. It has no repository or event-stream dependency;
  the 4,413-line core retains exactly one ordered Hermes event-application
  method. The architecture boundary enforces source ownership and individual
  plus combined size caps. The voice/Talk/speech/model/architecture slice passes
  185/185 in
  `build/DerivedData-SessionVoiceBridge/Logs/Test/Test-Nile-2026.08.08_20-21-20-+0200.xcresult`;
  the full 595-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-SessionVoiceBridge/Logs/Test/Test-Nile-2026.08.08_20-22-32-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionVoiceBridge`, whose packaged plist contains
  no `NSAppTransportSecurity` override.
- Extracted app/surface lifecycle and background-turn coordination from the
  4,773-line `SessionListModel` into a 139-line `SessionLifecycleRuntime`. The
  runtime owns foreground/background transition history, connection-loss and
  background-turn-started callbacks, and the exact-owner coordinator while
  receiving no repository or event-stream capability; the 4,739-line model
  retains authoritative reconciliation and exactly one ordered Hermes
  event-application method. The architecture boundary enforces that ownership
  and source-size cap. Five direct lifecycle-runtime tests plus the coordinator,
  architecture, and model suites pass 186/186 in
  `build/DerivedData-SessionLifecycleRuntime/Logs/Test/Test-Nile-2026.08.08_20-08-39-+0200.xcresult`;
  the full 594-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-SessionLifecycleRuntime/Logs/Test/Test-Nile-2026.08.08_20-09-53-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionLifecycleRuntime`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Split the 5,510-line `SessionListModelTests` monolith into a 3,470-line core,
  a 359-line attachment-delivery extension, an 847-line recovery/media
  extension, a 667-line command/model extension, and a 195-line shared fixture
  helper extension. All 134 scenarios retain the same
  `SessionListModelTests` discovery identity and original test names; rebuilding
  the former source from the split is byte-for-byte equivalent after restoring
  only the helpers' former `private` access. The architecture boundary enforces
  feature ownership, per-source and combined size caps, helper isolation, and
  the exact 134-test inventory. The direct model suite passes 134/134 in
  `build/DerivedData-SessionModelTestSplit/Logs/Test/Test-Nile-2026.08.08_19-54-55-+0200.xcresult`;
  the complete architecture/model slice passes 170/170 in
  `build/DerivedData-SessionModelTestSplit/Logs/Test/Test-Nile-2026.08.08_19-56-52-+0200.xcresult`;
  the full 588-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-SessionModelTestSplit/Logs/Test/Test-Nile-2026.08.08_19-57-48-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionModelTestSplit`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Split runtime-backed observable forwarding, directory ordering/search,
  runtime status labels, and terminal source labels out of the 5,050-line
  `SessionListModel` into a bounded 340-line
  `SessionListModelPresentation` extension. The 4,773-line core retains stored
  orchestration state, feature-runtime construction, async mutation sequencing,
  and exactly one ordered Hermes event-application method. The architecture
  boundary prevents the presentation extension from importing event types or
  constructing runtimes, caps both sources and their combined size, and keeps
  every adapter out of the core model. The complete architecture/model suite
  passes 170/170 in
  `build/DerivedData-SessionListPresentation/Logs/Test/Test-Nile-2026.08.08_09-13-25-+0200.xcresult`;
  five selector-driven session search/pin, Rename, model-picker, context, and
  statistics XCUITests pass in
  `build/DerivedData-SessionListPresentation/Logs/Test/Test-Nile-2026.08.08_09-18-08-+0200.xcresult`;
  the full 588-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-SessionListPresentation/Logs/Test/Test-Nile-2026.08.08_09-14-58-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionListPresentation`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Split the mixed 965-line usage/statistics source into a 190-line
  `ContextBreakdownSheet`, a 607-line `GatewayStatsSheet`, and a
  Foundation-only 170-line `GatewayStatsProjection`. Context composition and
  token formatting, sheet/chart rendering, and UTC momentum/13-week heatmap
  projection now have independent owners without changing the Android-aligned
  presentation contract. A source boundary caps all three responsibilities and
  prevents projection math from depending on SwiftUI or session state; a new
  deterministic heatmap test covers the UTC window, future cell, logarithmic
  level, invalid-day, and accessibility-summary rules. The 43 focused
  architecture and usage/goal codec tests pass in
  `build/DerivedData-UsageStatsSplit/Logs/Test/Test-Nile-2026.08.08_08-58-57-+0200.xcresult`;
  the two selector-driven context and statistics XCUITests pass in
  `build/DerivedData-UsageStatsSplit/Logs/Test/Test-Nile-2026.08.08_08-54-07-+0200.xcresult`;
  the full 587-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-UsageStatsSplit/Logs/Test/Test-Nile-2026.08.08_08-59-49-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-UsageStatsSplit`, whose packaged plist contains no
  `NSAppTransportSecurity` override.
- Split the 1,142-line model-picker source into a 332-line sheet/reasoning
  overlay, a 576-line searchable `ModelPickerCatalogView`, and a 116-line
  fail-closed confirmation surface. Catalog-local query, focus, provider
  expansion, model selection, and pin interaction state now has one component
  owner, while the overlay retains sheet-level loading/error/reasoning policy.
  The split also deletes 157 lines of unreachable custom close, disclosure, and
  push-pin glyph implementations, reducing the combined production surface to
  1,024 lines. The architecture regression enforces the three responsibilities,
  their source-size bounds, and continued absence of the dead glyphs. The 168
  focused architecture, model-control, and model integration tests pass in
  `build/DerivedData-ModelPickerSplit/Logs/Test/Test-Nile-2026.08.08_08-34-47-+0200.xcresult`;
  the two selector-driven picker search/pin/dismiss and provider/model interaction
  XCUITests pass in
  `build/DerivedData-ModelPickerSplit/Logs/Test/Test-Nile-2026.08.08_08-36-13-+0200.xcresult`;
  the full 585-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-ModelPickerSplit/Logs/Test/Test-Nile-2026.08.08_08-40-40-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-ModelPickerSplit`, whose packaged plist contains no
  `NSAppTransportSecurity` override.
- Consolidated production and fixture construction for all 23 session feature
  runtimes/coordinators into the retained 223-line
  `SessionRuntimeComposition`. The composition root unwraps the explicit
  17-slot `SessionRepositoryCapabilities` bundle once, narrows every transport
  dependency at construction, and preserves the shared voice/speech,
  composer/persistence, and navigation runtime identities. `SessionListModel`
  now retains one runtime graph instead of 23 parallel fields and no longer
  constructs feature runtimes or unwraps repository capabilities in either
  initializer, shrinking from 5,213 to 5,050 lines. The architecture regression
  enforces production/fixture ownership, exact capability mapping, shared
  identities, and source-size bounds. The 169 focused composition, event, and
  model tests pass in
  `build/DerivedData-RuntimeComposition/Logs/Test/Test-Nile-2026.08.08_08-20-13-+0200.xcresult`;
  the full 584-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-RuntimeComposition/Logs/Test/Test-Nile-2026.08.08_08-21-23-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-RuntimeComposition`, whose packaged plist contains
  no `NSAppTransportSecurity` override.
- Extracted the authoritative Hermes event stream and assistant-delta cadence
  from `SessionListModel` into the 184-line `SessionEventRuntime`. The runtime is
  now the only `HermesEventStreaming` owner and owns the one stream task,
  cadence timer, lossless coalescer, hidden-session bypass, structural and
  session-switch flush barriers, and publication accounting. The model retains
  one ordered event-application boundary and feature presentation, shrinking
  from 5,256 to 5,213 lines; `LiveTranscriptCoordinator` now owns only transcript
  projection and shrinks from 413 to 361 lines. The architecture regression
  rejects stream/task/coalescer state in the model and caps all three sources.
  The 51 focused event, transcript, model, and architecture tests pass in
  `build/DerivedData-SessionEventRuntime/Logs/Test/Test-Nile-2026.08.08_07-57-56-+0200.xcresult`;
  the full 583-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-SessionEventRuntime/Logs/Test/Test-Nile-2026.08.08_08-00-44-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionEventRuntime`, whose packaged plist contains
  no `NSAppTransportSecurity` override.
- Extracted blocking-input responses, model catalog/session controls, and usage
  transport into the 118-line `GatewayBlockingPromptService`, 99-line
  `GatewayModelService`, and 58-line `GatewayUsageService`. Dashboard-backed
  analytics and the remaining repository consumers now share the 26-line
  actor-isolated `GatewayConnectionState`, so connect/disconnect ownership stays
  singular and fail-closed. `TuiGatewayRepository` no longer conforms to those
  three capabilities or contains their operations, preserves sensitive-response
  uncertainty, exact model mutation validation, best-effort context breakdown,
  authenticated analytics, and the sole ordered signal projection, and shrinks
  from 772 to 520 lines. The 63 focused gateway and architecture tests pass in
  `build/DerivedData-GatewayCapabilityServices/Logs/Test/Test-Nile-2026.08.08_07-44-55-+0200.xcresult`;
  the full 580-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-GatewayCapabilityServices/Logs/Test/Test-Nile-2026.08.08_07-45-58-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-GatewayCapabilityServices`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Extracted command discovery/completion/execution into the 83-line
  `GatewayCommandService` and standing-goal status/mutations into the 247-line
  `GatewayGoalService`. The goal service depends only on
  `HermesCommandServing` for the exact `command.resolve` shadow check, preserving
  the collision fence, `cli.exec` turn-budget validation, RPC shapes, timeouts,
  and fail-closed mutation semantics without duplicating command transport.
  `TuiGatewayRepository` no longer conforms to either capability or contains
  those operations; it retains connection ownership and the sole ordered signal
  projection while shrinking from 1,071 to 772 lines. The 62 focused gateway
  and architecture tests pass in
  `build/DerivedData-GatewayCommandGoalServices/Logs/Test/Test-Nile-2026.08.08_07-31-28-+0200.xcresult`;
  the full 579-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-GatewayCommandGoalServices/Logs/Test/Test-Nile-2026.08.08_07-32-34-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-GatewayCommandGoalServices`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Used the session capability bundle for real production composition by
  extracting all delegation status, interrupt, save/list/load snapshot RPCs
  into the 173-line `GatewayDelegationService`, which independently implements
  `HermesDelegationServing`. `TuiGatewayRepository` no longer conforms to that
  capability or contains those operations; it contributes the service directly
  while retaining the sole ordered signal projection and shrinks from 1,222 to
  1,071 lines. The shared 12-line `GatewayRPCRequesting` seam also moved out of
  the repository source. The 62 focused gateway and architecture tests pass in
  `build/DerivedData-GatewayDelegationService/Logs/Test/Test-Nile-2026.08.08_07-22-05-+0200.xcresult`;
  the full 579-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-GatewayDelegationService/Logs/Test/Test-Nile-2026.08.08_07-23-18-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-GatewayDelegationService`, whose packaged plist
  contains no `NSAppTransportSecurity` override.
- Removed the all-capabilities Swift `HermesRepository` protocol. The explicit
  17-slot `SessionRepositoryCapabilities` composition boundary can be assembled
  from independent collaborators; production initially supplied one unified
  `TuiGatewayRepository`, while `SessionListModel` unwraps it once, retains only
  the authoritative event stream, and gives every feature runtime its exact
  narrow protocol. Connection lifecycle and global Hermes voice configuration
  remain outside the session feature graph, and the model remains the sole
  ordered event router. The architecture regression and complete 578-test
  unit/protocol suite pass in
  `build/DerivedData-SessionCapabilities/Logs/Test/Test-Nile-2026.08.08_07-11-34-+0200.xcresult`;
  the warnings-as-errors optimized unsigned Release build passes from
  `build/DerivedData-Release-SessionCapabilities`, whose product plist contains
  no `NSAppTransportSecurity` override.
- Added an optional iOS biometric app lock in Settings. Opt-in is persisted only
  after successful Face ID or Touch ID evaluation; enabled cold launches and
  returns from background stay behind an opaque, accessibility-isolating
  privacy shield until a fresh success. Cancellation, authentication failure,
  unavailable or unenrolled biometrics, and background transitions remain
  fail closed, while transient inactive snapshots are covered without
  needlessly relocking the active session. Seven focused model tests cover the
  disabled, enable, unavailable/failure, lifecycle/retry, background-during-
  authentication race, transient inactive authentication, and disable
  contracts. A scene-level shield window covers app-owned sheets and other
  presentations; a lifecycle XCUITest keeps a goal sheet open across
  backgrounding and verifies failed authentication leaves only the lock
  interactive.
- Integrated the live-turn status into the composer glass as a compact,
  divider-separated activity row instead of a detached label. Working,
  Stopping, and Needs input retain elapsed-time and VoiceOver semantics; the
  input, controls, and bottom anchor remain fixed while the pill settles upward
  with a small spring that is disabled under Reduce Motion.
- Replaced the session header's three competing glass circles with a restrained
  shared action rail. Settings remains a stable one-tap control, while Rename
  and Usage live in an adjacent semantic popover that leaves the complete title
  bar composed and stationary; both rail controls retain
  48-point targets, neutral resting color, pressed accent feedback, stable
  identifiers, and the rename progress indicator. The focused rail/popover and
  rename lifecycle XCUITests pass in
  `build/DerivedData-HeaderPopover/Logs/Test/Test-Nile-2026.08.07_21-37-32-+0200.xcresult`.
- Initialized the iOS Git repository without touching the private Android source.
- Installed XcodeGen 2.46.0 and generated `Nile.xcodeproj`.
- Installed and verified OpenJDK 17.0.20, Android command-line tools, platform
  tools 37.0.1, Android 35, Build Tools 35.0.0/36.0.0, Emulator 36.6.11, and
  the Android 35 Google APIs arm64 system image for source-authoritative Android
  captures on this Mac.
- Created Debug, LocalRelease, and Release configurations.
- Re-established one authoritative cleartext security contract after temporary
  configuration drift: Debug and LocalRelease retain the ATS exception and
  compile the explicit per-profile approval workflow, while Release compiles
  out that workflow and has no arbitrary-load exception. Domain URL creation,
  gated dashboard authentication, and WebSocket connection setup all reject a
  denied cleartext permission before credentials or transport work begins.
  The focused clean-onboarding and approval XCUITests pass 2/2 on a disposable
  iPhone 17 Pro in
  `build/DerivedData-CleartextUIFresh/Logs/Test/Test-Nile-2026.08.08_06-43-31-+0200.xcresult`;
  the full 576-test unit/protocol suite passes without failures or skips in
  `build/DerivedData-CleartextBoundary/Logs/Test/Test-Nile-2026.08.08_06-44-24-+0200.xcresult`.
  The warnings-as-errors unsigned optimized Release build passes from
  `build/DerivedData-Release-CleartextBoundary`, and its packaged plist contains
  no `NSAppTransportSecurity` override.
- An earlier slice moved every app-graph-owned deterministic sample, fake
  store/service, and fixture-only voice/statistics helper behind the dedicated
  409-line `NileAppGraphFixtures` namespace/source. It reduced
  `NileAppGraph.swift` from 1,168 to a 770-line intermediate that retained
  production dependency wiring, fixture selection, streaming-stress
  orchestration, and notification routing. That slice's source boundary capped
  both files and prevented fixture implementations from returning to the graph.
  Its full 577-test unit/protocol suite passed without
  failures or skips in
  `build/DerivedData-AppGraphFixtures/Logs/Test/Test-Nile-2026.08.08_06-58-19-+0200.xcresult`;
  four focused onboarding, usage, statistics, and Talk fixture XCUITests pass on
  a fresh disposable iPhone 17 Pro in
  `build/DerivedData-AppGraphFixtureUIFresh/Logs/Test/Test-Nile-2026.08.08_07-03-27-+0200.xcresult`;
  the warnings-as-errors unsigned optimized Release build passes from
  `build/DerivedData-Release-AppGraphFixtures`, and its packaged plist contains
  no `NSAppTransportSecurity` override.
- Moved the 838-line deterministic session fixture catalog and embedded media
  payloads from `SessionListModel.swift` into `SessionListFixture.swift`, reducing
  the production model source from 10,025 to 9,186 lines without changing its
  fixture initializer or ordered event router. A source-layout regression keeps
  that boundary in place; the full 454-test unit/protocol suite passes in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_23-17-57-+0200.xcresult`, and
  the unsigned generic-device Release build passes from
  `build/DerivedData-Release-FixtureBoundary`.
- Extracted session usage, context, and statistics state into a 317-line
  `SessionUsageRuntime` narrowed to `HermesUsageServing`. It owns polling and
  statistics tasks, retry policy, generation fences, loading/error state, and
  immutable owner snapshots while `SessionListModel` retains the sole ordered
  event router and forwards observable presentation state. The model is now
  8,997 lines; the full 456-test unit/protocol suite passes in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_23-29-08-+0200.xcresult`, and
  the unsigned generic-device Release build passes from
  `build/DerivedData-Release-UsageRuntime`.
- Extracted standing-goal validation, RPC mutations, status refreshes, progress
  projection, observable state, and lifecycle fencing into
  `SessionGoalRuntime`, narrowed to `HermesGoalServing`. `SessionListModel`
  retains ordinary prompt delivery, transcript annotation, and its sole ordered
  event router, and is reduced from 8,997 to 8,544 lines. The full 461-test
  unit/protocol suite passes in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_23-46-06-+0200.xcresult`, and
  the unsigned generic-device Release build passes from
  `build/DerivedData-Release-GoalRuntime`.
- Extracted the model catalog, model/reasoning mutations, expensive-model
  confirmation, provider-aware pin resolution, and protected FIFO pin writes
  into a 700-line `SessionModelControlRuntime` narrowed to
  `HermesModelServing`. Immutable gateway/display/session owners and independent
  generations fence catalog, control, and pin results; uncertain model writes
  still fail closed, while `SessionListModel` retains live-session projection,
  transcript notices, and its sole ordered event router. The model is reduced
  from 8,544 to 8,160 lines. The full 464-test unit/protocol suite passes in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_00-05-13-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-ModelControlRuntime`. The two focused model-picker
  XCUITests preserve in-memory pin mutation and model-switch progress in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_00-02-23-+0200.xcresult`.
- Consolidated five copies of protected-file path, atomic-write, data-
  protection, backup-exclusion, and removal mechanics behind the 124-line
  `ProtectedFileStorage`, and replaced the model-pin and session-pin queue tails
  with one `OrderedPersistenceQueue`. Gateway metadata, composer drafts, photo
  drafts, model pins, and session pins retain their domain-specific envelopes,
  validation, error mapping, and removal tombstones while their combined
  production persistence sources shrink from 2,103 to 1,978 lines. The focused
  persistence/queue/boundary suite passes 36/36 in
  `build/DerivedData-ProtectedPersistence/Logs/Test/Test-Nile-2026.08.08_00-19-40-+0200.xcresult`,
  and the full 465-test unit/protocol suite passes in
  `build/DerivedData-ProtectedPersistence/Logs/Test/Test-Nile-2026.08.08_00-17-05-+0200.xcresult`;
  the unsigned generic-device Release build passes from
  `build/DerivedData-Release-ProtectedPersistence`.
- Extracted delegated-agent coordination, interrupt/reconciliation/snapshot
  tasks, lifecycle fencing, persistence, and observable projection state into
  a 390-line `SessionDelegationRuntime` narrowed to
  `HermesDelegationServing`. `SessionListModel` retains navigation, current-
  transcript projection, and the sole ordered `HermesStreamEvent` router while
  shrinking from 8,160 to 7,821 lines; the 204-line deterministic delegation
  payload catalog is isolated in `SessionDelegationFixture.swift`. The full
  466-test unit/protocol suite passes in
  `build/DerivedData-DelegationRuntime/Logs/Test/Test-Nile-2026.08.08_00-31-21-+0200.xcresult`,
  the three delegation XCUITests pass in
  `build/DerivedData-DelegationRuntime/Logs/Test/Test-Nile-2026.08.08_00-32-22-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-DelegationRuntime`.
- Split model catalog decoding, mutation acknowledgement validation, and safe
  model/provider argument checks into the 313-line `GatewayModelCodec`, and
  consolidated the uncertain mutation-result primitives shared by model,
  delegation, and goal operations in the 69-line `GatewayMutationCodec`.
  `TuiGatewayRepository.swift` now concentrates on transport orchestration and
  is reduced from 1,997 to 1,576 lines without widening its private connection
  state. The 38 focused repository/architecture tests pass in
  `build/DerivedData-GatewayModelCodec/Logs/Test/Test-Nile-2026.08.08_00-41-23-+0200.xcresult`,
  the full 467-test unit/protocol suite passes in
  `build/DerivedData-GatewayModelCodec/Logs/Test/Test-Nile-2026.08.08_00-43-15-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-GatewayModelCodec`.
- Extracted command catalog/completion/execution validation into the 265-line
  `GatewayCommandCodec` and synthesis/transcription/voice validation into the
  143-line `GatewaySpeechCodec`. `TuiGatewayRepository.swift` now retains
  authenticated transport dispatch, connection ownership, capability
  classification, and ordered event projection while shrinking from 1,576 to
  1,204 lines. The 39 focused repository/architecture tests pass in
  `build/DerivedData-GatewayCapabilityCodecs/Logs/Test/Test-Nile-2026.08.08_00-50-36-+0200.xcresult`,
  the full 468-test unit/protocol suite passes in
  `build/DerivedData-GatewayCapabilityCodecs/Logs/Test/Test-Nile-2026.08.08_00-52-28-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-GatewayCapabilityCodecs`.
- Extracted command discovery state, debounced completion ownership, remote
  execution tasks, alias validation, uncertainty classification, and gateway-
  reset cancellation into the 355-line `SessionCommandRuntime`, narrowed to
  `HermesCommandServing`. Its current pure domain dependencies independently
  separate the 281-line fail-closed dispatch policy from the 142-line catalog
  curation/completion policy, with the latter reusing the former for every
  visibility decision. `SessionListModel` retains protected draft handling,
  transcript presentation, native command actions, and the sole ordered event
  router while shrinking from 7,821 to 7,654 lines. The 16 focused command,
  model, and architecture tests pass in
  `build/DerivedData-SessionCommandRuntime/Logs/Test/Test-Nile-2026.08.08_01-11-02-+0200.xcresult`,
  the full 471-test unit/protocol suite passes in
  `build/DerivedData-SessionCommandRuntime/Logs/Test/Test-Nile-2026.08.08_01-11-58-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-SessionCommandRuntime`.
- Extracted reply sanitization/chunking, synthesis dispatch, playback output,
  cancellation, request-generation fencing, and spoken-toggle failure policy
  into the 273-line `SessionSpeechRuntime`, narrowed to
  `HermesSpeechSynthesisServing`. `SessionListModel` retains Talk turn admission
  and transcript presentation in its sole ordered event router while shrinking
  from 7,654 to 7,564 lines and no longer calling speech synthesis directly.
  The four direct runtime lifecycle tests pass in
  `build/DerivedData-SessionSpeechRuntime/Logs/Test/Test-Nile-2026.08.08_01-25-48-+0200.xcresult`,
  the full 476-test unit/protocol suite passes in
  `build/DerivedData-SessionSpeechRuntime/Logs/Test/Test-Nile-2026.08.08_01-26-38-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-SessionSpeechRuntime`.
- Extracted Talk coordination, voice-phase handling, relisten and submission task
  ownership, acknowledgement and early-terminal correlation, stop/resume fencing,
  and speech transitions into the 787-line `SessionTalkRuntime`, narrowed to
  `HermesTalkServing`. `SessionListModel` retains transcript/background
  presentation and the sole ordered event router while shrinking from 7,564 to
  7,121 lines. Four direct runtime race/lifecycle tests plus nested-observation
  and architecture-boundary coverage pass, the full 482-test unit/protocol suite
  passes in
  `build/DerivedData-SessionTalkRuntime/Logs/Test/Test-Nile-2026.08.08_01-47-35-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-SessionTalkRuntime`.
- Extracted Claim advisory-status polling, mutation-time busy recheck and open,
  Rename normalization/request/error lifecycle, immutable owner snapshots, and
  independent status/Claim/Rename generation fencing into the 313-line
  `SessionManagementRuntime`, narrowed to `HermesSessionControlServing`.
  `SessionListModel` retains session/transcript presentation and the sole ordered
  event router while shrinking from 7,121 to 7,046 lines. Six direct runtime
  lifecycle/race tests plus nested-observation and architecture-boundary coverage
  pass, the full 490-test unit/protocol suite passes in
  `build/DerivedData-SessionManagementRuntime/Logs/Test/Test-Nile-2026.08.08_02-06-29-+0200.xcresult`,
  and the unsigned generic-device Release build passes from
  `build/DerivedData-Release-SessionManagementRuntime`.
- Extracted full-size attachment viewing, private-cache preparation, bounded
  image-preview hydration, two-request concurrency, eight-image retention,
  exact owner/generation validation, and per-operation UUID fencing into the
  initial 396-line `SessionMediaRuntime`, narrowed to `HermesAttachmentReading`
  plus the private cache contract. `SessionListModel` retains transcript
  presentation and the sole ordered event router while shrinking from 7,046 to
  6,909 lines. Six
  direct runtime lifecycle/policy tests plus nested-observation, existing model
  media regressions, and architecture-boundary coverage pass, the full 498-test
  unit/protocol suite passes in
  `build/DerivedData-SessionMediaRuntime/Logs/Test/Test-Nile-2026.08.08_02-30-06-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionMediaRuntime`.
- Extracted blocking-input coordination and all sensitive one-shot response
  tasks into the 350-line `SessionBlockingPromptRuntime`, narrowed to
  `HermesBlockingPromptServing`. The runtime owns typed dispatch, coordinator
  state, cancellation uncertainty, and reset-generation fencing without
  retaining response values or consuming the repository event stream;
  `SessionListModel` retains transcript/session-list projection and the sole
  ordered event router while shrinking from 6,909 to 6,799 lines. Four direct
  runtime tests plus coordinator/model/architecture regressions pass, the full
  503-test unit/protocol suite passes in
  `build/DerivedData-SessionBlockingPromptRuntime/Logs/Test/Test-Nile-2026.08.08_02-44-17-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionBlockingPromptRuntime`.
- Extracted ordinary prompt, steering, and Stop transport tasks, fail-closed
  delivery classification, gateway-reset fencing, and late Stop acknowledgement
  invalidation into the 279-line `SessionTurnRuntime`, narrowed to
  `HermesTurnServing`. Goal prompts now share the runtime and the persisted
  attachment transaction uses only its narrow submit bridge;
  `SessionListModel` retains optimistic transcript, draft-recovery, and
  background-turn projection plus the sole ordered event router while shrinking
  from 6,799 to 6,745 lines. Six direct runtime tests and 139
  model/goal/attachment regressions pass, the full 510-test unit/protocol suite
  passes in
  `build/DerivedData-SessionTurnRuntime/Logs/Test/Test-Nile-2026.08.08_02-58-33-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionTurnRuntime`.
- Extracted the bounded hidden-session timeline cache, exact live/stored
  indexes, LRU eviction, per-session transcript coordinators, synchronous
  offscreen event projection, and observed-runtime restore gate into the
  421-line `SessionTimelineRuntime`. `SessionListModel` remains the sole ordered
  event-stream consumer/router and owns global session-list presentation while
  shrinking from 6,745 to 6,453 lines. Four direct runtime tests, the
  architecture boundary, and all `SessionListModelTests` pass; the full 515-test
  unit/protocol suite passes in
  `build/DerivedData-SessionTimelineRuntime/Logs/Test/Test-Nile-2026.08.08_03-13-24-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionTimelineRuntime`.
- Extracted protected session-pin restoration, optimistic mutation state, FIFO
  desired-value writes, matching-intent rollback, and immutable gateway-owner
  fencing into the 103-line `SessionPinRuntime`. `SessionListModel` retains
  session ordering and presentation plus the sole ordered event router while
  shrinking from 6,453 to 6,432 lines; it no longer stores the pin backend or
  write queue. Four direct runtime tests, the existing model/store regressions,
  and the architecture boundary pass; the full 520-test unit/protocol suite
  passes in
  `build/DerivedData-SessionPinRuntime/Logs/Test/Test-Nile-2026.08.08_03-24-24-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionPinRuntime`.
- Consolidated initial and periodic session directory/status/history reads,
  source lookup, open/create operations, foreground reconciliation, and
  attached-turn authoritative refresh into the 352-line
  `SessionNavigationRuntime`, narrowed to `HermesSessionServing`. Immutable
  gateway/display owners fence late results, the runtime owns all three task
  lifecycles and cancellation, and `SessionListModel` retains observable
  presentation plus the sole ordered event router while remaining below its
  6,450-line architecture ceiling. Four direct runtime tests, the architecture
  boundary, and focused creation/source/history/reconciliation regressions pass;
  the full 525-test unit/protocol suite passes in
  `build/DerivedData-SessionNavigationRuntime/Logs/Test/Test-Nile-2026.08.08_03-44-37-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionNavigationRuntime`.
- Extracted the default transcription adapter, shared microphone coordinator,
  ordinary-draft listening/transcribing state, and the single Talk-first voice
  event task into the 137-line `SessionVoiceInputRuntime`, narrowed to
  `HermesTranscriptionServing`. `SessionTalkRuntime` shares the runtime, while
  `SessionListModel` retains presentation gating and its sole ordered Hermes
  event router, shrinks to 6,413 lines, and now accesses the repository directly
  only for `repository.events`. Five direct runtime/observation tests pass in
  `build/DerivedData-SessionVoiceInputRuntime/Logs/Test/Test-Nile-2026.08.08_03-57-04-+0200.xcresult`,
  ten focused model voice/Talk regressions pass in
  `build/DerivedData-SessionVoiceInputRuntime/Logs/Test/Test-Nile-2026.08.08_03-55-58-+0200.xcresult`,
  and the full 531-test unit/protocol suite passes in
  `build/DerivedData-SessionVoiceInputRuntime/Logs/Test/Test-Nile-2026.08.08_04-02-39-+0200.xcresult`;
  the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionVoiceInputRuntime`.
- Extracted attachment upload, prompt submission, response/event correlation,
  server-path leases, failure classification, start-confirmation timeout,
  disconnect, and reset fencing into the initial 429-line
  `SessionAttachmentRuntime`. Attachment downloads and mutations now use
  independent `HermesAttachmentReading` and `HermesAttachmentMutating`
  capabilities; the mutation runtime additionally receives exact
  `HermesPromptServing` and `HermesDisconnectServing` capabilities.
  `SessionListModel` retains
  protected draft/mutation-marker persistence, optimistic presentation, and its
  sole ordered event router, stores only `HermesEventStreaming`, has no optional
  repository escape hatch, and shrinks from 6,413 to 6,278 lines. Six direct
  runtime tests and the complete architecture-boundary suite pass in
  `build/DerivedData-SessionAttachmentRuntime/Logs/Test/Test-Nile-2026.08.08_04-23-20-+0200.xcresult`;
  the full 537-test unit/protocol suite passes with zero failures or skips in
  `build/DerivedData-SessionAttachmentRuntime/Logs/Test/Test-Nile-2026.08.08_04-24-45-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionAttachmentRuntime`.
- Extracted protected composer-record ownership, monotonic revision/timestamp
  generation, replaceable debounce tasks, immediate flushes, exact-claim
  tombstone/rollback, and missing-owner migration CAS into the initial 360-line
  `SessionDraftPersistenceRuntime`, narrowed to `ComposerDraftStoring`.
  `SessionListModel` retains visible composer and operation-recovery projection
  but no longer stores the backend, persisted-record mirror, write tasks,
  timestamp sequencer, or migration records; it shrinks from 6,278 to 6,087
  lines and remains the sole ordered event router. Six direct runtime tests, the
  full model regression suite, and every architecture-boundary test pass in
  `build/DerivedData-SessionDraftPersistenceRuntime/Logs/Test/Test-Nile-2026.08.08_04-38-41-+0200.xcresult`;
  the full 544-test unit/protocol suite passes with zero failures or skips in
  `build/DerivedData-SessionDraftPersistenceRuntime/Logs/Test/Test-Nile-2026.08.08_04-40-21-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionDraftPersistenceRuntime`.
- Extracted protected photo-record and mutation-marker mirrors, monotonic
  revision/timestamp generation, restoration/quarantine ownership, exact-marker
  CAS transitions, missing-owner multi-record migration, and replaceable
  recovered-edit retries into the 592-line
  `SessionAttachmentPersistenceRuntime`, narrowed to
  `AttachmentDraftStoring`. `SessionListModel` retains visible recovery and
  transcript orchestration plus the sole ordered event router, but no longer
  stores the backend, protected-state mirrors, timestamp sequencer, quarantine
  flags, or edit generations; it shrinks from 6,087 to 5,717 lines. Six direct
  runtime tests, the full model regression suite, and every architecture-boundary
  test pass in
  `build/DerivedData-SessionAttachmentPersistenceRuntime/Logs/Test/Test-Nile-2026.08.08_05-03-21-+0200.xcresult`;
  the full 551-test unit/protocol suite passes with zero failures or skips in
  `build/DerivedData-SessionAttachmentPersistenceRuntime/Logs/Test/Test-Nile-2026.08.08_05-04-11-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionAttachmentPersistenceRuntime`.
- Consolidated the former draft-recovery coordinator with the per-owner text
  projection, one-shot restoration flags, recovery generations, and deferred
  notices in the 268-line `SessionComposerRuntime`. Prompt, steer, command, and
  attachment failures now use one admission-ordered recover transition before
  the model independently persists and presents the result. `SessionListModel`
  no longer stores composer maps or recovery state, remains the sole ordered
  event router, and shrinks from 5,717 to 5,711 lines. Six direct runtime tests
  and every architecture-boundary test pass in
  `build/DerivedData-SessionComposerRuntime/Logs/Test/Test-Nile-2026.08.08_05-12-34-+0200.xcresult`;
  all 129 model integration tests pass in
  `build/DerivedData-SessionComposerRuntime/Logs/Test/Test-Nile-2026.08.08_05-14-11-+0200.xcresult`;
  the full 553-test unit/protocol suite passes with zero failures or skips in
  `build/DerivedData-SessionComposerRuntime/Logs/Test/Test-Nile-2026.08.08_05-19-44-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionComposerRuntime`.
- Split the former 840-line `SessionListFixture` across a 251-line session
  directory catalog, a 265-line control-state fixture, and a 330-line
  transcript/media fixture without changing any payload value or initializer
  contract. The reusable gateway, protected-store, voice, speech, and cache
  doubles also moved out of the 6,715-line `SessionListModelTests` source into a
  dedicated 1,207-line support file, reducing the behavior-test source to 5,510
  lines. Architecture boundaries cap all three production fixture sources,
  prevent test doubles from returning to the behavior source, and retain the
  single ordered event router. All 129 model tests plus 24 architecture tests
  pass in
  `build/DerivedData-SessionFixtureSplit/Logs/Test/Test-Nile-2026.08.08_05-29-10-+0200.xcresult`;
  the full 554-test unit/protocol suite passes with zero failures or skips in
  `build/DerivedData-SessionFixtureSplit/Logs/Test/Test-Nile-2026.08.08_05-30-12-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionFixtureSplit`.
- Extracted the missing-owner create transaction from `SessionListModel` into
  the 192-line `SessionCreationDraftRuntime`. The runtime now owns immutable
  creation plans, ordinary-photo promotion to durable recovered-marker
  authority, exact-CAS text/photo/marker retargeting, and the accepted in-memory
  composer handoff; the model retains the create/list network sequence, visible
  rollback presentation, immutable display/gateway fence, and sole ordered
  event router while shrinking from 5,711 to 5,578 lines. Four direct runtime
  tests, all 129 model integration tests, and all 25 architecture-boundary tests
  pass in `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_05-42-25-+0200.xcresult`
  and `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_05-41-38-+0200.xcresult`;
  the full 559-test unit/protocol suite passes without failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_05-44-02-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionCreationDraftRuntime`.
- Extracted process-relaunch photo-draft reconciliation from
  `SessionListModel` into the initial 425-line
  `SessionAttachmentRecoveryRuntime`. The
  runtime composes protected photo/text persistence, the per-owner composer
  projection, and read-only session navigation to own durable-history
  acceptance proof, stale-runtime quarantine, marker-authoritative edit
  rollback, and missing-owner recovery; it returns immutable presentation
  outcomes and never consumes stream events. The model retains visible
  presentation and the sole ordered event router while shrinking from 5,578 to
  5,278 lines. Six direct recovery tests, all 134 model integration tests, and
  all 26 architecture-boundary tests pass; the full 566-test unit/protocol suite
  passes without failures or skips, and the unsigned optimized generic-device
  Release build passes from
  `build/DerivedData-Release-SessionAttachmentRecoveryRuntime`.
- Extracted ordinary protected text-draft composition from `SessionListModel`
  into the 212-line `SessionDraftLifecycleRuntime`. The runtime now composes
  `SessionDraftPersistenceRuntime` with `SessionComposerRuntime` for record
  restoration, exact claim capture/flush/retirement and rollback,
  admission-ordered prompt/steer/command failure persistence, and offscreen
  notice routing through immutable presentation outcomes without consuming
  events. The model no longer retains or directly calls the lower-level draft
  persistence runtime, keeps only visible presentation and its sole ordered
  event router, and shrinks from 5,278 to 5,248 lines. Six direct lifecycle
  tests, all 134 model integration tests, and all 27 architecture-boundary tests
  pass; the full 573-test unit/protocol suite passes without failures or skips
  in `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_06-11-03-+0200.xcresult`,
  and the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-SessionDraftLifecycleRuntime`.
- Split the former 2,398-line `TranscriptView` source by responsibility into a
  255-line SwiftUI shell, an 810-line UIKit viewport/diffing controller, a
  launchpad/message-row surface, and a 697-line tool/todo-row source.
  The split preserves every non-import and non-access-control token while
  keeping the one viewport, scroll owner, row projection, accessibility
  identifiers, and rendering behavior intact. All 14 transcript projection and
  viewport tests plus all 28 architecture-boundary tests pass; the architecture
  suite now caps each source and prevents viewport, message, and tool ownership
  from collapsing back together. The full 574-test unit/protocol suite passes
  without failures or skips in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.08_06-20-38-+0200.xcresult`, and
  the unsigned optimized generic-device Release build passes from
  `build/DerivedData-Release-TranscriptSurfaceSplit`.
- Ported Android gateway endpoint parsing and WebSocket URL construction.
- Ported the strict JSON-RPC frame-envelope codec.
- Ported the complete immutable Android domain-model inventory and async
  `HermesRepository` operation contract.
- Added a production `URLSessionWebSocketTask` adapter and actor-isolated
  newline JSON-RPC client with connection generations, strict ready handshake,
  correlated requests, timeouts, cancellation, ordered signals, and stale-event
  suppression.
- Extracted the `/api/status` probe into an injectable cookieless ephemeral REST
  client. It matches Android's 404 legacy compatibility and otherwise requires
  the Boolean `auth_required` field before selecting an authentication path.
  Hermes's loopback `auth_required: false` mode remains protected by its
  process-lifetime dashboard session token and fails closed when that token is
  blank.
- Bounded every ordinary untrusted HTTP document before decoding: status,
  WebSocket-ticket, and best-effort logout responses use a 64 KiB cap, while
  stored history, stored-session metadata, and analytics use a 32 MiB cap.
  Existing smaller attachment, voice, transcription, and synthesis limits stay
  operation-specific. Oversized successful responses now fail closed without
  losing safe HTTP/auth-expiry classification.
- Hardened usage and statistics decoding against malformed or extreme numeric
  counters. Integer conversion now rejects unrepresentable JSON values,
  externally reported percentages clamp to 0...100, and derived context,
  token, heatmap, streak, session, and API-call totals saturate instead of
  trapping on overflow.
- Added versioned gateway-profile persistence: non-secret metadata is atomically
  written under Application Support with
  `completeUntilFirstUserAuthentication`; reusable tokens are stored in
  non-synchronizing `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain
  items behind versioned credential pointers. Cross-store updates preserve the
  prior pointer if metadata commit fails, while a persisted cleanup ledger
  retries post-commit Keychain deletion after interruption. Device-bound
  metadata is excluded from backup.
- Connected onboarding and startup restoration to the production transport.
  Profiles are saved only after the `gateway.ready` handshake, startup tokens
  never enter form state, and failed handshakes do not persist credentials.
- Added saved-profile list, selection, confirmed removal/fallback, retry,
  loading, and connected states to the currently implemented surface.
- Ported the Android session-list, live-session, stored-history, active-status,
  session-info, context-category, tool-result, subagent-event, goal-status-event,
  compaction-event, and blocking-prompt wire projections. Stored history removes
  private goal turns and protocol scaffolding, preserves tool-call context,
  converts private model markers, strips ANSI, and fails closed on malformed
  blocking payloads.
- Added the first production `TuiGatewayRepository` operations for ordered events,
  listing, opening, creating, renaming, active statuses, prompt submission,
  steering, and interruption with the Android methods, parameter names, null
  policy, and timeout policy.
- Replaced the temporary connected placeholder with a shared-repository session
  model and native session shell. The shell ports the 96-point collapsed rail,
  180×68 session pills, in-place expanding list, search, source labels, runtime
  priority, needs-input treatment, pinning, create control, and exact graphite
  tokens. Terminal-owned CLI/TUI rows are selected read-only without issuing
  `session.resume`; the Claim/history surface remains a later slice.
- The session model consumes the repository's single ordered event stream,
  updates busy/needs-input state, surfaces terminal connection failure, and
  clears old gateway session state before exposing data from another profile.
- Phase-one mid-turn restoration now keeps a bounded, memory-only timeline for
  up to eight live sessions. Events for a session continue updating its cached
  assistant segments, tool results, todos, and status while another session is
  visible; switching back restores that timeline immediately and reconciles it
  with `session.resume`. Returning from the background or another app surface
  also reconciles the visible turn, while the five-second status poll repairs a
  missed completion for an attached turn. The transport now projects Hermes's
  `message.interim` frames as segment boundaries instead of dropping them.
- Hermes still exposes only flattened `inflight.assistant` text through
  `session.resume`; it does not provide the full ordered tool/event backlog for
  a turn already in progress. The cache therefore preserves complete structure
  only for events observed by this app process. A process relaunch can recover
  authoritative messages and current inflight text, but not unseen tool detail.
- Added exact proxy-aware dashboard REST reads for stored-session source and
  history on legacy-token profiles. Dynamic identifiers are encoded as single
  path segments, requests are cookieless, 401/auth expiry is explicit, response
  objects are strict, and Android retryability is preserved.
- Ported Android terminal ownership memory across partial pages and reconnects,
  durable read-only history routing, five-second list/status/history refresh,
  and generation fencing for late source/history responses.
- Ported the CLI/TUI read-only bar and explicit Claim confirmation. Claim
  rechecks runtime status immediately before mutation, blocks
  starting/working/waiting terminals, and only overrides remembered terminal
  ownership after a successful resume.
- Ported one shared stored/live transcript projection. It preserves Android's
  historical ID hashing, chronological assistant segments, tool updates and
  grouping, outcomes, todos, diffs, active-plan lifecycle, image markers,
  assistant-only MEDIA attachments, standing-goal/system rows, and the
  post-completion authoritative-history refresh needed after attaching
  mid-turn.
- Added the native transcript renderer with Android-aligned bottom anchoring,
  message hierarchy, user bubble, selectable assistant prose, copy action,
  cursor-free incremental assistant rendering, the original inline grouped-tool
  card treatment with downward-only disclosure on one stable scroll subtree,
  in-place repeatable expansion/collapse, and a transient tap-position ripple,
  terminal output, todos, diffs, images, attachments, and active plans.
- Made the shared elbow detail rule draw without participating in vertical
  measurement, so the live plan is a compact current-task row when collapsed
  and a content-sized checklist when expanded. Short bottom-aligned transcripts
  now retain their pre-expansion top inset so grouped actions disclose downward
  instead of jumping toward the header. A deterministic five-task fixture and
  focused XCUITest enforce both geometries and preserve transcript space. Long
  current-action summaries now take their natural multiline height instead of
  being clipped to a one-line tail ellipsis while the group is collapsed.
- Replaced the page-wide session-switch spinner with a compact header status,
  a briefly retained disabled/dimmed outgoing transcript, and a minimal
  transcript-shaped skeleton when no renderable content exists. Incoming rows
  use a short 4-point fade/settle sequence, while Reduce Motion removes the
  movement; focused XCUITests retain screenshots and accessibility hierarchies
  for retained, empty, and settled states.
- Ported Android's structural Markdown behavior for headings, paragraphs,
  bullets, numbered lists, quotes, rules, fenced code (including unclosed
  fences), and pipe tables.
- Replaced terminal-style pipe-table strings with an adaptive native data grid.
  It preserves inline Markdown and source alignment, wraps real cells, exposes
  row/column semantics, keeps overflow horizontally scrollable, and switches to
  labeled stacked fields at accessibility content sizes. Streaming tables defer
  incomplete separator and row fragments until they are structurally complete.
- Added Android's exact language allowlist, keyword sets, streaming-tolerant
  tokenization, quote-aware trailing-comment split, and syntax
  keyword/string/value/comment colors for fenced code.
- Added per-gateway/per-session transcript position ownership, first-content
  tail placement, gesture-only anchor release, fling settlement, parked-reader
  preservation across external appends and session switches, fresh-user
  re-anchoring, viewport/async-size re-pinning, and the Android-copy 48-point
  contextual jump control.
- Ported the Android floating multiline composer hierarchy and stable selectors,
  including active status/timer presentation, idle Send, in-turn steering,
  pending steer rows, Stop, blocked-input placeholder behavior, Android vector
  glyphs, and the model/speaker/context telemetry strip.
- Added restrained iOS touch-down feedback to the composer's explicit action
  surfaces: a transform-only 0.96 scale with a fast damped spring and subtle
  fade. The complete composer glass also lifts to 1.04 scale with a stronger
  shadow while hovered and briefly when the field gains focus. The surface does
  not install a competing touch recognizer, so native text-field focus and
  keyboard presentation begin on the first tap. Once that focus tap has
  completed, the field arms a transparent local toggle so a second field tap
  dismisses the keyboard and the following tap restores it immediately. Session
  selection/opening explicitly clears the outgoing focus binding, preventing a
  stale logical focus from consuming the first tap when the incoming composer
  appears. A clear activation layer behind the composer content makes unused
  glass around the field focus it too, while attachment scrolling and every
  nested action remain in front and independent. Reduce Motion removes scaling
  and animation in favor of non-moving visual feedback; layout, accessibility
  semantics, and 44-point-or-larger hit regions remain unchanged.
- Ported the prompt/steer delivery reducers: prompt sends add a non-pending
  optimistic user row, steering adds a pending ghost, rejected mutations restore
  text ahead of edits typed while the request was outstanding, offscreen owners
  retain one-shot notices, and uncertain connection failures warn against
  duplicate retries.
- Added generation-fenced interrupt settlement so a late Stop acknowledgement
  cannot stop the next turn.
- Added protected ordinary text-draft persistence with versioned per-gateway and
  per-session revisions, stale/conflicting-write rejection, replaceable 350 ms
  writes, scene-phase flush, backup exclusion, process-recreation restoration,
  pre-send durability, acknowledgement tombstones, and gateway-removal cleanup.
- Ported camera/gallery photo intake and Android's off-main 1568-pixel,
  JPEG-quality-85 preparation contract. Pending bytes become visible only after
  their protected per-owner draft revision commits; the composer matches the
  Android 64×64 thumbnail strip, 10-point radius, 22-point remove control, and
  photo-only Send behavior.
- Added exact `image.attach_bytes`/`image.detach` repository calls and an
  attachment delivery coordinator that correlates submit responses with
  `message.start`, retains known server-path leases until consumption proof,
  detaches definite rejections, and quarantines ambiguous outcomes by exact
  gateway/session/runtime owner.
- Added a protected, backup-excluded attachment recovery envelope with atomic
  draft-to-marker handoff, upload/prompt stage compare-and-swap, authoritative
  empty tombstones, process recreation checks against the old live runtime, and
  durable-history acceptance proof before a marker can be retired.
- Added bounded attachment downloads with manual credential-safe redirects,
  two-at-a-time 2 MiB image previews, native image/file transcript cards, and a
  protected 12-entry/96 MiB Quick Look/share cache. Full opens are capped at
  32 MiB and late viewer work is selection/generation fenced. Long sanitized
  filenames retain their extension inside the 120-character cache limit so
  Quick Look and share targets receive a usable type hint.
- Ported exact slash-command discovery, completion, and execution contracts,
  including strict catalog/result decoding, the Android mobile allow/block and
  native-command policy, bounded aliases, source-scoped completion, transcript
  command rows, and definite-versus-uncertain draft recovery.
- Ported the Android session model settings sheet with searchable provider
  groups, current-model expansion, capability/pricing labels, unavailable/free
  tier states, session-scoped reasoning, expensive-model confirmation, progress,
  retry, and error states.
- Added gateway-scoped protected model pins with provider-aware versioned
  records, legacy-pin resolution, unresolved-pin removal, backup exclusion,
  gateway-removal tombstones, and an app-scoped FIFO that preserves rapid tap
  order while fencing late publication across gateways.
- Added gateway-scoped protected session pins with versioned deterministic
  records, backup exclusion, after-first-unlock protection, relaunch restore,
  gateway-removal tombstones, optimistic UI, FIFO desired-value writes, and
  matching-intent rollback that is fenced across gateway changes.
- Ported the Android Nile colors, radii, and motion constants. The
  product-approved river mark now intentionally replaces the earlier exact
  Android N-mark geometry in the app icon and visible in-app branding.
- Made the pinned Roboto typography roles scale relative to Apple text styles,
  added Dynamic Type-scaled gateway fields and primary controls without
  changing their default Android dimensions, propagated native Reduce Motion
  through root and feature animation policy, and added explicit
  Name → URL → secure-token keyboard progression.
- Added exact authenticated Hermes dashboard contracts for transcription,
  synthesis, and global voice configuration, with strict request bounds,
  response codecs, safe error detail, and unsupported-endpoint handling.
- Ported microphone capture through `AVAudioEngine`, Android's RMS VAD and
  pause/timeout behavior, canonical PCM16 WAV encoding, cancellation-safe
  transcription, and draft-preserving ordinary voice input.
- Added sanitized, natural-boundary, UTF-16-safe chunked spoken replies with
  sequential synthesis, cancellable native playback, explicit opt-in UI, and
  owner fencing across backgrounding, gateway/session switches, and new turns.
- Ported the Hermes voice Settings sheet with Android's provider/current/preset/
  custom/global-warning states and generation-fenced load/apply behavior.
- Ported Talk mode as a full-screen Android-aligned surface with private partial
  speech, exactly-once utterance submission, strict turn admission, pause/resume,
  interruption, blocking-prompt handling, background safety, speech playback,
  relisten, and stale/uncertain outcome fencing.
- Ported standing goals and turn budgets with exact status/set/pause/resume/clear
  RPCs, strict codecs, gateway/session/generation fencing, profile-default
  budgets, quick starts, and active/paused/terminal lifecycle controls.
- Added exact session-usage and dashboard-statistics reads with strict codecs,
  owner-fenced polling, categorized context/compaction presentation, 7/30/90-day
  ranges, momentum and aggregate summaries, and the recent-activity heatmap.
- Ported delegated-agent lifecycle handling with strict status and snapshot
  contracts, sparse progress merging, terminal-state stickiness, parent-turn
  settlement, bounded settled history, reconnect reconciliation, snapshot
  recovery, interrupt/open-child controls, and active/settled transcript
  presentations.
- Ported background-turn ownership for normal, attachment, goal, Talk, and
  remote-command turns with exact gateway/stored/live targets, FIFO handoff,
  uncertain-delivery retention, retryable-loss retention, terminal settlement,
  reconnect-only status reconciliation, and gateway-replacement cleanup.
- Added iOS's finite `beginBackgroundTask` continuation with mandatory exact
  expiration requeue, generic privacy-preserving completion notifications,
  app-delegate notification routing, one-time Android-copy permission
  education, and fail-closed saved-gateway/stored-session reopening.
- Ported gated dashboard authentication around one shared persistent WebKit
  cookie store. The current bounded sign-in sources independently own SwiftUI
  presentation, persistent WebKit lifecycle, and Foundation-only fail-closed
  navigation policy. The flow exposes the current origin, blocks same-origin
  path escapes and credentialed/malformed targets, confirms external HTTPS
  navigation, retains HttpOnly cookies, and retries the pending connection
  before saving the profile.
- Added fresh single-use WebSocket ticket minting, serialized Set-Cookie
  rotation, exact safe 401 login handling, profile-scoped REST cookie
  attachment, cookieless external downloads, best-effort host-scope logout,
  selective local cleanup, and pre-credential rejection of overlapping
  same-host gateway scopes.
- Ported the session shell's app-owned Material add, close, search, edit,
  statistics, settings, and custom push-pin paths instead of substituting SF
  Symbols.
- Ported the Android launcher-vector geometry into a reproducibly rendered iOS icon.
- Added a native Settings/gateway onboarding surface and real `/api/status`
  probe. The last-gateway removal state retains the pinned Android empty-state
  copy after its secure asynchronous cleanup finishes.
- Added the Android accessibility identifiers used by the implemented controls.
- Added focused unit/protocol, standard XCUITest, and dedicated
  accessibility-extra-large XCUITest coverage.
- Built, installed, launched, and visually inspected the app on iPhone 17 Pro,
  iOS 26.5 Simulator.

## Verification evidence

Current transcript-checkpoint results:

- Xcode 26.6, Swift 6.3.3, iOS Simulator 26.5
- `NileTests`: 138 passed, 0 failed
- `NileUITests`: 4 passed, 0 failed, including grouped-tool expansion and
  assistant-copy interaction
- signed combined exact-tree run: 142 passed, 0 failed in
  `TranscriptSignedFinal2.xcresult`
- an unsigned diagnostic run passed 140 tests and failed only the real-Keychain
  test because disabling code signing also removes the simulator Keychain
  entitlement; the normally signed lane above is authoritative
- Debug static analysis passed from fresh `DerivedData-TranscriptAnalyze2`
- unsigned generic-device Release build passed from fresh
  `DerivedData-TranscriptRelease2`; the built Release plist has no
  `NSAppTransportSecurity` override
- focused stored-session/ownership slice: passed in
  `StoredSliceFocused5.xcresult`
- Debug static analysis: passed from fresh
  `DerivedData-StoredAnalyzeExactFinal`
- unsigned generic-device Release clean build: passed from fresh
  `DerivedData-StoredReleaseExactFinal`
- built Debug ATS policy: `NSAllowsArbitraryLoads = true`
- built Release ATS policy: no `NSAppTransportSecurity` override
- `build/TestResults/Unit.xcresult`
- `build/TestResults/UI2.xcresult`
- `build/TestResults/Foundation.xcresult`
- `build/TestResults/Domain.xcresult`
- `build/TestResults/TransportUnit.xcresult`
- `build/TestResults/TransportFull2.xcresult`
- `build/TestResults/ProfileUnit.xcresult`
- `build/TestResults/ProfileUI.xcresult`
- `build/TestResults/ProfileUnitFinal4.xcresult`
- `build/TestResults/ProfileUIFinal3.xcresult`
- `build/TestResults/SessionUnitFinal.xcresult`
- `build/TestResults/SessionUnitFinal2.xcresult`
- `build/TestResults/SessionUnitFinal3.xcresult`
- `build/TestResults/SessionUnitFinal4.xcresult`
- `build/TestResults/SessionUnitFinal6.xcresult`
- `build/TestResults/SessionUIFinal.xcresult`
- `build/TestResults/SessionUIFinal2.xcresult`
- `build/TestResults/SessionUIFinal3.xcresult`
- `build/TestResults/SessionUIFinal7.xcresult`
- `build/TestResults/SessionUIVisual2.xcresult`
- `build/TestResults/SessionUIVisual3.xcresult`
- `build/TestResults/SessionUIVisual4.xcresult`
- `build/TestResults/SessionPinInteraction2.xcresult`
- `build/TestResults/StoredSliceFocused5.xcresult`
- `build/TestResults/StoredSliceUIFinal.xcresult`
- `build/TestResults/FullUnits-StoredSlice.xcresult`
- `build/TestResults/FullUI-StoredSlice.xcresult`
- `build/TestResults/FullUnits-StoredSliceFinal.xcresult`
- `build/TestResults/FullUI-StoredSliceFinal.xcresult`
- `build/TestResults/StoredSliceAllExactFinal.xcresult`
- `build/TestResults/TranscriptFinal.xcresult`
- `build/TestResults/TranscriptSignedFinal2.xcresult`
- `build/DerivedData-KeychainSigned/Logs/Test/` (signed real-Keychain rerun)
- `build/checkpoints/onboarding-foundation.png`
- `build/checkpoints/profile-settings-stable.png`
- `build/checkpoints/session-ui-visual2/` (collapsed and expanded session shell)
- `build/checkpoints/session-ui-visual3/` (Material-path visual rerun)
- `build/checkpoints/session-ui-visual4/` (final source-aligned search and
  workspace-branding rerun)
- `build/checkpoints/session-pin-interaction2/` (final exact-source independent
  pin/open hit-target rerun)
- `build/checkpoints/stored-session-final/` (final read-only working bar and
  blocked Claim confirmation)
- `build/checkpoints/transcript-final/` (collapsed transcript, expanded tool
  group, assistant-copy interaction, expanded session shell)

Current composer-checkpoint evidence:

- focused idle/working/stopping/needs-input composer activity XCUITest passed
  with four inspected retained screenshots and accessibility hierarchies in
  `build/TestResults/ComposerActivity2.xcresult`; geometry assertions prove the
  composer bottom edge and text-field midpoint do not move while the 36-point
  integrated row appears
- signed exact-tree full run: 164 passed, 0 failed in
  `build/TestResults/ComposerCheckpointFinal.xcresult`
- focused composer/recovery/gateway persistence suite: 46 passed, 0 failed in
  `build/DerivedData-DraftPersistence/Logs/Test/Test-Nile-2026.07.23_23-34-47-+0200.xcresult`
- selector-driven composer send/steer/stop XCUITest passed in
  `build/DerivedData-ComposerUI/Logs/Test/Test-Nile-2026.07.23_23-20-05-+0200.xcresult`
- tactile press-state unit coverage and the selector-driven composer
  send/steer/stop scenario passed on iPhone 17 Pro/iOS 26.5; the latter
  retained fresh collapsed, interaction, and expanded screenshots and verifies
  the dynamic Send and Stop hit regions remain at least 44 points:
  `build/DerivedData/Logs/Test/Test-Nile-2026.07.25_20-29-26-+0200.xcresult`
  and
  `build/DerivedData-Tactile/Logs/Test/Test-Nile-2026.07.25_20-42-44-+0200.xcresult`
- focused composer-surface hover/focus motion-policy coverage passed in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_16-48-42-+0200.xcresult`;
  first-tap keyboard presentation followed by field-tap dismissal and immediate
  field-tap reopening passed in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_16-55-41-+0200.xcresult`;
  four consecutive scroll-dismiss/reopen cycles passed in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_16-49-30-+0200.xcresult`;
  stale outgoing focus, a first broad-surface tap at 90% height after switching,
  focused-field toggling, and four repeated switched-session cycles pass in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_20-08-58-+0200.xcresult`;
  attachment removal/photo-only send and send/steer/stop control isolation pass
  in `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_20-11-06-+0200.xcresult`
- unsigned generic-device Release build passed from
  `build/DerivedData-ComposerFocusRelease`
- Debug static analysis passed from `build/DerivedData-ComposerFocusAnalyze`
- unsigned generic-device Release build passed from
  `build/DerivedData-ComposerRelease`; the built Release plist contains no
  `NSAppTransportSecurity` override
- the immutable Android/Hermes oracle verification passed on this exact tree
- inspected Simulator capture:
  `build/checkpoints/composer-ui/5F69196E-0995-45AD-98C1-CADA713F5518.png`

Current blocking-input checkpoint:

- implemented Android-aligned clarification, approval, sudo, secret, and
  malformed-request cards, including compact resolved rows and exact safety copy
- added typed `clarify.respond`, `approval.respond`, `sudo.respond`, and
  `secret.respond` RPCs with strict response validation
- added request deduplication, runtime/stored-session binding, per-runtime
  approval FIFO, pinned expiry, status-poll watermarks, session-switch isolation,
  stop/completion finalization, and definite-versus-uncertain failure handling
- response values are absent from observable/persisted state; masked
  privacy-sensitive fields clear on submit, dismiss, session switch, prompt
  invalidation, or backgrounding
- signed exact-tree full run: 184 passed, 0 failed (176 unit/protocol and 8 UI)
  in `build/TestResults/BlockingCheckpointFinal.xcresult`
- focused coordinator/repository/model suite passed 52 tests
- 4 selector-driven blocking-input XCUITests passed as part of the 8-test UI
  suite, covering explicit
  clarification continuation, approval FIFO/permanent confirmation, masked
  sudo/secret entry, and malformed non-actionable requests
- inspected Simulator capture:
  `build/checkpoints/blocking-prompts/approval-fifo-settled.png`
- Debug static analysis passed from `build/DerivedData-BlockingAnalyze`
- unsigned generic-device Release build passed from
  `build/DerivedData-BlockingRelease`; the built Release plist contains no
  `NSAppTransportSecurity` override
- the immutable Android/Hermes oracle verification passed on this exact tree

Current attachment checkpoint:

- signed exact-tree full run: 223 passed, 0 failed (214 unit/protocol and 9 UI)
  in `build/TestResults/AttachmentCheckpointFinal.xcresult`
- the attachment UI test covers the pending-photo strip, two real thumbnails,
  native media/file cards, removal selectors, and photo-only Send
- inspected Simulator capture:
  `build/checkpoints/attachments-final/233E6187-6ABE-44C6-9BF0-71FE821D893E.png`
- Debug static analysis passed from `build/DerivedData-AttachmentAnalyze`
- unsigned generic-device Release build passed from
  `build/DerivedData-AttachmentRelease`; the built Release plist contains no
  `NSAppTransportSecurity` override
- the immutable Android/Hermes oracle verification passed on this exact tree

Current slash/model/reasoning checkpoint:

- signed exact-tree full run: 250 passed, 0 failed (240 unit/protocol and 10 UI)
  in `build/TestResults/CommandModelCheckpointFinal2.xcresult`
- exact repository, policy, session-state, persistence, FIFO ordering, stale
  gateway, malformed-result, confirmation, and uncertain-outcome tests passed
- the model mutation codec accepts the installed pre-confirmation Hermes
  server's exact `key`/`value`/`warning` success acknowledgement while keeping
  the pinned confirmation-aware response strict; partial confirmation metadata
  and scoped responses without it still fail closed
- physical picker interaction is restored: Compose-backed labels do not
  intercept SwiftUI button taps, provider/model rows expose rectangular hit
  surfaces, and the initially expanded current provider can still be collapsed;
  the selector-driven XCUITest physically toggles current and alternate
  providers and taps an alternate model through to switch progress
- the composer model pill now preloads the same session-scoped Hermes catalog
  without presenting the full picker and opens a native hierarchical iOS menu:
  authenticated providers contain only selectable model actions, the current
  provider/model are checked, retry and full-settings actions remain available,
  and a selector-driven XCUITest opens the provider submenu and starts a model
  switch without presenting the full picker
- the selector-driven model picker XCUITest performs real unresolved unpin and
  provider-catalog pin mutations in addition to search and dismissal
- inspected Simulator capture:
  `build/checkpoints/model-picker-final/3AA2EC36-6E0C-4164-91FF-87F8699E9A11.png`
- Debug static analysis passed from `build/DerivedData-CommandModelAnalyze2`
- unsigned generic-device Release build passed from
  `build/DerivedData-CommandModelRelease2`; the built Release plist contains no
  `NSAppTransportSecurity` override
- the immutable Android/Hermes oracle verification passed on this exact tree

Current speech/Talk checkpoint:

- exact-tree signed combined run: 294 passed, 0 failed in
  `build/TestResults/SpeechTalkCheckpointFinal.xcresult` (281 unit/protocol
  tests and 13 UI tests)
- full signed unit/protocol run: 281 passed, 0 failed in
  `build/TestResults/SpeechTalkUnitFull.xcresult`
- full selector-driven UI lab: 13 passed, 0 failed in
  `build/TestResults/SpeechTalkUIFull.xcresult`
- focused repository, PCM/VAD/WAV, transcription cancellation, voice settings,
  spoken-reply, Talk ownership/race/rollback/background/blocking tests passed
- inspected Simulator captures for Hermes voice configuration and Talk listening
  under `build/checkpoints/speech-talk-ui-full/`
- Debug static analysis passed from `build/DerivedData-SpeechTalkAnalyze`
- unsigned generic-device Release build passed from
  `build/DerivedData-SpeechTalkRelease`; the built Release plist contains no
  `NSAppTransportSecurity` override and includes the microphone usage string
- the immutable Android/Hermes oracle verification passed after these checks

Current goals/usage/delegation checkpoint:

- full signed unit/protocol run: 308 passed, 0 failed in
  `build/GoalUsageDelegationUnitFull3.xcresult`
- six selector-driven goal, usage, statistics, and delegation UI scenarios
  passed in `build/GoalUsageDelegationUIFinal.xcresult`
- focused repository, codec, coordinator, lifecycle, reconciliation, snapshot,
  polling, fencing, interrupt, and stale-owner tests passed
- inspected Simulator captures under
  `build/checkpoints/goal-usage-delegation-ui-final/`

Current gated-authentication checkpoint:

- full signed unit/protocol run: 318 passed, 0 failed in
  `build/AuthUnitFullFinal2.xcresult`
- focused authentication and existing gateway/profile regression: 43 passed,
  0 failed in `build/AuthFocused2.xcresult`
- two selector-driven embedded sign-in scenarios passed in
  `build/AuthUIFinal.xcresult`, including real WebKit delegate enforcement for
  external-origin confirmation and same-origin path escape rejection
- the focused tests exercise fresh tickets, 401 login safety, scope collisions,
  cookieless external access, logout/cleanup, retained pending setup, navigation
  policy, cancellation/rotation races, and real WebKit
  HttpOnly/prefix/path cookie behavior
- inspected Simulator capture:
  `build/checkpoints/auth-ui-final/742790E2-A5ED-4530-B517-EFF80FE9A42C.png`
- Debug static analysis passed from `build/DerivedData-AuthAnalyzeFinal`
- unsigned generic-device Release build passed from
  `build/DerivedData-AuthReleaseFinal`; the built Release plist contains no
  `NSAppTransportSecurity` override

Current reconnect/offline/auth-expiry checkpoint:

- full signed unit/protocol run: 328 passed, 0 failed in
  `build/ReconnectUnitFullFinal2.xcresult`
- full selector-driven UI regression: 22 passed, 0 failed in
  `build/ReconnectUIFullFinal3.xcresult`
- first-wins `NWPathMonitor`-gated retry with Android's immediate attempt,
  quarter-spread jitter, exponential 1-to-20-second cap, and foreground restart
- saved-profile and transcript retention across retryable loss; composer/model
  controls remain unavailable until a fresh socket and selected-session restore
  both succeed
- gated dashboard 401 events are constrained to the active saved profile and a
  safe same-origin/path login URL, close the socket, and reopen sign-in without
  discarding profile context
- focused coordinator/setup/session/authentication tests passed in
  `build/ReconnectIntegrationFocused3.xcresult` and
  `build/AuthExpiryFocused2.xcresult`
- the selector-driven offline/reconnecting/restoring scenario passed both its
  focused and full UI lanes; inspected captures are under
  `build/checkpoints/reconnect-ui/`
- Debug static analysis passed from
  `build/DerivedData-ReconnectAnalyzeFinal2`
- unsigned generic-device Release build passed from
  `build/DerivedData-ReconnectReleaseFinal2`; the built Release plist targets
  iOS 17, includes the microphone usage string, and contains no
  `NSAppTransportSecurity` override
- the immutable Android/Hermes oracle verification passed after project
  regeneration and the final build gates

Current background-turn/notification checkpoint:

- full signed unit/protocol run: 352 passed, 0 failed, 0 skipped in
  `build/BackgroundUnitFull2.xcresult`
- full selector-driven UI regression: 23 passed, 0 failed, 0 skipped in
  `build/BackgroundUIFull1.xcresult`
- focused exact-target, FIFO/error/expiration, foreground, privacy,
  permission-education, reconnect-only reconciliation, session lifecycle, and
  fail-closed notification-route policy tests passed
- the Android-copy notification education scenario passed in the full UI lane;
  its inspected 1206 × 2622 capture is under
  `build/checkpoints/background-notification-ui/`
- Debug static analysis passed from
  `build/DerivedData-BackgroundAnalyze`
- the optimized unsigned generic-device Release build passed from
  `build/DerivedData-BackgroundRelease`; the built plist targets iOS 17,
  includes the microphone usage string, and contains no
  `NSAppTransportSecurity` override
- project regeneration, `git diff --check`, and the immutable Android/Hermes
  oracle verification passed after the final source changes

Current transcript scroll/syntax checkpoint:

- full signed unit/protocol run: 361 passed, 0 failed, 0 skipped in
  `build/TranscriptScrollUnitFull1.xcresult`
- full selector-driven UI regression: 24 passed, 0 failed, 0 skipped in
  `build/TranscriptScrollUIFull1.xcresult`
- seven focused scroll-policy tests cover first-content tail placement,
  external-append preservation, fresh-user re-anchoring, gateway/session owner
  isolation, exact offset restoration, programmatic positioning/jump behavior,
  and the Kotlin-compatible UTF-16 owner key
- seven Markdown tests cover structural parsing plus exact
  keyword/string/value/comment highlighting, comment markers inside strings,
  streaming fences, and unknown-language passthrough
- the selector-driven long-history scenario verifies gesture detachment,
  independent Alpha/Beta reading positions, restored parked content, explicit
  jump, send re-anchoring, and syntax rendering; inspected 1206 × 2622 captures
  are under `build/checkpoints/transcript-scroll-ui-final/`
- a deterministic multi-delta fixture now grows one assistant response through
  60 paragraphs, a streaming table transition, and a fenced code block. Its UI
  contract verifies bottom follow, deliberate detachment, continued growth
  while the keyboard resizes the viewport, stable parked content, and explicit
  reattachment without an empty transcript surface
- the separate source-copy production-shell tail is paired to a pinned Android
  capture with zero masks at SSIM `0.935771` and outlier fraction `0.028354`;
  exact colors and all four checked landmarks pass in
  `build/test-lab-results/20260725T040036Z-68713/`
- Debug static analysis passed from
  `build/DerivedData-TranscriptScrollAnalyze`
- the optimized unsigned generic-device Release build passed from
  `build/DerivedData-TranscriptScrollRelease`; the built plist targets iOS 17,
  includes the microphone usage string, and contains no
  `NSAppTransportSecurity` override
- project regeneration, `git diff --check`, and the immutable Android/Hermes
  oracle verification passed after the final source changes

Current visual-tooling and typography checkpoint:

- Added a dependency-free CoreGraphics/ImageIO screenshot comparer with strict
  SSIM, outlier, landmark, flat-color, crop, mask, and manual-review gates.
- Added regression fixtures proving narrow justified-mask acceptance, visible
  mismatch rejection, and broad-mask rejection.
- Corrected XcodeGen resource inclusion so the asset catalog, launcher icon,
  font, and license are copied into the app.
- Embedded the AOSP Android Roboto Classic 3.005 variable font pinned at commit
  `5d982bb4526f3e8a438a776619c060e1daf2f18f`; a hosted unit test verifies the
  regular, medium, semibold, and bold instances.
- Built the pinned Android Debug APK and captured the current clean and expanded
  Settings states on a disposable Pixel 6/API 35 AVD. This proved that the
  checked-in onboarding screenshot predates source commit `c9cb0c4`: current
  source has no Hermes Agent updater card and starts with the form collapsed.
  The historical screenshot remains a separate rejected fixture.
- Matched current Android Settings content order, panel geometry, Compose
  typography sizes/line heights/tracking, collapsed Add gateway button, expanded
  field geometry, inline cleartext warning, approval checkbox, and disabled
  insecure-connect state. Debug/LocalRelease use the iOS Simulator loopback
  `http://127.0.0.1:9119`; Release continues to default to HTTPS.
- Added `scripts/visual/capture-android.sh`, which verifies the pinned Debug APK
  hash, creates an isolated Pixel 6/API 35 AVD, fixes display and animation
  state, captures clean/form screenshots and accessibility hierarchies, and
  deletes the AVD on exit. Its 1206 × 2478 display and deterministic 72-pixel
  system bars yield the exact 1206 × 2334 app-owned viewport captured on iOS.
- Tracked the reproduced clean/form Android source baselines and their
  UIAutomator hierarchies under `scripts/visual/baselines/android/`. The clean
  and form PNG hashes are respectively
  `41d0873e1f5e4877f39f66169d0348c1300ac94e0bb9d3c52d26553133904db0`
  and `9dc1053b3f55d7ce3081efd437641434d4af3130efaed0d3c77cf967fde89065`.
- Added exact source-copy iOS clean/form fixtures and strict manifests for both.
  Flat-color samples pass with no mask. Comparer schema 2 derives 10 clean and
  13 form landmark coordinates, spans, and run sizes from bounded scans over
  the native cropped PNG pixels; reference/candidate probes must be identical,
  manifests cannot supply result coordinates, and a pixel-mutating self-test
  proves the independent landmark failure path.
- Reproduced Compose's greedy wrapping for the two affected multiline labels
  using an adaptive UIKit label with no line-break strategy, without forced
  production-string breaks. Calibrated small renderer tracking/glyph coverage,
  inside panel/button borders, the 64-point Material field slot around its
  56-point visible outline, floating-label/warning/action alignment, and
  disabled Material button colors.
- Reverse-engineered and reproduced the pinned Android text stack: Android
  FreeType 2.13.2 raster flags, HarfBuzz 8.2.2 shaping, Minikin word-piece and
  tracked-line behavior, whole-pixel Compose baseline cadence, and Skia A8
  gamma correction. The reproducible source-pinned build creates checked-in
  arm64-device and universal-Simulator static XCFramework slices with both
  upstream notices.
- Replaced onboarding's CoreText raster with the exact renderer while retaining
  scalable UIKit measurement, accessibility semantics, native editing/caret
  behavior, and transparent non-glyph pixels. Added deterministic version,
  invalid-input, tracked-wrap, transparency, and repeatability tests.
- The post-renderer development capture passes both strict manifests with no
  masks, the then-current strict SSIM/outlier thresholds, all 23
  image-derived landmarks,
  all flat colors, and accepted native-scale manual review. Clean reports SSIM
  `0.998730` and outlier fraction `0.000524`; expanded form reports SSIM
  `0.996220` and outlier fraction `0.001329`. Complete evidence is under
  `build/visual-dev-20260724T140426Z/`.
- Reproduced those exact clean/form results from accessibility-corrected commit
  `255c68f` in a fresh disposable Simulator at
  `build/test-lab-results/20260724T143404Z-28004`. The lane passed its comparer
  self-test, all strict gates and accepted native-scale manual reviews, no-crash
  check, all-file secret scan, and Simulator deletion.
- The corrected historical-screenshot comparison separately fails at SSIM
  `0.710951` and outlier fraction `0.232190`.
- The disposable exact-tree unit lane passed analyzer, 369/369 unit/protocol
  tests, and an optimized unsigned Release build with warnings as errors at
  `build/test-lab-results/20260724T170343Z-46394`, including the Simulator
  Keychain integration, hosted font-registration test, exact typography
  contracts, deterministic Android-renderer tests, and cleartext-approval
  revocation.
- The latest exact-tree selector-driven standard UI regression passed all 26
  tests in `build/test-lab-results/20260724T165612Z-38561`. The onboarding
  scenario proves
  collapsed clean state, local loopback default, inline cleartext approval,
  disabled/enabled connect transition, and retained clean/form screenshots.
  The model-picker scenario also proves that its Android-matched resting height
  contracts for the iOS keyboard so filtered model and pin actions remain
  reachable.
- The first post-renderer accessibility lane retained a real 37-point native
  editor semantic-frame failure at
  `build/test-lab-results/20260724T142733Z-21029`. Expanding the native editor
  and hiding its visual-only raster from accessibility fixed the defect; the
  corrected disposable large-text/reduced-motion/keyboard lane passed 1/1 at
  `build/test-lab-results/20260724T143222Z-26418`.
- Debug static analysis passed from
  `build/DerivedData-OnboardingSourceParityAnalyze`.
- A fresh two-architecture Debug Simulator build passed with Swift and Clang
  warnings promoted to errors in
  `build/DerivedData-OnboardingSourceParityWarnings`.
- The optimized unsigned generic-device Release build passed from
  `build/DerivedData-OnboardingSourceParityRelease`. Its packaged app contains
  the byte-identical pinned Roboto file, license, asset catalog, and
  `UIAppFonts` declaration, targets iOS 17, includes the microphone usage
  string, and has no `NSAppTransportSecurity` override.

Current disposable iOS/Hermes lab checkpoint:

- Added read-only `scripts/test-lab/doctor.sh` plus repository-owned
  `unit`, `ui`, `accessibility`, `visual`, `installer`, `smoke`, `full`, and
  `drive` orchestration.
- The lab creates and deletes a fresh iPhone 17 Pro/iOS 26.5 Simulator, uses
  temporary DerivedData and Hermes state, chooses a random loopback port, records
  every lane independently, exports `.xcresult` summaries/attachments, captures
  app logs, a final screen, and any new Nile crash report, and scans every
  retained file for both disposable and provider credentials.
- A fresh unmodified Hermes installation passed at exact commit
  `7441e3395f9db0d8319f43bfe07dfb222777101e` through the installer's
  hash-verified `uv.lock` path in
  `build/test-lab-results/20260724T071532Z-66378`.
- The current disposable unit lane passed Debug analysis, all 404
  unit/protocol tests, and the unsigned optimized Release build with warnings
  as errors in `build/test-lab-results/20260725T052222Z-46897`; its all-file
  secret scan passed, it produced no new crash report, and it deleted its fresh
  Simulator.
- The current disposable standard UI lane passed all 37 deterministic scenarios,
  exported its attachment manifest, passed its secret scan, and deleted its
  fresh Simulator in `build/test-lab-results/20260725T052628Z-50149`.
- The dedicated accessibility lane sets a disposable Simulator to
  accessibility-extra-large, proves scaled typography and reachable native
  controls with 44-point-or-larger semantic targets, reduced-motion
  propagation, keyboard Next/Done focus, and secure-value redaction, then
  restores the content size.
  It passed 1/1 and exported inspected screenshots plus a masked hierarchy in
  `build/test-lab-results/20260725T054549Z-67302`.
- The previous disposable visual lane captured both clean and expanded
  onboarding fixtures and correctly retained both then-failing comparisons in
  `build/test-lab-results/20260724T115014Z-89283`. The clean comparison reports
  SSIM `0.986563` and outlier fraction `0.010324`; the form comparison reports
  SSIM `0.952348` and outlier fraction `0.027576`. All 23 image-derived
  landmarks passed. This result is superseded by the passing committed
  disposable run at
  `build/test-lab-results/20260724T143404Z-28004`.
- Added a three-phase production XCUITest for invalid-token rejection,
  production persistence, read-only CLI discovery, observable persisted-history
  refresh, Claim, acknowledged model/reasoning changes, a real turn, interrupt,
  two-turn standing-goal completion, server outage, reconnect, and process
  relaunch restoration. The bundle compiles; it has not yet run with an
  OpenRouter key, so no smoke pass is claimed.
- Repaired the host's stale Homebrew Node binary; `node` is now 26.5.0 and
  npm/npx are 11.17.0. The Hermes lab nevertheless retains its own managed,
  temporary dependencies.

Build/test artifacts are ignored and are not completion evidence after the code
changes; final lanes must rerun on the exact final commit.

The user subsequently approved a wider visual margin for harmless
cross-platform rasterization and small spacing differences. The strict default
remains SSIM `>= 0.97`, outliers `<= 0.03` at an 18-level per-channel delta.
Explicitly reviewed native cross-platform presentations may use SSIM `>= 0.82`
and outliers `<= 0.10`. Both tiers keep landmarks within 2 points. Flat
app-owned colors, fixture state, visible content, and manual review remain
mandatory; paired-state comparisons continue to use zero masks unless a
narrowly allowed system-owned dynamic pixel requires one.

- Added a source-paired production-shell model-picker state on both platforms.
  The Android baseline comes from an exact-commit disposable clone with a
  tracked test-only instrumentation patch; the production source and pinned APK
  remain unchanged. The iOS fixture uses the real session shell, deterministic
  connected-session/model data, and the production overlay.
- Reproduced the Android picker geometry, session-only reasoning notice,
  current-model card, provider disclosure, selected model row, Material pin and
  close icons, Droid Sans Mono model labels, Material label-small supporting
  text, and dialog dimming. The formal zero-mask comparison passes at SSIM
  `0.976389`, outlier fraction `0.007127`, and mean absolute channel delta
  `0.864652`; all 13 landmarks and four exact flat-color checks pass.
- A full fresh AVD reproduction exposed and removed a transient 20-point
  status-bar inset from the first model-picker baseline. The canonical recipe
  now builds the unchanged app and test overlay together under one isolated
  debug certificate, completes `OK (1 test)`, and reproduces the popup directly
  below the verified 72-pixel status bar.
- Extended the disposable visual lane to capture and compare onboarding clean,
  onboarding form, and the production-shell model picker. The fresh run at
  `build/test-lab-results/20260724T164959Z-30802` passed all three comparisons,
  the comparer self-test, no-Nile-crash validation, all-file secret scan, and
  Simulator deletion.
- Added the exact-source standing-goal quick-start sheet as the fourth visual
  lane state. The Android recipe runs the pinned production-shell test, selects
  `Fix and verify` and 10 turns, and exports both roots. The iOS test proves the
  draft is preserved and the same controls mutate state. The final calibration
  passes without masks at SSIM `0.832805`, outliers `0.098630`, seven
  image-derived landmarks, and four exact flat-color samples under the approved
  native-presentation tier.
- Reproduced that four-state result on a disposable standard-content-size
  Simulator in `build/test-lab-results/20260724T175412Z-9023`. The lane passed
  setup, comparer self-test, all four comparisons, no-crash validation,
  all-file secret scan, and cleanup. Goal geometry is within `0.34` point at
  every checked landmark; the onboarding and model-picker metrics remain
  unchanged.
- Added source-identical empty-session launchpad quick starts. The iOS catalog
  selection matches Android's two-skill-plus-safe-registry policy, distinctness,
  fallback copy, three-row limit, and composer mutation. The active-goal
  XCUITest found and fixed a semantic-container defect that had overwritten the
  three button identifiers; the test now selects the first card by its stable
  identifier and proves the exact draft value.
- Added exact-commit Android active-goal card and collapsed-details captures plus
  UIAutomator hierarchies. The pinned PNG hashes are
  `cba47e0f1d6b0bba5392cfac21b19e252246a667d3d41e482c7b4fc7fb2bd8b8`
  and `9cadc8b1776a9e74bba8a0bd84f840aa89e2a8c4cbe07c0208740cdd4f8540b2`.
  Their semantics prove `niles.goal.card`, Active 7/20, `niles.goal.sheet`,
  `More work remains`, Pause, and Run next step without changing the pinned
  production source or APK.
- Matched the active-card placement and exact colors, then calibrated the
  details sheet with the Android text renderer, source button heights, objective
  and latest-check card geometry, and collapsed-objective behavior. The
  zero-mask comparisons pass at SSIM `0.856523`/outliers `0.052735` and SSIM
  `0.848625`/outliers `0.084417`. All 11 landmarks and eight exact color samples
  pass; maximum landmark delta is `1.67` points.
- Extended the disposable visual lane from four to six states. The fresh run at
  `build/test-lab-results/20260724T192044Z-92852` passed comparer self-test,
  onboarding clean/form, model picker, goal creation, active card, and active
  details, plus no-crash validation, all-file secret scan, and Simulator
  deletion.
- Added an exact-commit Android mixed-delegation capture and semantics dump by
  running the pinned repository's existing instrumentation test against the
  unchanged production app. The PNG and semantics hashes are
  `a906fb79dab9931bff46bb66a339186a17804b7d3546e6af32e308f79de1dc8b`
  and `a2bee56b190958fb1bd9c47a567be1705897b3fd85ca0808d878a36c8c108042`.
- Added a separate iOS source-pair fixture with the same working, failed, and
  finished agents and expanded working-agent controls. It exposed and fixed a
  production launchpad bug: a filtered pinned-delegation anchor no longer makes
  the empty-session launchpad appear behind active delegated work.
- Matched the source panel and all three row bounds, Material label geometry,
  status-dot colors, detail spacing, and white agent controls. The zero-mask
  comparison passes at SSIM `0.888724` and outlier fraction `0.050518`; all
  seven landmarks have zero-point deltas and all five exact flat-color checks
  pass under the approved native-presentation tier.
- Extended the disposable visual lane from six to seven states. The fresh run at
  `build/test-lab-results/20260724T202848Z-37346` passed comparer self-test,
  onboarding clean/form, model picker, goal creation, active card/details, and
  mixed delegation, plus no-crash validation, all-file secret scan, and
  Simulator deletion.
- Added an exact-commit Android context-breakdown capture and merged-semantics
  dump through the same test-only exact-pin overlay. Its state is 124.0k of
  200.0k tokens at 62%, with exact category ordering and values. The PNG and
  semantics hashes are
  `3b45b6a38f25e6e1513373fb4c7a99118d1969933f76347029dea295cd671c44`
  and `7444f27828cc4833f8a7de914feed173676ada3f7b5596d33fa0eea61ee82567`;
  pinned production source and the production APK remain unchanged.
- Added a separate iOS production-shell context fixture and calibrated the
  native sheet detent, Apple sheet inset compensation, content padding, stacked
  meter, and right-aligned category values. The zero-mask comparison passes the
  approved native-presentation tier at SSIM `0.822102` and outlier fraction
  `0.083586`; all four image-derived landmarks are within `0.67` point and all
  seven exact flat-color checks pass.
- Extended the disposable visual lane from seven to eight states. The fresh
  clean-room run at `build/test-lab-results/20260724T210357Z-11708` passed the
  comparer self-test, all eight Android/iOS comparisons, native-scale reviews,
  no-crash validation, all-file secret scan, and Simulator deletion. The
  context metrics reproduced exactly.
- Added an exact-commit Android gateway-statistics capture and merged-semantics
  dump through the same test-only production-shell overlay. The deterministic
  state selects 30 days and supplies exact totals, daily and heatmap activity,
  momentum, model, tool, and skill rows. The PNG and semantics hashes are
  `5acfa133d6809940a8f96a24a56ad6adaed91cd28216366709b257ece1f9eec3`
  and `1b5373e8d16688822ef4f8637fcdd32a5c32f2324a67efe1f86dc1980dbeeeb8`;
  pinned production source and the production APK remain unchanged.
- Added a separate iOS production-shell statistics fixture, a retained
  accessibility hierarchy, and a source-paired visual manifest. Calibrating
  the native detent, card geometry, section placement, and heatmap grid yields
  a zero-mask pass at SSIM `0.854220` and outlier fraction `0.098091`. All
  eight landmarks are within `1.34` points and all six exact flat-color checks
  pass under the approved native-presentation tier. The test-only reference
  date is fixed to the source-capture day while production continues to use
  live UTC time; a focused rerun after local midnight reproduced the metrics
  exactly.
- Extended the disposable visual lane from eight to nine states. The final
  clean-room run at `build/test-lab-results/20260724T221324Z-22312` passed the
  comparer self-test, all nine Android/iOS comparisons, native-scale reviews,
  no-crash validation, all-file secret scan, and Simulator deletion. The
  focused statistics metrics reproduced exactly.

Current session-rename checkpoint:

- Replaced the session-header rename no-op with the Android operation and
  dialog contract. Rename is available only for the selected live session
  while its gateway is online and writable, trims nonblank titles, updates the
  immutable session projection on success, keeps failures local to the open
  dialog, and disables dismissal and controls during mutation.
- Added owner and gateway-generation fencing so a late rename completion
  cannot update a newly selected session or gateway. Switching sessions,
  creating a session, losing the connection, hiding the surface, and teardown
  all invalidate the pending operation and clear rename-only state.
- Added four focused model tests covering success, local failure, stale-owner
  completion, and offline/read-only availability. The selector-driven UI
  journey proves the 48-point semantic controls, trimmed Save result,
  subsequent reopen, and Cancel rollback without coordinate taps.
- Added an exact-commit Android rename-dialog production-shell capture and
  semantics dump. Their SHA-256 values are
  `d3e829044f5caef9e328b3955c2715319ff44a1c454323ea2b83a05eee123719`
  and `23ea77c05f131a956bdb418178efa90911be97927a8e14110f7246d48efd0f7c`;
  only the tracked Android instrumentation patch changes, and it remains
  confined to `app/src/androidTest`.
- The source-paired zero-mask dialog comparison passes at SSIM `0.913306` and
  outlier fraction `0.036201`. The panel width is exactly 320 points, all six
  geometry landmarks are within `0.67` point, all three graphite/notice colors
  match exactly, and native-scale review is accepted under the approved
  cross-platform presentation tier.
- Fresh clean-room gates passed: 373/373 unit/protocol tests at
  `build/test-lab-results/20260724T224854Z-72424`, 29/29 deterministic UI tests
  at `build/test-lab-results/20260724T230051Z-86630`, the dedicated
  accessibility journey at
  `build/test-lab-results/20260724T230746Z-92373`, and all ten paired visual
  states at `build/test-lab-results/20260724T230938Z-94306`.

Current session-pin persistence checkpoint:

- Ported Android's gateway-scoped pinned-session persistence instead of keeping
  the Swift session ordering only in memory. A deterministic versioned
  Application Support envelope is atomically protected until first unlock and
  excluded from backup.
- Pin and unpin remain immediately responsive. An app-scoped FIFO persists the
  explicit desired value so rapid taps cannot invert; a failed write rolls back
  only if that same intent is still visible, and a gateway-generation fence
  prevents late failure from mutating a newly selected gateway.
- Gateway deletion removes its session pins alongside drafts, attachment state,
  and model pins. A process-lifetime removal tombstone prevents a queued write
  from recreating the deleted record.
- Four protected-store tests cover gateway scoping, relaunch, file protection,
  backup exclusion, removal races, malformed envelopes, versions, and invalid
  IDs. Five model tests cover restore/sort priority, optimistic persistence,
  failure rollback, rapid FIFO taps, and stale-gateway completion; the existing
  gateway-removal test now proves session-pin cleanup too.
- The fresh clean-room unit lane at
  `build/test-lab-results/20260724T232708Z-18635` passed analyzer, 382/382
  unit/protocol tests, the unsigned optimized Release build with warnings as
  errors, secret scan, no-crash validation, and disposable-Simulator cleanup.

Current session-creation affordance checkpoint:

- Ported Android's exact no-session copy and 48-point primary Create session
  action. The state distinguishes an empty list from no currently open session
  and explicitly tells the user when an unsent draft remains safe.
- Ported the collapsed carousel's right-swipe creation gesture: it begins only
  while connected, writable, collapsed, nonempty, and at the true leading
  scroll edge; claims only a right-dominant drag after touch slop; applies
  progressive resistance; and commits at the source 85% edge or a
  500-point-per-second fling. Leftward and non-start drags remain ordinary
  scrolling/non-actions.
- The full collapsed session section and its pull handle now accept a
  down-dominant drag after touch slop to reveal the expanded list. The
  simultaneous direction lock leaves handle taps, horizontal session
  scrolling, and the right-swipe creation gesture independent, and expansion
  continues to honor the reduced-motion setting.
- The collapsed row now preserves Android's eight-point top inset, exposes
  a deterministic New session ghost pill, centers non-leading selected pills,
  and uses iOS 18 scroll geometry with an iOS 17 first-pill fallback. Replacing
  lazy recycling prevents an offscreen first pill from falsely resetting the
  start-edge state. Crossing the commit edge emits selection feedback and every
  accepted create path emits confirmation feedback.
- Seven focused model/policy tests and four selector-driven XCUITests cover
  fixture and production creation, availability guards, exact resistance and
  commit thresholds, the working no-session action, downward expansion from
  the pull handle, preserved handle taps and horizontal strip scrolling,
  successful fling creation, and rejected non-start/leftward drags.
- A manual drive against the operator's local Hermes exposed the server's
  intentional omission of a newly created empty session from `session.list`
  until its first turn. The model now overlays only the selected writable
  session with its matching live runtime, retains that placeholder across
  refresh ticks, records ownership from authoritative rows only, and replaces
  the placeholder as soon as Hermes lists the persisted first turn. A focused
  regression covers the complete omission-to-replacement lifecycle.
- The post-fix Debug Simulator regression passed all 416/416 unit/protocol
  tests in
  `build/DerivedData/Logs/Test/Test-Nile-2026.07.26_16-27-47-+0200.xcresult`.
- Fresh clean-room gates passed 391/391 unit/protocol tests at
  `build/test-lab-results/20260725T002714Z-76510`, 32/32 standard UI scenarios
  at `build/test-lab-results/20260724T235418Z-43494`, the accessibility journey
  at `build/test-lab-results/20260725T000114Z-47619`, and all ten paired visual
  states at `build/test-lab-results/20260725T000855Z-56865`. The first visual
  attempt caught a four-point pill shift; restoring the source inset returned
  context to SSIM `0.822102`/outliers `0.083586` without changing a threshold,
  baseline, or mask. Focused post-fix create/reject swipe journeys also pass.
  A final exact-source run exposed a 47.667-point rounded semantic button frame;
  the label slot now carries a one-point raster margin and the 48-point-minimum
  assertion passes.
- Added Android's secondary create guards and exact user-facing errors for an
  in-flight model setting, goal update, or photo operation. The visible create
  affordances intentionally remain enabled under model/photo work, matching
  Android; the action explains why it cannot proceed.
- Creating from a live session now reserves the display owner, synchronously
  flushes the outgoing protected text record before `session.create`, keeps its
  already-protected photos under the old owner, and opens the new owner with a
  clean composer. Reopening the old session restores the exact text and JPEG
  draft. A storage error leaves the old owner visible and results in zero create
  RPCs.
- Three new tests cover guard copy, protected text/photo parking and restore,
  and fail-closed preflight. The fresh 391-test lane at
  `build/test-lab-results/20260725T002714Z-76510` passed analyzer, all tests,
  optimized Release with warnings as errors, secret scan, no-crash validation,
  and cleanup.
- Creation from a missing ordinary photo owner now promotes the photo record to
  a recovered marker before `session.create`; failure to protect that handoff
  produces zero create RPCs. Text-only ordinary drafts migrate through an exact
  composer-store CAS.
- Recovered no-live creation restores the marker's exact prompt and photos,
  consolidates subsequent edits into marker authority, merges multiple markers
  deterministically, and retargets every expected marker/photo record to the new
  durable/live owner in one protected attachment-store replacement. Composer
  ownership migrates with an exact source/destination CAS.
- The store revalidates after actor reentrancy and commits only while the exact
  gateway/display generation still matches. A stale gateway switch or any
  persistence failure leaves the missing source selected, its complete payload
  visible and relaunch-safe, and reports Android's retry guidance.
- Eleven new persistence/model tests cover atomic retargeting, stale snapshots,
  a rejected commit guard, ordinary promotion, text-only transfer, multi-marker
  merge, edit consolidation, relaunch, protection failure, migration failure,
  and a gateway-switch race. The fresh lane at
  `build/test-lab-results/20260725T005647Z-99351` passed analyzer, 402/402 tests,
  optimized Release with warnings as errors, secret scan, no-crash validation,
  and disposable-Simulator cleanup.

Current canonical brand-shell checkpoint:

- Captured the pinned Android
  `SessionShellUiTest#capturesDeterministicBrandScreens` state without changing
  its fixture behavior. The tracked chat PNG/semantics hashes are
  `e63f354995eaf86a2796336dabaa8103fe1a9fce1b841eb60027f51a96bf87ed`
  and `2be8d561b46cf0ec3f5b7e306a4c267eeaaba5c70a97e2848ede47a2ea117abf`;
  expanded sessions hashes are
  `0ec7441fc8c333031f1a335b46c11df06c6c4c505cf3418268b1654d86b62b1b`
  and `a5c3031c66061d8db12e080a80dc4a353179717cd77ce7cab9c8fee736e2a8e0`.
- Added the exact pinned Android text renderer to plain Markdown blocks,
  Compose line measurement to the composer, source typography/heading metrics,
  terminal grouping without a false generic summary, exact 64-point search and
  56-point expanded header geometry, and the deterministic two-state iOS
  fixture. The composer remains 56 points for one line, grows to 70.67 points
  for the fixture's two-line draft, and caps at five lines.
- Focused renderer regressions verify the source paragraph line breaks and
  one-/two-/five-line composer heights. The first integrated visual attempt
  correctly rejected the original fixed 70.67-point composer because it shifted
  single-line goal/delegation states; the adaptive implementation restores all
  prior geometry rather than weakening their probes.
- The fresh twelve-state lane at
  `build/test-lab-results/20260725T020857Z-59492` passes comparer self-test,
  every zero-mask comparison, every exact-color and image-derived landmark
  check, native-scale manual review, no-crash validation, secret scan, and
  fresh-Simulator cleanup. Canonical chat reports SSIM `0.828341`/outliers
  `0.071415`; expanded sessions reports `0.947338`/`0.023988`. Their six
  landmarks are within `0.67` point and all six sampled colors match exactly.
- The companion unit lane at
  `build/test-lab-results/20260725T021725Z-68020` passes analysis, 404/404
  unit/protocol tests, the unsigned optimized Release build with warnings as
  errors, secret scan, no-crash validation, and fresh-Simulator cleanup.

Current retained media/read-only checkpoint:

- Promoted the mandatory retained
  `.reference/android/docs/screenshots/nile-media.png` frame into a
  deterministic visual gate without changing the Android oracle. Its SHA-256
  remains
  `87e2aa25b4268eddb90ccaa0f6f7dbaf1b84954f15e2ad3caae3744a175d714c`.
  The iOS fixture carries the exact CLI session ID, prompt, response, filename,
  MIME type, and base64 PNG preview bytes from the Android test-lab recipe.
- The selector-driven fixture proves the terminal session is read-only, the
  attachment is actionable, Claim remains available, and no composer exists.
  It exposed and fixed a production-copy defect: the workspace header now says
  Android's exact `CLI · read-only mirror` instead of only `CLI`. The
  attachment action also uses a monochrome open-in-new symbol instead of
  allowing the Unicode arrow to become a platform emoji tile.
- Extended the comparer with an optional full-width responsive-spacer
  normalization. It removes a band only when every native pixel equals the
  declared flat color, the band is internal, and it is at most 10% of content.
  The self-test proves an exact spacer passes and any band containing
  non-background UI is rejected. The corrected manifest crops only the
  63-pixel Android status bar and removes 227 pixels wholly inside the
  historical frame's 535-pixel solid canvas gap, preserving every rendered UI
  pixel and using no mask.
- The source/retained-oracle comparison passes at SSIM `0.855411`, outlier
  fraction `0.067721`, and mean absolute channel delta `9.255635`. All three
  container-edge landmarks are within `1.72` points and all three app-owned
  flat-color samples match exactly.
- Added an exact-pin Android test-only long-history checkpoint on the production
  session shell and a source-copy iOS fixture for messages 32–40, the Kotlin
  syntax block, final user bubble, and idle composer. The tracked Android PNG
  and semantics hashes are
  `b2e0a93471f503374cd0ef3b53d995f9a3ca0f0906735e1babffed00d4be44ee`
  and `c2c0da3f0638a77d606ad5691c045fa30ea0ae2cc493d96ad7ca0ba3e3f7f0ad`.
  Its zero-mask comparison passes at SSIM `0.935771`, outlier fraction
  `0.028354`, and mean absolute channel delta `3.819058`; the three exact
  flat-color samples pass and all four selected-session/syntax landmarks are
  within `1.34` points.
- Added an exact-pin Android test-only attachment checkpoint on the production
  session shell and a separate source-copy iOS visual fixture. Both carry the
  exact user/assistant copy, image and file transcript cards, two named pending
  JPEG items, idle model state, and enabled photo-only send action. The
  existing interaction fixture remains independent and still exercises remove
  plus photo-only submit behavior.
- The tracked Android attachment PNG and semantics hashes are
  `40a1f3e2c2ccc717040d55e9cf79d47640042f89e07bbd357d05f5aca9e1aa89`
  and `95955aab69999f9e0fa8c2353b1b307487177bf68826dd1e15ee14edeca1cd14`.
  The zero-mask comparison passes at SSIM `0.922386`, outlier fraction
  `0.032650`, and mean absolute channel delta `4.576272`; all four flat-color
  samples are exact and all five selected-session/composer/thumbnail landmarks
  are within `1.34` points.
- The fresh fifteen-state visual lane at
  `build/test-lab-results/20260725T043831Z-8863` passes every comparison,
  native review, exact-color/landmark gate, no-crash validation, secret scan,
  and cleanup. The exact tree also passes analyzer, 404/404 unit/protocol tests,
  warnings-as-errors Release, and cleanup at
  `build/test-lab-results/20260725T044252Z-12935`, plus all 36/36 standard UI
  tests and attachment export at
  `build/test-lab-results/20260725T044704Z-17495`.

Current gateway-removal confirmation checkpoint:

- Captured the pinned Android production removal confirmation from a disposable
  exact-commit test-only clone. The tracked Android PNG and all-root Compose
  semantics hashes are
  `a5690303736d94c121cd75d23f14b20faa45f529b61c2a6be0605bc34b40144e`
  and `88ab66c7c6f21a2691485cf956c8819f42d2e063704405038329f9b6c6e94239`.
  The capture opens the destructive dialog but never confirms it; the pinned
  production APK and tree remain unchanged.
- Replaced the native iOS alert with an app-owned Material-aligned confirmation
  surface carrying Android's exact title, credential/session/draft deletion
  copy, active-turn warning, Cancel label, and Remove gateway action. The panel
  cannot dismiss during removal and exposes Android's `Removing…` progress
  state; a failure remains visible without pretending deletion succeeded.
- The isolated fixture injects an in-memory profile store and no-op session
  cleaner, then exercises the real `GatewaySetupModel.removeGateway` path
  without reading or mutating user credentials. Its selector-driven XCUITest
  proves cancel is non-destructive, confirmation is required, and confirmation
  reaches the empty saved-gateway state.
- The accepted zero-mask development comparison passes at SSIM `0.931439`,
  outlier fraction `0.030375`, and mean absolute channel delta `4.003688`.
  The 320-point panel, both vertical edges, destructive-button top and width are
  all within `1.34` points, and the panel/destructive colors match exactly.
- Fresh clean-room gates pass analyzer, 404/404 unit/protocol tests, and the
  warnings-as-errors Release build at
  `build/test-lab-results/20260725T052222Z-46897`; all 37/37 standard UI
  journeys at `build/test-lab-results/20260725T052628Z-50149`; all sixteen
  paired zero-mask visual states at
  `build/test-lab-results/20260725T053441Z-54439`; and the dedicated
  accessibility-extra-large journey at
  `build/test-lab-results/20260725T054549Z-67302`. Every passing lane also
  completed its no-crash, secret-scan, and disposable-Simulator cleanup
  contract.
- The accessibility rerun exposed that iOS can localize the system keyboard
  independently of the app launch locale: the source-correct Next key had the
  stable `Next:` identifier but the German label `Weiter`. The test now asserts
  the stable system identifier and sends the logical Return action through the
  focused editor, preserving Name → URL → secure-token behavior without
  hard-coding a host keyboard language. The retained failing runs
  `20260725T053914Z-58152` and `20260725T054213Z-63080` document the discovery
  and the localized-key hit-target quirk; the clean run above supersedes them.

Running-turn gateway-switch checkpoint:

- Captured Android's existing
  `runningTurnGatewaySwitchRequiresExplicitConfirmation` journey from a
  disposable exact-commit, test-only clone before its first dismissal. The
  tracked PNG and all-root Compose semantics hashes are
  `3e0c1a25e85552fa3954ece060bf482d5b7874c5f0cfb455c42a1971dbc2920c`
  and `e5d8d93583505b22dbb66de10c39d0ec74055807b8b0219c0164f7c0d9c2440c`;
  production Android source, tree, and APK remain unchanged.
- Added a Settings-only switch request boundary. It asks the session model a
  read-only outside-gateway ownership question and stages the exact saved
  target without connecting, selecting, disconnecting, or stopping a turn.
  Stay here clears only the staged dialog. Switch gateway consumes it once,
  then the existing will-connect boundary stops outside targets before
  transport replacement. Direct notification routing remains explicit and
  unprompted.
- The state machine matches Android's race cases: selecting the already
  connected profile only dismisses Settings; a safe switch proceeds directly;
  repeated confirmation is a no-op; old-connection loss preserves the pending
  request; and successful target removal clears it. Six focused model tests
  prove those behaviors and the absence of pre-confirmation client/store/turn
  side effects.
- Added an isolated two-profile fixture whose no-op transport still exercises
  the real `GatewaySetupModel` selection path. Its selector-driven XCUITest
  verifies exact title/body/action copy, screenshots and hierarchy, Stay here
  preservation, and confirmed transition to the Lab Hermes session shell.
- The zero-mask paired comparison passes at SSIM `0.906843`, outlier fraction
  `0.033835`, and mean absolute channel delta `4.045658`. The 320-by-224-point
  panel and white action geometry use six landmarks, all within `0.67` point;
  the `#212121` panel and `#F8F8F8` action colors match exactly. The integrated
  seventeen-state clean visual lane passes at
  `build/test-lab-results/20260725T065109Z-27360`.
- Fresh clean-room regressions pass analyzer, 410/410 unit/protocol tests, and
  warnings-as-errors Release at
  `build/test-lab-results/20260725T063650Z-18404`; all 38/38 standard UI
  journeys at `build/test-lab-results/20260725T064051Z-21818`; and the dedicated
  accessibility-extra-large journey at
  `build/test-lab-results/20260725T064903Z-25639`. Every lane also passed its
  secret scan, no-crash check where applicable, and disposable-Simulator
  cleanup.

Current exact-commit Hermes voice-settings checkpoint:

- Added a test-only exact-pin Android overlay that opens the real loaded Hermes
  voice sheet over `NileAppContent` with the connected Edge TTS / Aria fixture.
  The capture script accepts only Android-test changes, builds the unchanged
  production app, exports the 1206-by-2478 PNG plus all-root Compose semantics,
  validates exact sheet copy, and leaves `.reference/android` clean at commit
  `bd5451da891f2d886b9bc35f8ea67d6920df1d98` and tree
  `3b954e5844f05276d34aaee34a7d3f69169ef9f5`.
- The tracked Android PNG and semantics hashes are
  `61c7c77ca4e48a557d180bc83a3c3fbc692d61794b4e6467bb2ce7ea24ba0e27`
  and `bf8a4eef859851c55c50348a7b2ea31a40bd680937a3b7d2b4a0b3da4c5c0a4d`.
  The source-paired fixture exercises provider summary, current voice, selected
  and alternate presets, custom identifier field, global-impact warning,
  disabled Apply, and Close.
- Calibrated the native iOS sheet to the Android app-owned geometry and
  explicit Material colors, including embedded Roboto and Droid Sans Mono
  roles, the 603-point detent, provider/preset/field/warning/action rhythm, and
  disabled-button styling that is not altered by SwiftUI environment dimming.
  The native eight-point sheet inset and system-owned chrome are explicitly
  accepted cross-platform differences under the user-approved visual tier.
- The selector-driven journey captures screenshot and hierarchy before
  mutation, proves disabled-to-enabled Apply, sends the changed voice through
  the production model path, verifies the global summary, and closes the sheet.
  Its handle, selected preset, Apply, and Close semantic targets are each
  `46.1` points high; negative layout padding preserves the paired visual slots.
- The zero-mask comparison passes at SSIM `0.872254`, outlier fraction
  `0.085222`, and mean absolute channel delta `7.022960`. All eight
  sheet/card/chip/warning/action landmarks are within `2` points and the five
  exact samples `#212121`, `#242424`, `#00284D`, `#0D0D0D`, and `#3C3C3C`
  pass. The integrated eighteen-state clean visual lane is
  `build/test-lab-results/20260725T074048Z-61567`.
- Fresh final-source regressions pass analyzer, 410/410 unit/protocol tests,
  warnings-as-errors Release, and secret scanning at
  `build/test-lab-results/20260725T074610Z-67209`; all 38/38 standard UI
  journeys at `build/test-lab-results/20260725T075027Z-71091`; and the dedicated
  accessibility-extra-large journey at
  `build/test-lab-results/20260725T075900Z-78115`. Every applicable lane also
  passed no-crash validation and disposable-Simulator cleanup.

Current exact-commit Talk-listening checkpoint:

- Added a test-only exact-pin Android capture of the real `TalkScreen` in its
  listening phase with the deterministic Brand polish session title. The
  unchanged production APK renders the full-screen surface while instrumentation
  exports the 1206-by-2478 PNG and all-root Compose semantics. The tracked PNG
  and semantics hashes are
  `93e65e8191936ab69426b82aac98ad88d09fab69b3f0fdd84c3e9f83eb5d66c1`
  and `026ccd3956661be8047df9c804425af96323b5e940bc4f0208e5330b0352069c`.
- Replaced the remaining native SF close symbol with the app-owned pinned
  Material path, corrected the Talk header from a padded 76-point slot to the
  source 64 points, changed enabled controls to Android's exact `#242424`, and
  moved control padding inside the source-sized 92-by-75-point semantics.
  Reducing header and control excess equally keeps the centered phase group
  fixed while aligning both ends of the screen.
- The selector-driven fixture enables Reduce Motion before capture, proves
  private draft/transcript text stays absent, asserts the status and orb,
  verifies Close/Transcript/Pause/End are at least 44 points in both dimensions,
  then exercises pause, resume, and end back to the ordinary composer.
- The zero-mask paired comparison passes at SSIM `0.987325`, outlier fraction
  `0.007053`, and mean absolute channel delta `0.916477`. The graphite canvas,
  outer/middle/core orb layers, and control surface match all five exact colors;
  all six orb and control landmarks have exactly zero-point delta. The
  integrated nineteen-state clean visual lane is
  `build/test-lab-results/20260725T082058Z-97729`.
- Fresh final-source regressions pass analyzer, 410/410 unit/protocol tests,
  warnings-as-errors Release, secret scanning, no-crash validation, and
  disposable-Simulator cleanup at
  `build/test-lab-results/20260725T082723Z-4481`; all 38/38 standard UI
  journeys, including the source-sized Talk targets and pause/resume/end path,
  at `build/test-lab-results/20260725T083216Z-10354`; and the dedicated
  accessibility-extra-large journey at
  `build/test-lab-results/20260725T084227Z-18388`.

Current iOS-native expanded-session checkpoint:

- Replaced the tall opaque overlay, hard 50% dimmer, permanently visible
  outlined search field, and isolated stacked cards with an adaptive-height
  contextual Liquid Glass sheet, a quiet 16% scrim, a 44-point grabber
  dismissal target, a clear title/status hierarchy, and native glass search
  and add actions.
- Consolidated sessions into one grouped surface with compact 62-point rows,
  separators, selected checkmark/tint, needs-input warning treatment, runtime
  state, timestamps, previews, and independent 44-point pin actions. Switching,
  create-session availability, pin ordering, status presentation, and
  read-only selection still use the existing model paths.
- Search is progressive and autofocuses when requested. It retains title,
  source, and ID filtering, sizes the sheet to filtered results, supports clear
  and Cancel, dismisses with Escape or Cancel, and uses interactive keyboard
  dismissal while scrolling.
- Added stable sheet/search accessibility identifiers, compact-height and
  progressive-search assertions to the existing journeys, a forced-light
  visual fixture, and a focused pin/dismiss/search/keyboard/select contract.
  Fresh dark and light iPhone 17 Pro / iOS 26.5 captures plus the active-search
  keyboard capture were inspected under `build/session-list-polish/`.

Current transcript keyboard edge-case checkpoint:

- The transcript now uses one authoritative self-sizing `UICollectionView`
  viewport with a compositional layout and a diffable, stable-ID data source.
  UIKit owns content size, offset, drag state, bottom visibility, keyboard-driven
  bounds changes, and visible-row reuse instead of reconstructing them from
  asynchronous row preferences and `scrollTo` requests.
- Row hosts retain their SwiftUI-local state by transcript ID, but only visible
  hosts are attached and laid out. A row transfer explicitly releases its former
  cell before attaching to the next cell, so late reuse cannot remove visible
  content during a keyboard resize.
- Bottom follow is an explicit per-gateway/session mode. Only user scrolling
  detaches it; streaming/layout changes preserve the exact offset while parked,
  and a fresh user turn or the jump action reattaches it after real layout.
- Plain Markdown measurement and drawing now share UILabel's sizing path;
  Android-derived heights are no longer forced around differently wrapped
  UIKit glyphs.
- The focused one-message and four-cycle switched-session keyboard journeys
  remain green alongside the dynamic streaming stress journey.

Current real-world edge-case audit checkpoint:

- `docs/USER_EDGE_CASE_AUDIT.md` maps 24 concrete user scenarios across
  onboarding, authentication, gateway lifecycle, sessions, transcript and
  blocking input, models, commands, media, goals, delegation, usage, speech,
  background completion, and accessibility.
- The audit found and fixed seven weak spots: unbounded gateway documents,
  remotely triggered counter overflows, lost preview extensions, drifted
  post-removal copy, two obsolete native-control geometry contracts, and
  long-transcript keyboard repinning.
- Final disposable regressions pass analyzer, 427/427 unit/protocol tests,
  warnings-as-errors unsigned Release, secret scanning, crash validation, and
  cleanup at `build/test-lab-results/20260728T234055Z-18012`; all 52/52
  standard UI journeys at
  `build/test-lab-results/20260728T234502Z-20631`; and the dedicated
  accessibility-extra-large journey at
  `build/test-lab-results/20260728T235940Z-26509`.

Current streaming-performance checkpoint:

- Established a deterministic publication contract for the hottest rendering
  path: assistant fragments remain byte-for-byte ordered and lossless while
  visible transcript publication is capped at 30 times per second. A 120-delta
  burst across four cadence windows now produces four publications instead of
  120, and a 120-delta burst terminated by a tool event produces exactly one
  model transcript publication before the tool.
- Visible assistant deltas take a cadence-limited fast path. Interim,
  completion, tool, prompt, error, connection, and session-switch boundaries
  synchronously flush pending text first. Hidden-session timelines continue to
  consume deltas immediately, preserving mid-turn restoration and chronology.
- Live assistant text now mutates the identified transcript tail in place and
  avoids redundant `isSending` writes instead of mapping the complete transcript
  for every publication. The publication counter used by the regression is
  excluded from SwiftUI observation.
- Transcript presentation is projected once per observed update, then the
  diffable viewport reconfigures only changed IDs. A deterministic 400-row
  regression changes the streaming tail and proves that exactly one row is
  targeted, with no structural snapshot change or broad layout invalidation.
- Settled Markdown parsing, fenced-code tokenization, and base64 transcript-image
  decoding use bounded `NSCache` stores (128/4 MiB, 64/2 MiB, and 24/48 MiB).
  Streaming Markdown deliberately bypasses the settled cache so incomplete
  structures remain correct; focused counters prove stable content is processed
  once.
- LocalRelease includes an allowlisted, secret-free streaming stress fixture,
  and the viewport emits `os_signpost` intervals for complete updates and row
  configuration. Release continues to accept no fixture arguments. Optimized
  whole-module LocalRelease simulator, signed LocalRelease device, and unsigned
  generic Release builds pass.
- A 19.21-second physical Animation Hitches recording of that LocalRelease
  fixture on an iPhone 15 / iOS 26.5.2 completed at
  `build/performance-results/20260807-transcript/device.NoGpRc/animation-hitches.trace`.
  The device remained at nominal thermal state and Instruments reported zero
  animation hitches and zero hang-risk events. Four potential main-thread hangs
  (43.82, 155.00, 78.97, and 46.36 ms) were confined to cold launch before the
  active foreground interval; none occurred during the streaming workload.
  Across the fixture's 3.3-7.2 second steady burst window, 60 application render
  intervals measured 2.57 ms median, 3.15 ms p95, and 3.51 ms maximum, with at
  most one offscreen pass. The paired Logging recording at
  `build/performance-results/20260807-transcript/device-logging.KBSx0O/transcript-signposts.trace`
  likewise places all seven UIKit/Core Animation stall intervals at 1.32-1.68
  seconds during launch and none in the burst window.
- The final full unit/protocol regression passes 451/451 in
  `build/DerivedData/Logs/Test/Test-Nile-2026.08.07_20-12-42-+0200.xcresult`.
  The repository-owned disposable UI lane passes 56/56 on a fresh iPhone 17 Pro
  / iOS 26.5 simulator, including fit-content and scrollable keyboard resizing,
  immediate broad composer activation after switching, attached/detached
  streaming, session switching, accessibility, prompts, attachments, and scroll
  restoration, at `build/test-lab-results/20260807T181327Z-40982`.

## Beautiful UI design system (2026-08-13; Settings audit 2026-08-15)

The Beautiful UI implementation is a complete alternate visual direction based on the
component library at `beautifului.dev`. It replaces glass and broad native
styling with the reference's exact light/dark semantic palette, 8/10/14-point
radii, compact typography, one-pixel borders, low shadows, dense session rows,
neutral chat bubbles, Prompt Bar composer, Approval Card prompts, and pixel-grid
loading/Talk states. The detailed component map, interaction rationale, token
values, and retained visual evidence are in
[`BEAUTIFUL_UI_REDESIGN.md`](BEAUTIFUL_UI_REDESIGN.md).

The follow-up audit opened all 19 Beautiful UI demos and source panels. It found
stale or missing treatments in thinking/tool traces, delegated task rows,
standing-goal recommendations, context cards, diff/code containers, search,
usage insights, model fine-tuning, and message selection actions. Those surfaces
now use the shared opaque canvas/surface/inset hierarchy, 8/10/14-point radii,
one-pixel boundaries, compact semantic rows, framed code/diff content, and
contextual iOS selection behavior. The component-by-component before/after
ledger is in [`BEAUTIFUL_UI_REDESIGN.md`](BEAUTIFUL_UI_REDESIGN.md).

All 719 unit/protocol tests, the 61 architecture contracts, and ten focused UI
executions pass on iPhone 17 Pro / iOS 26.5. Both visual iterations were
inspected at original resolution under `build/visual-review/`, and an unsigned
generic-device Release build succeeds. This direction intentionally proposes an
alternative to the governing Android visual target; it is not evidence that
strict Android visual parity is complete and does not amend `IOS_PORT_GOAL.md`.

The 2026-08-15 Settings audit separates the pre-connection journey from the
connected settings hierarchy. First launch now presents a focused Connect Nile
to Hermes surface; connected Settings is a large contextual sheet with compact
Hermes and Security groups, while saved endpoints, Add Gateway, switching, and
destructive removal live in a Gateways detail. The active session remains
visible behind the sheet. Voice is a compact peer row instead of another card.
Focused disposable-simulator journeys verified both appearances, large text,
secure keyboard navigation, 44-point targets, progressive disclosure, gateway
switch/removal confirmation, and voice updates. The audit corrected a too-small
heading, a 20-point Cancel accessibility frame, transient title alignment, and
confirmation overlays hidden behind pushed navigation. The final six-test
evidence bundle passes in `build/settings-hierarchy-verified.xcresult`, with
inspected captures exported under
`build/settings-hierarchy-verified-attachments/`.

## Known incomplete work

The current app is a foundation, not a functional parity release. In particular:

- Settings/onboarding and the wider Beautiful UI surfaces have current
  product-design screenshots and interaction checks, but those are not pinned
  Android parity evidence. Historical source-paired gates describe earlier
  layouts and do not establish parity for this tree. The strict visual lane is
  therefore expected to remain red until the product direction and the
  repository's Android acceptance contract are reconciled and every current
  state has fresh paired quantitative results.
- The disposable real-Hermes smoke lane is implemented and compile-verified but
  still needs its first credentialed execution and resulting fixes. A manual
  local-Hermes drive now proves loopback token connection, real session/history
  reads, search, statistics, Claim confirmation, reconnect, and cold restore
  without mutating an existing session. It exposed and now has focused
  regression coverage for the pre-first-turn session-list omission. A clean
  loopback socket correctly remained unavailable without Hermes's dashboard
  session token; the paid model-turn phase remains pending.
- The Android full disposable lab is Linux-specific and cannot run unchanged on
  this macOS host; a Linux runner must preserve Android-oracle verification.
- Streaming publication pressure, broad transcript invalidation, and repeated
  settled-content processing are now bounded. The deterministic 120-to-4
  publication and 400-to-1 row-target baselines provide reproducible before/after
  evidence; the physical LocalRelease trace above supplies the post-change device
  validation. No pre-change physical trace was retained, so future regressions
  should compare against this exact fixture, device profile, and trace.

## Next concrete action

Execute the credentialed three-phase real-Hermes smoke when a secure OpenRouter
credential is available. Continue extending paired coverage across the remaining
state inventory before final exact-commit verification, and rerun the pinned
physical streaming trace after future transcript-rendering changes.
