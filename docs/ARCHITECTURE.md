# Nile iOS architecture

## Status

This document describes the target architecture and marks what exists today.
The port is incomplete until the parity matrix and full test lab are green.

## Acceptance sources

`AGENTS.md` and `IOS_PORT_GOAL.md` are the governing repository and
acceptance contracts. The pinned Android commit and tree define functional,
security, and app-owned visual parity. `docs/IOS_NATIVE_DESIGN.md` is retained
as a historical implementation record for current native-presentation
divergences; it cannot waive a parity row or turn a red strict comparison into
an accepted result.

`project.yml` is the authoritative XcodeGen input. The checked-in
`Nile.xcodeproj` is its generated convenience artifact and must not acquire
personal signing data. `Config/Info-*.plist` and the matching xcconfig files
own transport policy for Debug, LocalRelease, and Release.

## Layers

```text
SwiftUI / UIKit feature surfaces
            │
      @MainActor app state
            │
   domain models and protocols
            │
 coordinators / use-case boundaries
            │
 REST + JSON-RPC WebSocket transport
            │
       vanilla pinned Hermes
```

### App and features

`Sources/Nile/App` owns the app entry point, top-level state, and stable
accessibility identifiers. `Sources/Nile/Features` owns user-visible surfaces.
UI code must not parse Hermes frames or own credentials.

Implemented:

- bounded app-entry surfaces: the 169-line `NileApp` source owns the sole app,
  graph, root routing, scene lifecycle, fail-closed fallback shield, and loading
  state; the 210-line `BiometricAppLockOverlay` exclusively owns the scene-bound
  modal lock window; and the 73-line `NotificationEducationView` owns permission
  education without app-graph or biometric authority
- feature-owned stable accessibility contracts: the one-line
  `NileAccessibilityID` namespace has no identifiers of its own, while seven
  extensions independently own app/gateway, composer/talk, delegation,
  goal/prompt, model/command, session, and transcript identifiers. All 149
  constants, 34 public dynamic factories, two private key helpers, and 183
  external `niles.*` templates remain present; the voice Java-style hash and
  length-framed model-pin key each have focused value regressions. Architecture
  enforcement requires unique feature markers, 95/60/40/40/90/60/55-line caps,
  and a 370-line aggregate so stable UI-test contracts cannot reconsolidate
- bounded biometric app-lock internals: the 187-line observable state machine,
  64-line Foundation-only contracts, 21-line non-secret `UserDefaults` adapter,
  and 97-line `LocalAuthentication` adapter have exclusive ownership; only the
  platform adapter sees `LAContext`/`LAError`, which it maps into stable domain
  failures before the fail-closed state machine handles presentation
- a gateway setup state model
- Android-aligned Settings/onboarding structure
- explicit cleartext confirmation before a cleartext status request
- production `/api/status` reachability probe using an ephemeral, cookieless session
- Android-aligned gated dashboard sign-in split across a 185-line SwiftUI state
  surface, a 159-line persistent-`WKWebView` lifecycle bridge, and a 98-line
  Foundation-only fail-closed navigation policy. The current origin remains
  visible, navigation stays inside the gateway path prefix, external HTTPS
  origins require explicit confirmation, credentialed/malformed targets fail
  closed, and no JavaScript-to-native message bridge exists. Architecture
  contracts enforce 210/180/115-line caps and include the split in the bounded
  gateway-surface aggregate
- post-`gateway.ready` profile commit, automatic active-profile restore, saved
  profile selection/removal, and a connected root boundary
- Android-aligned recovery phases that retain the selected profile, session
  strip, and transcript while offline/reconnecting; block interaction; restore
  the selected session before publishing online; and restart backoff
  immediately when the app returns to the foreground
- a bounded 248-line `GatewaySetupModel` core that owns retained observable
  state, dependency construction, handler installation, authentication-event
  observation, and initial connection; a task-free 65-line presentation
  extension owns synchronous form mutation plus form, error, and root-shell
  projection; bounded 293-line connection, 285-line saved-profile, and 160-line
  Hermes voice extensions independently own dashboard sign-in/reconnect,
  explicit profile actions, and voice-settings presentation without duplicating
  the gateway state machine or broadening the pending-switch setter
- one 6-line `GatewaySetupModelTests` identity with its 30 lifecycle contracts
  owned by six behavior extensions for connection/form, fixtures, staged gateway
  switching, reconnect/authentication, protected-data cleanup, and Hermes voice.
  Those sources range from 44 to 327 lines; four support sources ranging from
  48 to 168 lines separately own shared model helpers and the voice, connection,
  reconnect, profile, draft, and pin fakes
- a bounded 262-line `SettingsView` orchestration surface that solely owns the
  observable setup/app-lock models, async intent admission, navigation, and
  confirmation lifecycle; a 188-line model-free `SettingsCards` source owns the
  app-security and saved-gateway renderers through one narrow security binding,
  immutable render state, and synchronous gateway intents; a 59-line Hermes
  voice entry; a 159-line model-bound sheet; a 312-line model-free editor,
  status, and control surface; and a
  107-line Foundation provider/preset/draft-admission policy; plus staged
  gateway-switch and protected gateway-removal confirmations owned by 98-line
  and 143-line dialog sources. The Add Gateway flow is split into a 216-line
  model/focus/form/task orchestrator and a 77-line model-free cleartext warning
  and approval renderer; unreachable legacy sizing, raster-color, exact-text,
  and button-style remnants were removed without changing the rendered path.
  Their architecture contract enumerates every Swift source in the Gateway
  feature directory, preserves unique declaration/model/task ownership,
  enforces 275/210-line settings caps with a 470-line pair aggregate,
  175/325/125-line voice caps, 235/95-line onboarding caps, the 1,350-line
  settings aggregate, and a 2,100-line complete gateway-surface aggregate
  without changing geometry or accessibility IDs
- a feature-owned design-system boundary: `NileDesignTokens` owns colors,
  radii, motion, tactile feedback, and the reduced-motion environment;
  the 188-line `NileTypography` owns custom Roboto role declarations and the
  font factory without importing UIKit, while the 125-line
  `NileTypographyMetrics` owns the immutable measurement contract, UIKit weight
  resolution, and Dynamic Type mapping without declaring visual roles;
  `NileDesignModifiers` owns reusable panel/glass/text modifiers;
  `NileComposeText` owns the narrow UIKit bridge for Compose-greedy multiline
  wrapping; and `NileAndroidTextMeasurement` alone imports the pinned Android
  renderer for cross-renderer measurement. Markdown is likewise bounded: the
  191-line `NileMarkdown` source owns the public view plus block/code rendering,
  21-line contracts source owns immutable block/table values, the 42-line cache
  owns lock-backed parse accounting and settled `NSCache` state, and the
  256-line parser owns only block parsing mechanics. The 83-line inline source
  owns list and attributed-text styling, and the 276-line table source owns
  adaptive grid/stacked layout and accessibility. The 50-line
  `NileMaterialIcon` compatibility view maps its nine retained Android-vocabulary
  cases directly to SF Symbols; it has no dormant `Path` renderer or private
  geometry. Scaled gateway field/button geometry
  keeps the default Android dimensions unchanged, explicit keyboard progression
  crosses the gateway form, and the root reduced-motion policy combines the
  native system preference with a Debug-only deterministic fixture before
  suppressing root and feature animations
- `NileAppGraph`, which gives gateway setup and session state the same production
  `TuiGatewayRepository`/WebSocket client instead of opening parallel transports
- a 231-line `NileAppGraphFixtures` source that owns build-configuration
  argument filtering plus deterministic transcript, composer, usage, and
  statistics states; its 185-line collaborator extension separately owns the
  fake biometric, profile, connection, cleanup, voice-input, and Hermes-voice
  capabilities; the 173-line `NileAppGraphFixturePlan` retains filtered global
  fixture flags and admission, while the 74-line pure
  `NileSessionFixturePolicy` is the sole owner of session-catalog, streaming,
  and recovery precedence. Neither contains fake-capability, gateway-profile,
  or session-model construction. The 171-line assembly extension owns only
  selected collaborator/profile construction without raw launch arguments, and
  a 248-line installer owns deterministic state mutation and streaming-stress
  orchestration. All sample state, fake collaborators, policy, selection,
  assembly, and installation compile only under `DEBUG || NILE_LOCAL_RELEASE`;
  App Store Release sees compact no-op plan, assembly, and installer branches,
  while delegated-agent installation remains Debug-only
- a 218-line production `NileAppGraph` that retains shared repository/WebSocket
  dependency wiring, lifecycle callback installation, and notification-route
  execution without raw fixture arguments or sample data; the stateless 84-line
  `TurnNotificationRoutePolicy` independently owns its fail-closed decisions
- a `@MainActor` session-list model that isolates one gateway's session state,
  opens Nile-owned sessions, preserves terminal-owned sessions as read-only, and
  retains the shared state and ownership rules consumed by one ordered event
  application extension
- a bounded 118-line `SessionListModelPresentation` extension that owns only
  runtime-backed feature forwarding; a 171-line
  `SessionListModelWorkspacePresentation` extension independently owns
  synchronous eligibility/error/scroll-owner and session-directory projection;
  33-line lifecycle and 58-line blocking-prompt bridges isolate model-facing
  callbacks and projection without transport, task, persistence, capability, or
  event authority; the 233-line core retains stored observable and fixture state,
  runtime construction, teardown, and private ownership projection
- a bounded 227-line `SessionListModelGateway` extension that owns reconnect
  restoration, gateway replacement/reset sequencing, protected draft and pin
  restoration, initial directory/catalog loading, and immutable gateway
  generation checks without receiving a repository or event-stream capability
- a bounded 267-line `SessionListModelNavigation` extension that owns displayed
  selection, reset/cancellation, fixture and cached-switch presentation, pins,
  and display-owner/status/overlay helpers; a 173-line
  `SessionListModelSessionOpening` extension owns immutable owner-fenced source
  lookup, live/history opening, recovery quarantine, cache restoration, and
  opening settlement; and a 107-line `SessionListModelRefresh` extension owns
  periodic directory/status/history sink application and completed-turn repair.
  All three depend on the same capability-narrow navigation runtime without
  constructing a repository or consuming events; private terminal provenance
  remains in the core behind narrow classification and recording helpers
- a bounded 48-line `SessionListModelEvents` core that retains the sole private
  ordered Hermes event-application method and fixes the stage order; a 128-line
  settlement extension owns delegation/lifecycle effects, blocking-input
  interception, and terminal resource cleanup; a 240-line visible projection
  extension owns ordinary visible turn/transcript effects; a 70-line connection-
  loss projection owns the ordered gateway-wide teardown transaction; and the
  106-line cadence/helper projection isolates visible/cached deltas, goal,
  attached-turn, and tool presentation. Blocking-input admission and visible
  projection live in the independent model bridge. None constructs a repository
  or consumes another event stream, and the five event sources remain under a
  610-line aggregate ceiling
- a bounded 241-line `SessionListModelTimeline` extension that binds the
  timeline runtime to visible-session caching, guarded restoration,
  foreground/status reconciliation, live/stored transcript replacement, and
  background/blocking/delegation runtime association without a repository or
  event-stream capability
- a bounded 247-line `SessionListModelComposer` extension that owns displayed
  composer admission, protected text-draft projection, claim retirement, owner
  visibility, and restoration callbacks; composer, draft-lifecycle, and
  attachment-recovery runtimes retain state and persistence authority while the
  bridge receives no repository capability or event stream
- a bounded 221-line `SessionListModelTurn` extension that owns displayed
  prompt, steering, and Stop admission plus optimistic turn/background
  projection; its 136-line settlement extension independently owns
  protected-draft recovery and prompt/steer/Stop visible outcomes without
  transport admission. The turn runtime retains transport tasks and uncertainty
  fencing, while the event extension retains the sole ordered application
  boundary
- a bounded 255-line `SessionListModelCreation` extension that owns creation
  admission, protected text/photo draft handoff, immutable request fencing,
  fixture creation, and displayed post-create settlement; navigation and
  creation-draft runtimes retain transport and protected migration authority,
  while ownership coordination remains in the core and event routing remains in
  the event extension
- a bounded 260-line `SessionListModelCommands` extension that integrates
  `SessionCommandRuntime` admission and native-command draft claims with the
  visible composer, plus a 205-line settlement extension for definite/uncertain
  recovery and transcript delivery; neither receives a repository capability or
  event stream
- a bounded 185-line observable `SessionCommandRuntime` that owns catalog and
  completion state plus the sole stored `HermesCommandServing` capability; a
  separate 224-line non-observable `SessionCommandExecutionLifecycle` receives
  that capability only for an admitted operation and owns per-session mutation
  tasks, alias validation, uncertainty classification, and reset cancellation
- a bounded 221-line `SessionListModelModelControl` extension that projects the
  picker, reasoning, and protected pin runtime into the displayed session; the
  227-line runtime core retains the sole state/capability/task declarations plus
  catalog and pin coordination, while its 285-line mutation-lifecycle extension
  isolates model/reasoning admission, confirmation, and settlement without
  another runtime, repository owner, or event path
- a bounded 193-line `SessionListModelGoal` extension that integrates
  standing-goal sheet actions, exact-owner fencing, kickoff/resume prompt
  delivery, and definite/uncertain turn-failure settlement with the displayed
  session; the mutation runtime retains full goal capability and progress state,
  its status child receives only read capability, and event reconciliation
  remains at the event extension's ordered boundary
- a bounded 97-line `SessionListModelMedia` extension that owns attachment
  viewer state, open/dismiss actions, exact-owner validation, and visible image
  preview projection; the 165-line `SessionMediaRuntime` core retains the sole
  authenticated-read and cache capabilities plus viewer state and all
  viewer/preview operation registries, while its 243-line same-runtime preview
  extension owns reconciliation, concurrency/retention policy, image hydration,
  and projection without another capability, state authority, or event path;
  the bridge receives no repository capability or event stream
- a bounded 293-line `SessionListModelAttachments` extension that owns photo
  draft add/remove projection and delivery admission; its 192-line same-model
  settlement extension applies protected mutation-marker callbacks, definite
  recovery, uncertainty quarantine, and relaunch outcomes without a task
  registry or state store. The attachment transport, persistence, and recovery
  runtimes retain their authorities, while the event extension forwards only
  typed effects without giving either bridge a repository or event stream
- a bounded 225-line `SessionListModelManagement` extension that owns Claim and
  Rename presentation, eligibility, exact-owner capture, and runtime callbacks;
  `SessionManagementRuntime` retains authenticated status/open/rename requests,
  task and dialog lifecycle, and independent generations, while successful
  Claim ownership and transcript projection remain on the core session-state
  boundary and the bridge receives no repository capability or event stream
- a bounded 130-line `SessionListModelUsage` extension that owns usage/context
  and gateway-statistics presentation, actions, and immutable owner capture;
  the 132-line `SessionUsageRuntime` retains authenticated polling/retry state,
  while the independent 202-line `GatewayStatsRuntime` retains statistics
  loading/error state; each owns only its typed capability, task, generation,
  and immutable owner while the bridge receives no capability or event stream
- a bounded 185-line `SessionListModelDelegation` extension that owns delegated
  state forwarding, visible transcript projection, controls, child navigation,
  fixtures, and runtime callbacks; the event extension retains ordered decoding
  and forwards typed delegation effects without giving the bridge an event
  stream or repository capability
- a bounded 128-line `SessionListModelVoice` extension that integrates ordinary
  dictation, spoken replies, and app/surface lifecycle responses with the
  displayed session; a separate 218-line `SessionListModelTalk` extension owns
  Talk-first voice routing, owner/listening gates, callbacks, controls, and
  optimistic submission/failure projection. Neither has a repository capability
  or event consumer
- a `SessionEventRuntime` narrowed to `HermesEventStreaming` that owns the only
  repository-event task, visible assistant-delta coalescer and cadence timer,
  lossless structural/session-switch flush barriers, hidden-session bypass, and
  publication accounting; it forwards structural events through the dedicated
  `SessionListModelEvents` core boundary, which orders same-model settlement and
  projection stages without giving any stage another consumer or router
- a 235-line `SessionRuntimeComposition` construction root that unwraps the
  18-slot production capability bundle once, gives each feature runtime only its
  narrow protocol, preserves shared voice/speech, draft/persistence, and
  navigation identities, and supplies the fixture initializer's no-op graph
  without duplicating runtime construction in `SessionListModel`
- four capability-owned session-fixture sources compiled only for Debug and
  LocalRelease deterministic test/performance/visual payloads: the 253-line
  `SessionListFixture` catalog owns session-directory metadata, the 267-line
  `SessionControlFixture` owns blocking/goal/model/composer/attachment control
  state, the 240-line `SessionTranscriptFixture` owns live/stored repository
  messages, and the 97-line `SessionTranscriptPresentationFixture` exclusively
  owns rendered transcript entries and their embedded preview; the model's
  shared fixture initializer is guarded by the same build condition, and App
  Store Release compiles none of these contracts or payloads
- five capability-owned model-test-double sources: a 63-line audio-input/output
  source, 133-line pin-store source, 251-line protected text/photo-store source,
  53-line attachment-cache source, and 734-line integrated repository source.
  The repository actor remains whole so model integration tests exercise the
  real capability composition shape, while unrelated infrastructure no longer
  shares a 1,226-line catch-all
- bounded same-class model regression sources: a 4-line class identity and
  eleven behavior-owned extensions separately cover creation,
  management/pins/goals, navigation/ownership, ordered events/timelines,
  turns/drafts, blocking prompts, voice/usage/delegation, background lifecycle,
  attachment delivery, attachment recovery/media, and commands/models. The
  sources range from 336 to 847 lines; a 195-line helper extension owns reusable
  fixture builders and eventual assertions, while the five bounded doubles
  sources retain test infrastructure. All 134 tests keep their original
  `SessionListModelTests` discovery identity, and the 93 tests moved from the
  former core reconstruct byte-for-byte from the feature files
- a `SessionOwnershipCoordinator` that remembers terminal provenance across
  partial pages and reconnects, routes terminal sessions to durable history, and
  lets an explicit successful Claim override the remembered source
- a `SessionNavigationRuntime` narrowed to `HermesSessionServing` and split
  behind its unchanged API: the 198-line core owns immutable gateway/display
  contracts, the sole capability and task/operation-ID state, initial directory
  reads, source/history lookup, open/create/status operations, cancellation, and
  reset; its 166-line same-runtime task lifecycle owns five-second directory/
  status/read-only-history refresh, foreground display reconciliation, and
  attached-turn authoritative refresh without another capability or event path.
  The gateway/navigation model extensions apply lifecycle outcomes, while
  `SessionListModelEvents` retains the single ordered event application boundary
- the Android-aligned collapsed/expanded session shell, deterministic Debug-only
  brand and empty fixtures, search/source projection, pinning, and stable
  selectors; the no-session primary create action and collapsed-strip
  right-swipe share one availability contract, while exact scroll geometry
  admits the swipe only at the true leading edge and programmatic selection
  keeps non-leading pills centered; a simultaneous down-dominant pull gesture
  expands the list without claiming horizontal strip interactions;
  source-aligned selection/confirmation haptics are emitted only after the
  create gesture crosses or commits its threshold
- session creation reserves the display owner before suspension, synchronously
  flushes any pending protected text draft before the Hermes mutation, and
  leaves live-session drafts parked under their old owner; creation from a
  missing owner promotes ordinary photo drafts to recovery markers before the
  RPC, then exact-CAS migrates the protected prompt, photos, and every recovered
  marker to the new durable/live owner under a display-generation commit guard
- the Android-aligned CLI/TUI read-only bar and Claim confirmation, including a
  fresh runtime-busy check immediately before `session.resume`
- one shared stored/live transcript projection, owned by the bounded timeline
  extension, with Android-compatible stable history IDs, assistant-segment
  reconciliation, consecutive-tool grouping, active todo projection,
  protocol-noise filtering, attachment/media parsing, and authoritative history
  replacement after attaching to a turn mid-stream
- a `SessionTimelineRuntime` that owns the bounded eight-session offscreen
  timeline cache, exact live/stored indexes, LRU eviction, per-session
  transcript coordinators, synchronous hidden-event projection, and guarded
  mid-turn restoration while the event runtime remains the sole stream consumer
  and the timeline extension owns visible transcript presentation
- a native transcript surface for user, assistant, system, standing-goal,
  terminal/tool, todo, diff, image, attachment, and active-plan rows, including
  assistant copy, grouped-tool expansion, cursor-free incremental assistant
  rendering, and Android-aligned block Markdown structure and language-scoped
  syntax highlighting
- bounded transcript feature sources: `TranscriptView` owns only the SwiftUI
  shell and transient disclosure state; the 98-line `TranscriptViewport` owns
  bridge inputs and `UIViewControllerRepresentable`; the 98-line
  `TranscriptViewportController` owns row-host/update ordering, update
  signposting, and accessibility projection while delegating all scroll
  mechanics to one 350-line `TranscriptViewportPositionRuntime`. That runtime
  owns the sole collection view and `UICollectionViewDelegate`, scroll-owner
  coordination, pending offsets, resize/inset preservation, layout settlement,
  UIKit offset application, and anchor publication. A separate 63-line
  collection-view source owns the compositional layout and configured-view
  factories, root constraints, and layout-callback subclass without scroll,
  row-host, coordinator, or accessibility-ID authority; the 65-line
  CoreGraphics-only `TranscriptViewportPositionPolicy` owns reusable offset
  bounds/clamping,
  bottom tolerance, and viewport-shrink preservation without UIKit, a scroll
  owner, or coordinator access; the stateless 62-line
  `TranscriptViewportRowFactory` alone maps immutable viewport items/actions to
  launchpad, entry, and grouped-tool SwiftUI roots; the 68-line
  `TranscriptHostingCell` owns hosting transfer and self-sizing; the 139-line
  `SessionLaunchpad` owns empty-session command
  discovery and selection; the 227-line `TranscriptMessageRows` owns central
  entry/role dispatch, assistant Markdown/copy state, and the user bubble, while
  the 112-line `TranscriptMediaRows` exclusively owns decoded-image/fallback
  presentation and tappable attachment cards. The 85-line
  `TranscriptCommandRows` owns
  expandable command output, and the 84-line `TranscriptNoticeRows` owns system
  and standing-goal notices; the 221-line `BlockingPromptView` owns fail-closed
  prompt-card framing, kind dispatch, resolved summaries, and accessibility,
  while the 230-line `BlockingPromptActions` owns clarification selection/text
  state plus reusable action and status controls without response-policy or
  secure-entry authority; the 123-line `BlockingPromptOverlays` owns secure
  response and permanent-approval confirmation surfaces;
  the 189-line `TranscriptToolActivityRows` owns grouped-action disclosure,
  reduced-motion ripple feedback, heading/status, duration/count, and current-
  action presentation; the 210-line `TranscriptToolRows` independently owns the
  one specialized-card dispatcher plus default/terminal tool cards; the
  110-line diff and 123-line todo sources own their specialized cards and active
  plan; and a 72-line support source owns shared status/elbow primitives,
  formatting, and the collection helper used across tool surfaces; the
  architecture contract caps all twenty-two sources independently and retains
  a strict 3,190-line aggregate; the current surface is 3,157 physical (3,179
  component-counted) lines
- a `TranscriptScrollCoordinator` whose state is keyed by exact gateway and
  stored session, preserves the first visible row for parked readers, re-arms
  only for a fresh user entry or explicit jump, and keeps anchored content
  pinned through viewport and asynchronous content-size changes
- an Android-aligned floating composer driven by the session model, with
  optimistic prompt rows, pending steering rows, Stop generation fencing,
  ordered delivery recovery, and per-owner draft restoration
- a `SessionComposerRuntime` that owns the visibility-independent per-owner
  text projection, restoration flags, admission-ordered failed-input recovery,
  gateway invalidation generations, and deferred steer/operation notices; the
  bounded composer bridge retains only the currently rendered composer plus
  draft presentation and callbacks, while event application stays in the
  dedicated event extension
- a 245-line `SessionDraftPersistenceRuntime` core narrowed to
  `ComposerDraftStoring`; it remains the sole store, protected-record mirror,
  replaceable-write-task registry, and monotonic timestamp authority while
  owning restore, exact-claim tombstone/rollback, retirement, and missing-owner
  migration CAS; its 122-line same-runtime write extension owns text writes,
  flushes, recovered-draft persistence, debounce/cancellation, and failure
  delivery without introducing another capability, state authority,
  repository, or event boundary
- a `SessionDraftLifecycleRuntime` that composes protected text authority with
  the composer projection; it owns ordinary restoration, exact claim
  flush/retirement and rollback, admission-ordered failure persistence, and
  offscreen notice routing while returning immutable presentation changes to
  the app model and never consuming stream events
- a 121-line `SessionAttachmentPersistenceRuntime` core narrowed to
  `AttachmentDraftStoring`; it exclusively declares the protected photo-record
  and mutation-marker mirrors, revision/timestamp state, and restoration/
  quarantine ownership. Its 226-line same-runtime transaction extension is the
  only source that invokes the storage capability and owns draft updates,
  marker CAS, snapshot restoration, guarded migration, and best-effort
  quarantine persistence. A 187-line same-runtime recovery-lifecycle extension
  composes those primitives for ordinary-photo promotion, missing-owner
  migration, recovered-marker editing, and disconnect quarantine without
  invoking storage directly, while the 121-line
  `SessionAttachmentRecoveredEditRuntime` subordinate owns only replaceable
  edit tasks and bounded exact-CAS retries through supplied operations and
  marker-projection callbacks
- an independently bounded 180-line `AttachmentDraftContracts` source for the
  immutable photo/marker/migration values, narrow storage capability, and safe
  errors; the 172-line `AttachmentDraftStore` core remains the sole protected-
  file, removed-gateway fence, versioned-envelope, validation, and conflict-
  application authority, while its 224-line same-actor transaction extension
  owns exact draft updates, marker transitions/recovery, guarded multi-record
  migration, and gateway erasure without another store, state owner, envelope,
  capability declaration, or file-protection policy
- a bounded 264-line `SessionAttachmentRecoveryRuntime` core that composes
  protected attachment state with read-only navigation for process-relaunch
  restoration, durable-history acceptance proof, stale-runtime quarantine, and
  missing-owner recovery; its bounded 163-line same-runtime composer extension
  owns marker reconstruction and edit rollback without navigation, task state,
  storage-protocol ownership, or stream events
- a `SessionCreationDraftRuntime` that composes the text-persistence,
  attachment-persistence, and composer runtimes into one fail-closed
  missing-owner creation handoff; it captures immutable plans, promotes ordinary
  photos to durable marker authority before the create RPC, and retargets text,
  photos, markers, and in-memory composer ownership behind the creation bridge's
  immutable request-generation commit fence without owning network or events
- a `SessionTurnRuntime` narrowed to `HermesTurnServing`; it owns ordinary
  prompt, steer, and Stop transport tasks, fail-closed delivery uncertainty,
  gateway-reset fencing, and late Stop invalidation, while the bounded turn
  bridge retains optimistic transcript, draft-recovery, and background-turn
  projection and the event extension retains the ordered application boundary
- Android-aligned camera/gallery photo intake, the 64-point pending-photo strip,
  photo-only and text-plus-photo sends, and native media/file cards; a
  165-line read-only `HermesAttachmentReading`-narrowed `SessionMediaRuntime`
  core solely declares the read/cache capabilities, viewer state, and
  viewer/preview task and failure registries; its 243-line same-runtime preview
  extension owns two-request/eight-image reconciliation, MIME-checked hydration,
  retention projection, exact owner/generation validation, and per-operation
  UUID completion without a second authority, while the bounded model-facing
  media extension owns only displayed-session projection and the event
  extension retains the ordered application boundary
- a bounded 158-line `SessionAttachmentRuntime` core narrowed independently to
  `HermesAttachmentMutating`, `HermesPromptServing`, and
  `HermesDisconnectServing`; it solely declares the capabilities,
  `AttachmentDeliveryCoordinator`, task registries, timeout configuration, and
  lifecycle generation while owning response/event correlation, server-path
  leases, quarantine, and reset. Its bounded 279-line same-runtime delivery
  extension owns upload/prompt execution, start-confirmation timeout,
  generation validation, and fail-closed uncertainty classification without
  another capability or state authority. The independent attachment-persistence
  runtime owns protected recovery authority, the bounded attachment bridge owns
  visible integration, and the event extension retains ordered application
- strict slash discovery/completion/execution with a fail-closed mobile policy,
  bounded alias routing, native model/reasoning commands, owner-scoped recovery,
  and a native completion palette
- exact session model/reasoning RPCs and an Android-aligned model picker whose
  332-line overlay owns sheet status and reasoning; its former 486-line catalog
  component has been narrowed into a 280-line search/focus/provider-state owner
  and a 180-line same-view row/pin interaction extension; a 59-line Foundation
  policy has become a 97-line stateless catalog projection that owns normalized
  filtering, pinned grouping/sorting, scope notices, deterministic ordering,
  and capability/pricing labels; a 34-line text component owns the Compose
  bridge, and a 116-line confirmation component keeps expensive changes fail
  closed; protected
  gateway-scoped provider-aware pins retain unresolved-pin handling and FIFO
  persistence, and the split removes the former unreachable custom glyphs
- Android-contract voice recording and transcription, ordinary composer
  dictation, opt-in spoken replies, global Hermes voice configuration, and a
  `SessionVoiceInputRuntime` narrowed to `HermesTranscriptionServing` that owns
  default transcription adapter, shared microphone coordinator, one voice-event
  task, Talk-first dispatch, and ordinary-draft phase projection; Talk shares
  that runtime while the bounded model-facing voice extension retains session
  and lifecycle integration and the event runtime exclusively retains
  authoritative Hermes event-stream access
- a full-screen Talk mode whose recognition, remote-turn, synthesis, playback,
  pause, blocking-input, and relisten phases are owner/generation fenced; its
  bounded orchestration surface, reusable orb/control source, and Foundation-
  only phase-to-copy/action policy are independently reviewable
- a `SessionGoalRuntime` narrowed to `HermesGoalServing`; its bounded core owns
  authoritative owner synchronization, progress/status reconciliation, and
  observable presentation state, while the bounded `SessionGoalMutations`
  extension owns only the four standing-goal RPC command flows. One
  independently typed `SessionGoalMutationLifecycle` owns replacement and
  cancellation of the mutation task plus mutation-token generation and
  validation without becoming another observable goal authority. Its
  `GoalStatusRuntime` child receives only
  `HermesGoalStatusServing` and owns authoritative lookup/refresh tasks, while
  stable contracts and pure admission/event/status reduction live separately;
  the bounded model-facing goal extension retains prompt delivery and
  exact-owner settlement while the event extension retains event-driven
  transcript integration
- bounded standing-goal presentation: the 87-line `GoalView` owns the sole
  modal, draft/budget state, dismissal, and active/creation routing; its
  store-free 242-line `GoalSheetCreation` extension owns quick-start, objective,
  budget, and submit rendering without another model/state/modal owner; its
  201-line same-sheet `GoalSheetDetails` extension owns active-goal
  details/actions without stored state; the stateless 36-line
  `GoalPresentationPolicy` is the single phase-to-label/color mapping; and the
  independently bounded 128-line `GoalStatusCard` owns persistent status/actions
  plus the shared target glyph
- a `SessionUsageRuntime` narrowed to `HermesSessionUsageServing` and an
  independent `GatewayStatsRuntime` narrowed to `HermesGatewayStatsServing`;
  each owns its task, generation, observable state, and immutable owner snapshot,
  while the model-facing usage extension owns forwarding and owner capture
- bounded usage presentation sources: the 190-line `ContextBreakdownSheet`
  owns context composition and token formatting; gateway statistics use a
  149-line sheet shell, 74-line content router, 113-line summary-card source,
  113-line row/section source, 125-line heatmap, and 38-line formatter source;
  and the Foundation-only 170-line `GatewayStatsProjection` retains UTC momentum
  and 13-week heatmap math. An architecture boundary enforces unique component
  ownership, individual caps, and a 650-line statistics-presentation aggregate
- a production `SessionDelegationRuntime` narrowed to
  `HermesDelegationServing` and split behind its unchanged API: the 128-line
  observable core retains projection/event admission, the sole capability and
  coordinator, task/generation/gateway state, cancellation, and reset; its
  247-line same-runtime async lifecycle owns interrupt, snapshot-load,
  reconciliation, and persistence operation bodies without another repository
  owner or event path. The 158-line model-facing delegation extension owns
  production projection, controls, navigation, and ordered-event callbacks. A
  206-line sample catalog plus 40/31-line runtime/model adapters are entirely
  `#if DEBUG`, so Release compiles no delegation sample payload or fixture
  mutation surface
- a single delegation authority split between a bounded 289-line
  `DelegationCoordinator` core for live-owner binding, multi-agent turn grouping,
  parent settlement, and transcript anchoring; a 140-line
  `DelegationInterruptLifecycle` owns interrupt admission, monotonic request
  fencing, target lookup, and status transitions behind the unchanged coordinator
  API; and a 185-line same-type `DelegationSnapshotLifecycle` extension owns
  snapshot loading, reconciliation generations, persistence claiming, and history
  trimming. The 85-line `DelegationPresentation` source owns stable
  UI/owner/request contracts,
  while the pure 272-line `DelegationAgentReducer` normalizes sparse events and
  projects UI/snapshot representations without lifecycle or persistence authority
- bounded delegated-agent presentation sources: the 164-line group surface owns
  overview/transcript orchestration, the 109-line row owns summary disclosure,
  the 204-line detail owns expanded output and controls, and the 164-line support
  source owns status, duration, aggregate, and text primitives. Their shared
  architecture contract enforces unique ownership and a 675-line aggregate cap
- a 139-line `SessionLifecycleRuntime` that owns foreground/background history,
  connection-loss and background-turn-started callbacks, and the exact-owner
  background-turn coordinator without receiving a repository or event stream;
  the event extension retains authoritative reconciliation and its sole ordered
  Hermes event-application method
- an exact-owner `BackgroundTurnCoordinator` that tracks one active
  gateway/stored-session/live-runtime target plus a deduplicated FIFO, preserves
  uncertain mutations and retryable disconnects, settles definite failures,
  reconciles missed terminal events only from reconnect snapshots, and prevents
  an ordinary status poll from manufacturing completion
- four bounded Core notification boundaries: 65-line route validation/buffering,
  a 156-line finite background-execution and generic scheduling controller, a
  127-line permission/education/persistence owner, and a 47-line app delegate
  that installs the notification-center delegate and forwards accepted taps.
  Completion content still contains no transcript or live-runtime identifier,
  while routing remains fail-closed through a saved gateway and stored session
- an optional iOS biometric app lock whose `@MainActor` state boundary covers
  all app content before cold-launch restoration, places an opaque privacy
  shield over inactive snapshots, requires a fresh biometric result after
  backgrounding, and leaves underlying content hidden from accessibility while
  locked. Its state machine, Foundation-only contracts, non-secret preference
  adapter, and `LocalAuthentication` adapter are independently bounded; the
  platform adapter translates `LAError` into a stable domain failure before it
  reaches presentation. The overlay source retains the alert-plus-one window
  level, modal accessibility root, prior-key-window restoration, and no app-
  graph or notification authority

The adaptive type and motion policy follows Apple's supported SwiftUI
environment contracts rather than maintaining a parallel user preference:

- [Scaling a custom font relative to a text style](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:))
- [Dynamic Type size](https://developer.apple.com/documentation/swiftui/dynamictypesize)
- [Reduce Motion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [UILabel line-break strategy](https://developer.apple.com/documentation/uikit/uilabel/linebreakstrategy)
- [No paragraph line-break strategy](https://developer.apple.com/documentation/uikit/linebreakstrategy/nslinebreakstrategynone)

### Domain

`Sources/Nile/Domain` contains immutable, `Sendable` value types and repository
contracts.

Implemented:

- `GatewayEndpoint`
- `GatewayConnection`
- `CleartextPermission`
- the complete immutable Android domain-model inventory, partitioned by gateway,
  session, stream-event, model, usage, media, delegation, command, and goal
  ownership
- the complete async Hermes operation inventory, with independently injectable
  capability protocols and their fail-closed defaults colocated with the domain
  values they consume

`GatewayEndpoint` rejects ambiguous origins, credentials, queries, fragments,
encoded slash/backslash forms, dot segments, invalid ports, and missing schemes.
Its 88-line value/URL-construction surface delegates canonicalization and all
input validation to a 173-line `GatewayEndpointParser`; the parser has no token,
cleartext-permission, or connection authority. A separate 66-line
`GatewayConnection` source owns the credential plus build-gated per-profile
cleartext admission, without duplicating URL parsing or encoding. The parser
canonicalizes default ports and preserves clean reverse-proxy prefixes. An
architecture contract enforces unique endpoint/parser/permission/connection
ownership, 105/190/85-line caps, and a 350-line aggregate.

Nine feature-owned contract sources replace the former 722-line `Models.swift`
and 460-line `HermesRepository.swift` catch-alls. Each source is below 200 lines,
and an architecture boundary requires every primary domain declaration to have
one owner, retains an aggregate growth cap, and rejects reintroducing either
grab-bag file.

`SessionRepositoryCapabilities` is the session composition boundary. A
`SessionRepositoryCapabilityProviding` implementation may assemble its 18
slots from independent collaborators. Production now supplies the transport-
backed `TuiGatewayRepository` for shared capabilities plus separate delegation,
session, turn, Talk, command, goal, blocking-prompt, model, usage, attachment,
and speech services; tests may substitute the same or further-separated
implementations. `HermesLiveRuntimeStatusServing` lets the Talk service compose
prompt submission with only the session status operation it needs. The goal
service depends only on `HermesCommandServing` for its command-shadow safety
check, while session history, dashboard-backed usage, attachment downloads, and
speech share one actor-isolated active-connection primitive with the repository.
`SessionRuntimeComposition` unwraps the bundle once and passes each feature
runtime its exact narrow protocol; `SessionListModel` retains the constructed
runtimes but no capability bundle or stream protocol. Gateway connection
lifecycle remains outside the session bundle, and the same speech service
exposes global Hermes voice configuration through the app composition root.
This avoids an app-wide all-capabilities repository requirement without
introducing a second ordered event consumer. Convenience
overloads and fail-closed defaults remain beside the domain capabilities instead
of in gateway or app layers. Attachment
downloads and mutations are independently injectable through
`HermesAttachmentReading` and `HermesAttachmentMutating`; their composite
`HermesAttachmentServing` remains useful for unified gateway implementations.

### Gateway data layer

`Sources/Nile/Data/Gateway` owns exact wire representations.

Implemented:

- a typed recursive `JSONValue`
- newline-delimited JSON-RPC request encoding
- strict inbound response/notification dispatch
- strict `gateway.ready` and known session-event envelope validation
- forward-compatible ignoring of unknown notifications/events
- fail-closed blocking-prompt payload behavior
- strict result/error response validation and positive integral IDs
- a cookieless ephemeral REST status client with strict object-response validation
- a production `URLSessionWebSocketTask` adapter
- an actor-isolated newline JSON-RPC client whose 506-line transport core is the
  sole connection-attempt, generation, receive-loop, signal, and terminal-effect
  owner. Its 140-line same-actor request lifecycle isolates positive request-ID
  allocation, pending-call correlation, encoding, send/deadline/cancellation
  cleanup, and response settlement without another socket or connection state
- a dedicated 163-line connection-failure policy that distinguishes explicit
  HTTP/WebSocket authentication, host, redirect, protocol, and retry outcomes;
  bounds close reasons and redacts credential query values. The client shares a
  58-line gateway synchronization source for connect/request deadlines and
  one-shot continuations without exposing actor-owned connection state
- exact Android auth-mode discovery: status 404 selects reusable legacy token;
  successful status must contain Boolean `auth_required`; gated mode never falls
  back to the reusable token
- bounded gated-authentication sources: a 22-line Foundation-only contract
  source owns session cleanup, scope-conflict error, and authentication-expiry
  event values without transport, cookie-store, policy, request, task, or actor
  authority. The 237-line service actor remains the sole owner of serialized
  ticket/logout and managed-REST I/O, expiry publication, transport/cookie
  capabilities, and saved-profile scope checks. A transport-free 90-line HTTP
  policy exclusively owns ticket/logout paths, bounded POST construction, safe
  401 admission, retry classification, and fail-closed ticket decoding; a 91-line
  `GatewayCookieRotationGate` actor exclusively owns lock/waiter state, FIFO
  admission, cancellation shielding, and interruptible rotation release without
  request, profile, cookie-store, or event dependencies. Cancellation cannot
  discard an admitted rotation or resurrect cookies after cleanup. The 80-line
  `WebKitGatewayCookieStore` owns only persistent `WKHTTPCookieStore`
  reads/writes/deletes, so HttpOnly values never become observable UI state.
  Architecture guards cap the contract/actor/HTTP-policy/rotation/store/cookie-
  policy sources at 35/255/110/105/95/205 lines and their aggregate below 725
- one 190-line stateless `GatewayCookiePolicy` owns URL containment, overlapping
  profile detection, domain/path/expiry/secure matching, `__Host-` and
  `__Secure-` eligibility, and selective cleanup. External attachment downloads
  remain cookieless; overlapping same-host profile paths are rejected before
  tickets or cookies are used; a pending connection is persisted only after the
  post-sign-in ticket/ready retry succeeds
- bounded session wire projection: a 137-line `GatewaySessionCodec` owns only
  session-list, live-session, active-status, and session-info decoding; a
  156-line `GatewayStoredSessionCodec` exclusively reconstructs persisted
  messages, correlates stored tool calls/results, and flattens multimodal
  history; and a transport-free 37-line `GatewaySessionMessagePolicy` shares
  private goal-continuation filtering and model-switch notice projection across
  both schemas. Context-category decoding has one owner in `GatewayUsageCodec`
- exact event-to-domain projection for every currently allowlisted transport
  event through one 136-line repository-facing dispatcher. Strict fail-closed
  blocking prompts live in a stateless 166-line payload projector, goal and
  compaction interpretation lives in a stateless 143-line status projector,
  and typed subagent validation lives in a stateless 149-line payload projector.
  The dispatcher retains message, tool, review, session-info, and error routing
  without introducing another ordered event consumer; architecture guards cap
  the four sources at 155/155/180/165 lines and the aggregate below 620 lines
- one 193-line production repository composition root for connection and
  ordered events. Its two public initializers delegate to one capability-
  composition path, construct the shared active-connection state exactly once,
  and expose no session, prompt, turn, attachment, speech, or voice RPC methods
- one 4-line `TuiGatewayRepositoryTests` identity with its 33 transport
  contracts owned by seven capability extensions for session/history,
  turn/blocking prompts, attachments/commands, models, speech/voice,
  goals/usage, and ordered events/delegation. Those sources range from 199 to
  360 lines; a separate 275-line support source owns the recording RPC,
  dashboard, voice, and connection fakes instead of mixing infrastructure into
  capability behavior
- a dedicated 131-line `GatewaySessionService` for session list, stored history,
  resume/create/title, and stored/runtime status. Its architecture contract
  enforces unique live/stored/policy ownership, individual 150/175/50-line
  codec caps, and a 350-line aggregate; a 64-line `GatewayTurnService`
  for prompt submit, steer, and interrupt; and a transport-free 31-line
  `GatewayTalkService` that composes `HermesPromptServing` with the narrow
  `HermesLiveRuntimeStatusServing` capability
- a dedicated 103-line `GatewayAttachmentService` for exact
  `image.attach_bytes` and `image.detach` calls plus bounded attachment
  downloads. The cookieless transport disables automatic redirects, strips the
  legacy token before cross-origin redirects, rejects credential-bearing and
  HTTPS-downgrade targets, and permits unauthenticated external media only over
  HTTPS or loopback HTTP
- bounded dashboard boundaries: an 88-line capability source owns the
  independently injectable read/query/mutation/download protocol and its
  fail-closed defaults; the 197-line JSON core funnels ordinary reads, queried
  reads, and mutations through one authenticated, bounded object-request path;
  an 86-line transport-free response policy exclusively owns safe error
  details, retry classification, and exact profile-scoped login validation for
  JSON, authentication, and download consumers; the 127-line download extension
  owns request execution, credential attachment/stripping, manual redirect
  sequencing, and response bounds; and a transport-free 240-line download
  policy owns managed path translation, external/downgrade admission, and safe
  filename parsing.
  Login validation and redirect handling share one 33-line default-port-aware
  origin policy rather than client-owned duplicate comparison mechanics. The
  architecture contract enforces 100/220/100/140/255/45-line caps, unique
  response-policy ownership, and a 790-line complete dashboard aggregate
- a proxy-aware, ephemeral dashboard REST reader for legacy-token profiles. It
  reads exact stored-session source and history paths, encodes each dynamic path
  segment, sends only `X-Hermes-Session-Token`, strictly requires top-level JSON
  objects, preserves Android's retry/auth-error classification, and accepts an
  advertised 401 login URL only when its origin and path exactly match the
  profile-scoped login endpoint
- a dedicated 124-line `GatewaySpeechService` for exact authenticated dashboard
  JSON requests to `/api/audio/transcribe`, `/api/audio/speak`, and
  `/api/niles/tts-config`, including Android request fields, byte/text bounds,
  strict JSON/base64/config codecs, safe error detail, and operation-specific
  unsupported-endpoint failures
- exact standing-goal status/set/pause/resume/clear, command
  discovery/completion/execution, session-usage, and dashboard-statistics
  contracts with strict response validation; delegation validation is further
  partitioned into a 43-line status decoder, a 155-line strict snapshot decoder,
  a 131-line outbound snapshot encoder, and a 232-line shared
  string/number/timestamp/input primitive boundary. Architecture guards keep
  save construction out of the decoders, load/list parsing out of the encoder,
  and cap the four-source aggregate below 590 lines
- a dedicated `GatewayDelegationService` that owns every delegation RPC and
  contributes `HermesDelegationServing` directly to the production capability
  bundle
- a dedicated `GatewayCommandService` that owns command discovery, completion,
  and execution over `GatewayCommandCodec`, plus a `GatewayGoalService` that
  owns goal collision checks, status, turn-budget validation, and mutations
  while depending only on `HermesCommandServing`
- dedicated `GatewayBlockingPromptService`, `GatewayModelService`,
  `GatewayUsageService`, `GatewayAttachmentService`, and `GatewaySpeechService`
  collaborators that own sensitive response mutations, model catalog/session
  controls, usage/analytics, attachment, and speech/voice transport
  respectively; all dashboard consumers share `GatewayConnectionState`, and
  the `GatewayRPCRequesting` seam lives independently of every service and
  repository implementation
- model transport composes a 260-line response-only `GatewayModelCodec` with a
  separate 52-line Foundation-only `GatewayModelArgumentPolicy`; the policy
  exclusively rejects blank, whitespace/control-corrupted, and reserved-flag
  model/provider arguments before any RPC and has no JSON, mutation-codec,
  repository, or transport authority
- a first-wins reconnect loop gated by `NWPathMonitor`, with Android's immediate
  first attempt, quarter-spread jitter, exponential 1-to-20-second cap, saved
  profile retention, and socket-plus-session restoration boundary
- scoped gated-session expiry events: only 401 responses inside a saved
  cookie-authenticated profile can request sign-in; advertised login URLs pass
  the same exact origin/path policy; duplicates and stale profiles are ignored

## Architecture enforcement

The `ArchitectureBoundaryTests` XCTest identity is partitioned by the boundary
it protects. A 150-line coordinator owns repository lookup, shared source
helpers, and the split inventory; nine extension sources independently cover
composition, session bridges, feature surfaces, general capability runtimes,
the command runtime, session runtimes, gateway clients, gateway services, and
persistence. Every extension is below 1,000 lines.

The inventory regression requires all 62 pre-split contracts plus the gateway
repository-test boundary to have one test-name owner, pins representative
contracts to the appropriate feature source, and caps the aggregate below
5,450 lines. The gateway-test boundary independently requires all 33 transport
tests and ten support declarations to have one source owner, enforces
capability-specific line caps, and keeps the complete test group below 2,150
lines. The setup-model boundary likewise requires all 30 lifecycle tests and 13
helper/fake declarations to have one owner across its six behavior and four
support sources, with individual caps and a 1,580-line aggregate ceiling. The
design-system boundary pins every Markdown entry, immutable contract, cache,
parser, inline, and table declaration to one source, rejects stateful cache and
rendering authority in the parser, and keeps all 12 design and Markdown sources
individually bounded and below a 1,825-line aggregate. The test splits preserve
their original XCTest class and method names, so discovery and historical result
continuity do not depend on file layout.

## Concurrency

Swift strict-concurrency checking is enabled. UI models are `@MainActor`.
Immutable connection failures, generation-tagged signals, the filtered async
sequence, and the narrow connection capability live in the 67-line
`TuiGatewayClientContracts` boundary. Its sequence accepts only an actor-supplied
`@Sendable` generation predicate and does not depend on the concrete client.
Transport state remains solely declared by the 506-line `TuiGatewayClient`
actor core, with one current connection generation, one receive task, and one
pending-call map. Its 140-line same-actor request lifecycle owns request
admission, positive IDs, per-call one-shots, timeout/cancellation cleanup, and
response settlement while delegating send-failure termination back through one
narrow core operation. The stateless
`GatewayConnectionFailurePolicy` classifies and redacts transport errors, while
`GatewayDeadline` and `GatewayOneShot` own only generic synchronization
mechanics. Disconnect fails all pending calls, and generation-tagged signals are
filtered when consumed so buffered events from earlier connections are
unobservable. `TuiGatewayRepository` consumes that one ordered signal queue and
projects frames and terminal failure into one `AsyncStream`; this prevents a
socket failure from overtaking completion frames. `SessionEventRuntime` is the
only app-layer consumer of that stream. It serially forwards structural events
to the sole private `SessionListModelEvents.consume(_:)` method on the main
actor, cadence-limits visible assistant deltas, and flushes any pending delta
before a structural event or session switch. The sole private consumer then
orders delegation/lifecycle settlement, blocking-input interception, terminal
resource settlement, and visible projection. Those same-model stages are
invoked only by that path and never open or consume a stream.
`GatewayReconnectCoordinator` owns exactly one retry task. It waits for an
`NWPath` whose status is satisfied, attempts immediately, then applies
quarter-spread jitter to exponential backoff capped at 20 seconds. A successful
WebSocket handshake moves the UI to restoring, not online.
`GatewaySetupModel` publishes online only after `SessionListModel` has freshly
listed sessions and reopened the preferred/current session. Foregrounding
replaces any old backoff with an immediate fresh loop; Settings, profile
replacement, removal, sign-in, and deinitialization cancel the loop.

Background turn ownership is independent of the visible session. Normal,
attachment, goal, Talk, and remote-command admissions capture the exact
gateway/stored-session/live-runtime tuple before crossing an async boundary.
`SessionLifecycleRuntime` owns the foreground/background transition history,
app callbacks, and coordinator access behind this policy, but has no repository
or event-stream capability. Authoritative status and stream results still enter
through the dedicated `SessionListModelEvents` boundary before it delegates the
resulting lifecycle effect.
Definite rejection and explicit Stop settle that tuple; ambiguous delivery and
retryable connection loss retain it. A reconnect's fresh active-status snapshot
can settle every target whose stored session is absent or idle, while the
ordinary five-second poll deliberately cannot. Settings asks the session model
only whether a target exists outside the requested gateway. If so, gateway
setup stages an immutable saved-profile confirmation without disconnecting,
selecting a profile, or stopping any turn. Dismissal clears only that staged
request. Confirmation consumes it exactly once, then the existing
gateway-will-connect boundary stops outside targets before transport ownership
changes. Selecting the already connected profile merely dismisses Settings;
old-connection loss cannot erase a staged switch, while successful removal of
its target does.

Android can keep an indefinite foreground service for an active turn. iOS does
not offer an equivalent general-purpose indefinite execution mode. Nile calls
`beginBackgroundTask` before a tracked turn, always ends the task on
completion/stop, and uses its mandatory expiration handler to requeue the exact
target. Expiration is not treated as turn completion: the socket/reconnect
snapshot remains authoritative. This is a finite best-effort continuation
window, not a claim that iOS will execute indefinitely:

- [Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time?changes=_1)

The notification-center delegate is installed by the app delegate before launch
finishes. Completion copy is intentionally generic (`Turn finished` /
`Open Nile to view the result`); routing metadata contains only the saved
gateway ID and optional stored-session ID. A tap is buffered across cold launch,
waits for live reconnect/sign-in work, rejects missing saved targets, opens the
gateway first, then selects the stored session. The system permission prompt is
requested only after Android-copy app-owned education and the choice is
persisted:

- [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate?changes=_2)
- [Requesting notification authorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization%28options%3Acompletionhandler%3A%29/)
- [Handling notification responses](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions)
- [UIApplicationDelegateAdaptor](https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor)

The 277-line `LiveTranscriptCoordinator` owns the currently open assistant
segment, reconciles authoritative completion, closes segments at chronological
tool/system boundaries, and delegates tool-row matching and mutation to the
97-line stateless `LiveTranscriptToolProjector`. That projector exclusively owns
the live-tool input/projection values, tool IDs, labels, kinds, timestamps,
incremental field replacement, and active-todo projection; it has no assistant
segment, parser, image-cache, task, event-stream, or Hermes authority. The
coordinator continues to bound its image cache through the separate payload
cache. Selection, stored-source, stored-history, refresh, and Claim work is
generation-fenced so a late response cannot replace a newer gateway or
selection. The refresh task is
cancelled on connection loss, and every Claim rechecks the live terminal status
at mutation time. The management bridge captures the displayed owner and
forwards runtime outcomes, but successful Claim still crosses a guarded core
method before terminal provenance, the live session, transcript, and usage are
changed. Composer mutations capture ordered recovery tokens by gateway and
stored-session owner. Prompt, steer, and Stop settlements are independently
generation-fenced, so late failure or acknowledgement cannot overwrite a newer
selection, edit, or turn.

`SessionTimelineRuntime` owns the memory-only timelines parked behind session
switches. It maintains exact live-to-stored ownership, replaces stale runtime
aliases, retains at most eight timelines through LRU eviction, and keeps a
dedicated `LiveTranscriptCoordinator` with each snapshot. `SessionEventRuntime`
remains the only event-stream consumer, routes hidden deltas synchronously to
the event-projection extension's offscreen path, and forwards structural events
through the core's one ordered application boundary. The projection extension
applies the timeline runtime's explicit session-status effect; the timeline
extension restores a cached transcript only when the authoritative resumed
runtime is still in flight and that exact live ID was previously observed.

`TranscriptScrollCoordinator` is retained by `SessionListModel`, not by a
particular transcript view, so switching sessions or gateways cannot alias
reading positions. SwiftUI geometry preferences record the first visible row
only while a vertical user gesture or its settling fling is active; programmatic
pins cannot release the bottom anchor. Content and viewport size changes re-pin
only an already anchored owner, while a newly observed user row always re-arms
the tail.

The transcript renderer keeps its public shell, bridge values, UIKit viewport
controller, position runtime, configured collection view, stateless row-root
factory, hosting cell, central message/media dispatcher, command rows,
system/goal notices, grouped/default tools, diffs, todos/plans, and shared row
primitives in separate bounded sources. The splits do not introduce a second
scroll owner, projection path, or tool dispatcher: every row still enters the
one `TranscriptViewportController`, its one row host invokes the value-only
`TranscriptViewportRowFactory`, and `ToolRow` still selects exactly one default,
diff, or todo card. The controller retains row/update ordering and accessibility;
the position runtime is the only collection-view delegate and retains scroll
coordination, anchoring, inset/resize settlement, and UIKit offset application;
the value-only position policy owns reusable geometry and resize-preservation
transitions; and the reusable cell independently owns only hosting-view
transfer, constraints, reuse cleanup, and self-sizing.

The 146-line `SessionBlockingPromptRuntime` owns the
`BlockingPromptCoordinator` plus event, binding, status, and projection
forwarding. Its 247-line `SessionBlockingPromptResponseLifecycle` collaborator
alone stores `HermesBlockingPromptServing`, one-shot response tasks, typed RPC
dispatch, and the reset generation that suppresses cancelled work from an old
gateway. Response values remain task-local. `SessionEventRuntime` remains the
sole stream consumer and forwards each individual event synchronously to the
dedicated event-application extension. A bounded 58-line
`SessionListModelBlockingPrompt` bridge owns response admission and visible
transcript/session-list projection without storing a capability or task. The
bounded 258-line coordinator core declares the one safe-record array and owns
event intake, live-to-stored binding, request deduplication, status-poll
watermarks, expiry, finalization, and transcript/attention projection. Its
same-type 281-line `BlockingPromptSubmissionLifecycle` extension owns response
admission, approval-FIFO actionability, secret-safe summaries, async settlement,
and retry/unavailable/uncertain transitions without declaring a second record
store or consuming events. Together they remain the sole mutable prompt-
lifecycle authority and keep uncertain responses non-retryable until runtime
finalization. A stateless event factory
owns exact Hermes-event-to-card interpretation, including visible,
non-actionable malformed requests. A separate pure policy owns timeouts,
response summaries, FIFO actionability inputs, uncertain-failure
classification, runtime-status normalization, and transcript-card replacement;
stable runtime/submission contracts live in their own small source. Passwords,
secrets, and free-text answers have no model or runtime field: ephemeral SwiftUI
state passes them into the response task, clears on submit/dismiss/session
switch/backgrounding, and uses privacy-sensitive masked entry.

`SessionTurnRuntime`, narrowed to `HermesTurnServing`, owns the ordinary prompt,
steer, and Stop transport tasks. It prepares prompt and steer RPCs off the main
actor, classifies definite versus connection-uncertain failures fail-closed,
generation-fences gateway replacement, and invalidates a late Stop
acknowledgement without cancelling unrelated delivery recovery. Goal prompts
share this lifecycle. `SessionDraftLifecycleRuntime` composes protected text
persistence with the per-owner composer projection for restoration, exact
claim retirement/rollback, ordered prompt/steer/command failure recovery, and
offscreen notice routing; the model receives immutable projection outcomes.
The 158-line `SessionAttachmentRuntime` core independently owns the three exact
attachment/prompt/disconnect capabilities, coordinator and task state,
response/event correlation, server leases, quarantine, and lifecycle reset. Its
279-line same-runtime delivery extension owns the upload-to-prompt task,
start-confirmation timeout/disconnect, generation checks, and definite versus
uncertain failure policy. The extension declares no capability, coordinator,
task registry, generation, repository, or event-stream authority.
The 121-line `SessionAttachmentPersistenceRuntime` core, narrowed to
`AttachmentDraftStoring`, independently declares the protected record/marker
mirrors, revision/timestamp state, and restoration/quarantine ownership. Its
226-line same-runtime transaction extension exclusively invokes that capability
for draft writes, marker CAS, snapshot restoration, guarded migration, and
best-effort quarantine persistence. The 187-line recovery-lifecycle extension
coordinates ordinary-photo promotion, recovered-session migration, marker
editing, and disconnect quarantine exclusively through those primitives,
without another object, state owner, or storage invocation. The 121-line
`SessionAttachmentRecoveredEditRuntime` subordinate owns only replaceable edit-
task identity, cancellation, and three-attempt CAS retries through narrow
operations supplied by the parent; it cannot own the store or marker
projection. The capability and its immutable values/errors are declared
separately from the protected-file actor. That actor's 172-line core alone owns
the protected file, versioned envelope, validation/conflict policy, and
removed-gateway fence; its 224-line same-actor transaction extension performs
draft/marker CAS, guarded migration, and gateway erasure without redeclaring
storage or state. Runtime consumers therefore cannot become coupled to storage
mechanics, while exact transactions remain independently reviewable.
`SessionAttachmentRecoveryRuntime` composes that authority with read-only
navigation to decide whether interrupted process state was durably accepted,
may be restored, or must remain quarantined. Its same-runtime composer
reconciliation extension folds ordinary text into marker authority, rebuilds
the in-memory text/photo projection, and rolls failed edits back to durable
markers. The extension has no navigation capability, stored state, task
registry, storage protocol, or stream-event dependency; the core continues to
return immutable presentation outcomes.
`SessionCreationDraftRuntime` composes those persistence primitives with
`SessionComposerRuntime` for the missing-owner create transaction: ordinary
photos gain marker authority before the RPC, then exact-owner text and
photo/marker migrations commit under the creation bridge's immutable
display/gateway fence before in-memory ownership advances. The bounded creation
bridge retains the create/list sequence and visible settlement; the core keeps
session-ownership coordination, the event extension keeps the ordered
application boundary, and the composer, turn, attachment-intake, and attachment-
settlement bridges retain their respective visible projection and recovery
presentation.

Photo encoding runs outside the main actor and publishes no bytes until the
protected draft revision commits. Photo delivery persists an upload-pending
marker before the first Hermes mutation, advances it before prompt submit, and
retires it only after a correlated stream start. A definite rejection detaches
every known lease before restoring the draft. A false, failed, interrupted, or
otherwise ambiguous detach/upload/prompt result keeps the exact owner closed.
After process recreation, the owner remains closed while its old live runtime
exists; once that runtime disappears, only durable user-history evidence may
prove acceptance, otherwise the exact text/photo draft is restored. Preview and
viewer work shares one media-runtime authority and remains selection/generation
fenced; its isolated preview extension permits at most two 2 MiB requests in
flight, while the core enforces the 32 MiB full-open bound.

Slash completion and execution capture the gateway/session/runtime owner before
crossing isolation boundaries. `SessionListModelCommands` is the bounded
model-facing bridge for composer/transcript projection and recovery; repository
access and catalog/completion state remain in the 185-line observable
`SessionCommandRuntime`, which owns the sole stored command capability. It
passes that capability only for an admitted operation to the non-observable
224-line `SessionCommandExecutionLifecycle`, whose isolated task registry owns
per-session exclusion, alias validation, uncertainty classification, and
gateway-reset cancellation. The 281-line
`NileSlashPolicy` is the sole fail-closed dispatch/native-routing authority,
while the 142-line `NileSlashCatalogPolicy` owns only catalog curation and
completion visibility and delegates every safety judgment back to that dispatch
policy. Neither domain policy has repository, task, or event-stream authority,
and authoritative events remain at the event extension's single ordered
boundary. Native commands reuse the same session-control
fences, and remote command recovery classifies definite rejection separately
from uncertain delivery so the draft is restored without inviting an unsafe
duplicate. `SessionListModelModelControl` is the bounded model-facing bridge for
picker projection, owner capture, live-session updates, and transcript notices.
The 227-line `SessionModelControlRuntime` core owns observable presentation,
catalog/pin coordination, and the sole mutation capability, task, generation,
session owner, pending-switch, and reset declarations. Its 285-line same-runtime
mutation-lifecycle extension owns model/reasoning admission, confirmation,
capability calls, owner-fenced settlement, and fail-closed uncertainty handling
without another runtime, repository owner, or event path.
`ModelOptionsRuntime` owns the replaceable catalog-read task behind the narrower
`HermesModelOptionsServing` capability, while `ModelPinRuntime` owns
gateway-scoped protected pin state and persistence. Admission, notice, failure,
provider, and legacy-pin rules are pure `ModelControlPolicy` operations, and the
stable owner/callback values live in `SessionModelControlContracts`. Model-pin
writes are enqueued synchronously on the main actor into an app-scoped FIFO,
committed by the protected store actor, and published only when the gateway and
latest mutation generation still match. `SessionListModel` remains the single
ordered Hermes event boundary.

Voice capture is split into bounded Core/Speech owners: the 43-line
`VoiceInputContracts` source owns the event/protocol/null-input surface, PCM
source capability, factory, and permission error; the 151-line `VoiceInput`
runtime owns availability, event publication, the single serial capture gate,
active-capture/generation fencing, terminal admission, and public start/stop/
cancel lifecycle; the 206-line immutable `VoiceInputCaptureOperation` owns PCM
source execution, VAD, bounded sample accumulation, WAV/transcription handoff,
and safe failure projection; and the 112-line `VoiceInputCapture` source owns
only the serial async-gate mechanics and lock-backed stop/cancel/terminal state.
The concrete `AVAudioEngine` source remains behind the PCM capability boundary,
delegates format conversion to the independently bounded
`SpeechAudioConverter`, and publishes 16 kHz mono PCM16 samples to the
Android-compatible processor. The operation applies the pinned RMS threshold
and silence/maximum-duration rules before producing canonical little-endian
PCM16 WAV bytes. The microphone is closed before Hermes transcription starts;
cancellation closes it synchronously and generation checks discard late private
results.

`VoiceInputCoordinator` owns one composer base string and never lets stale
callbacks replace a newer draft. The 96-line Foundation-only
`TalkModeContracts` owns phase/UI state, validated owner identity, and opaque
mode/turn/relisten tokens and decisions without task, capability, or runtime
authority. The 304-line `@MainActor` `TalkModeCoordinator` alone owns generation
and sequence counters, blank-result state, active tokens, and recognition/turn/
relisten transitions. Architecture guards enforce unique declarations,
325/110-line caps, and a 420-line aggregate. Tokens remain bound to one
connection/gateway/stored-session/live-runtime identity. A 279-line
`SessionTalkRuntime` core remains the sole stored-state and observable
declaration owner and composes that state machine with mode lifecycle, voice
capture, recognition, and prompt admission. Its 324-line same-type
`SessionTalkResponseLifecycle` extension isolates message/completion/error
handling, Stop recovery, speech playback, and relisten scheduling without a
second runtime or event path. Its subordinate
`TalkSubmissionRuntime` exclusively owns the narrow `HermesTalkServing`
capability, submission task/generation, and acknowledgement/early-terminal
correlation; stable callback contracts and the pure admission, settlement, and
failure policy live in separate bounded sources. Partial speech is deliberately
absent from transcript and model state. Only a confirmed streaming admission
may own the next assistant completion; queued, steered, early, stale, or
ambiguous outcomes pause instead of risking the wrong spoken reply.
Backgrounding, selection changes, blocking prompts, connection loss, and
surface dismissal close voice and playback.
`SessionListModelVoice` is the bounded model-facing bridge for ordinary
dictation, spoken-completion callbacks, and lifecycle responses.
`SessionListModelTalk` separately owns Talk-first voice routing, owner/gating
snapshots, controls, and optimistic transcript effects. Neither receives a
repository or event stream; the event extension applies every authoritative
event through one ordered method
before invoking the bridge.
Speech output sanitizes Markdown/media/protocol text, splits at natural
boundaries without breaking UTF-16 surrogate pairs, synthesizes sequentially,
and plays through `AVAudioPlayer`.

The Talk listening surface is split into a 246-line `TalkModeView` that alone
binds `SessionListModel`, blocking prompts, and runtime callbacks; a 118-line
`TalkModeControls` source that owns the reusable reduced-motion orb and semantic
bottom control; and a 74-line Foundation-only `TalkPresentation` policy that
maps every phase, blocking state, working label, and authoritative run state to
copy and the primary action without SwiftUI or model access. Architecture
contracts enforce 275/140/100-line caps, unique declarations, exclusions, a
500-line surface aggregate, and the retained global ceiling. The view preserves
the pinned Material close geometry, exact 64-point header, reduced-motion
188/172/132/84-point orb stack, and 92-by-75-point bottom actions over the
graphite canvas. Its app-owned listening state is source-paired to the exact
Android commit with zero masks, while the close, Transcript, Pause, and End
controls retain 44-point-or-larger semantic targets.

The global Hermes voice editor preserves the server-owned provider as read
only, stages preset or custom voice changes locally, and applies only a
non-blank changed identifier through the generation-fenced gateway model. Its
loaded Edge TTS state is source-paired to the exact Android commit: app-owned
sheet geometry, provider/current/preset/field/warning/action hierarchy, explicit
disabled colors, embedded Roboto/Droid Sans Mono roles, and 44-point-or-larger
semantic button targets are covered together without visual masks.

Goal and telemetry work is independently generation-fenced so stale status,
usage, or statistics responses cannot replace a newer gateway/session owner.
`SessionGoalRuntime` remains the one observable standing-goal authority. Its
core owns owner synchronization and event/status reconciliation;
`SessionGoalMutations` owns the full mutation capability and four RPC command
flows, while `SessionGoalMutationLifecycle` exclusively stores, replaces, and
cancels the mutation task and validates lifecycle/mutation tokens. Its
`GoalStatusRuntime` child owns the narrow read capability and independently
fenced lookup/refresh task.
`GoalRuntimePolicy` reduces admission, domain goal updates, status results, and
turn-boundary signals without transport or mutable state. `SessionListModelGoal`
supplies immutable gateway/display/session owner snapshots and performs ordinary
prompt delivery, while the event extension routes the runtime's synchronized
objective back into transcript annotation.
The persistent status card, modal/state core, store-free creation renderer, and
active-details renderer have independent source owners and size caps, preventing
lifecycle controls or a second state/modal authority from returning to creation
rendering.
`SessionUsageRuntime` owns session polling/retry behind the session-usage
capability, while `GatewayStatsRuntime` independently owns statistics loading
behind the gateway-statistics capability. `SessionListModelUsage` supplies
immutable owner snapshots and exposes lifecycle reset/refresh calls; the core
invokes those calls when selection, turn, or gateway state changes. Neither
runtime nor the model-facing bridge has a stream-event dependency, so
ordered events continue to enter through exactly one `SessionEventRuntime`
stream consumer and one `SessionListModelEvents` application boundary.
`DelegationCoordinator` keys live groups by gateway, parent session, and
multi-agent turn, accepts sparse out-of-order events without regressing terminal
agents, and settles a group only after the parent completion boundary is
observed. `DelegationInterruptLifecycle` exclusively owns active interrupt
requests, monotonic interrupt tokens, delegated-agent lookup, and status mutation;
same-type forwarding methods preserve the coordinator API without adding another
turn store. The `DelegationSnapshotLifecycle` extension isolates reconciliation,
snapshot restoration, persistence claiming, and bounded-history trimming while
the core remains the sole declaration owner of turn history and the only
live-event path. Reconciliation requests carry monotonic tokens and
snapshots are deduped before restoring settled history. Sparse field normalization
and event-to-agent merge/projection are delegated to the stateless
`DelegationAgentReducer`; it cannot access owner history, interrupt tokens,
reconciliation generations, or the clock. `SessionListModelEvents` remains the
only ordered Hermes event decoder; it forwards typed subagent updates and parent
completion effects to `SessionListModelDelegation`, which asks the runtime to
mutate coordinator state and reprojects only the visible transcript.

## Persistence and security

`ProtectedFileStorage` is the sole implementation of the Application Support
path, atomic write, after-first-unlock file protection, backup exclusion, and
idempotent removal mechanics shared by gateway metadata, composer drafts,
photo drafts, model pins, and session pins. Each domain store continues to own
its versioned envelope, validation, tombstones, and user-facing error mapping.
Gateway profile capabilities/errors, transactional envelope ownership, and the
protected-file/Keychain adapters live in three independently bounded sources;
only the adapter source imports Security or constructs `ProtectedFileStorage`.
`OrderedPersistenceQueue` likewise owns the one main-actor FIFO tail used by
model-pin and session-pin adapters, so actor suspension cannot reorder rapid UI
mutations.

Implemented optional biometric app lock:

- the non-secret opt-in flag is isolated in a 21-line `UserDefaults` adapter;
  it defaults off and is committed only after a successful biometric policy
  evaluation
- a 64-line Foundation-only contract source owns capability, biometry-kind,
  stable authentication-failure, storage, and authentication interfaces; the
  97-line platform adapter alone imports `LocalAuthentication`, creates
  `LAContext`, and maps every platform error into that domain failure
- the 187-line observable state machine owns enabled/locked/shield/authentication
  presentation, scene/background fencing, and exact failure copy without direct
  `UserDefaults`, `LAContext`, `LAError`, or `LocalAuthentication` access
- enabling first requires currently available and enrolled Face ID or Touch ID,
  so an unsupported device cannot accidentally enter a locked state
- cold launch begins covered when the flag is enabled; returning from the
  background requires a new biometric evaluation, and cancellation or failure
  remains fail closed behind an explicit retry action
- transient inactive states receive the same opaque privacy shield for safe app
  switcher snapshots, but require a new authentication only if the scene
  actually entered the background
- the interactive lock surface is hosted in a scene-bound window above
  app-owned presentation layers, so an existing SwiftUI sheet cannot remain
  visible or interactive; the root view retains an opaque, non-interactive
  fail-closed fallback while that window attaches, while the dedicated overlay
  source owns only UIKit window attachment and lock presentation
- all configurations provide `NSFaceIDUsageDescription`; Nile never receives or
  persists biometric data because LocalAuthentication and the Secure Enclave
  own evaluation

This is an intentional iOS security extension with no pinned-Android
counterpart. It follows Apple's LocalAuthentication and protected-resource
contracts:

- [Local authentication context](https://developer.apple.com/documentation/localauthentication/lacontext)
- [Biometric authentication policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics)
- [Face ID usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription)

Implemented profile storage:

- a 63-line `GatewayProfileContracts` capability/error boundary, 207-line
  `GatewayProfileStore` transaction actor, 146-line
  `GatewayProfileStoreCodec` deterministic envelope/validation boundary, and
  105-line `GatewayProfileSecureStorage` protected-file/Keychain adapter
  boundary; the codec has no actor, storage capability, protected-file, or
  Keychain authority
- non-secret profile metadata uses a versioned, deterministic JSON envelope in
  Application Support with atomic replacement and
  `completeUntilFirstUserAuthentication` data protection
- legacy tokens use generic-password Keychain items behind versioned credential
  pointers, with synchronization disabled and
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- each credential update writes a new Keychain item before atomically committing
  its metadata pointer; a failed metadata commit deletes the candidate while the
  previous pointer remains usable
- committed credential replacement/removal uses a persisted cleanup ledger, so
  process death or a transient Keychain deletion failure is retried before any
  profile is exposed
- metadata lives inside a backup-excluded directory because its
  this-device-only Keychain counterparts cannot migrate
- missing Keychain items, malformed metadata, duplicate identities/endpoints, and
  unsupported versions fail startup closed

Implemented composer-draft storage:

- the 245-line `SessionDraftPersistenceRuntime` core is the only session feature
  source that declares the store capability, in-memory protected-record mirror,
  write-task registry, or timestamp sequencer; its 122-line same-runtime write
  extension executes text writes, immediate flushes, recovered-draft
  persistence, debounce/cancellation, and failure delivery against those
  authorities; `SessionComposerRuntime` separately owns the per-owner text
  projection and recovery ordering; `SessionDraftLifecycleRuntime` composes
  them for ordinary restoration, claims, retirement rollback, recovered-draft
  persistence, and deferred notices, while the bounded composer bridge owns
  only the rendered composer and operation-specific presentation
- ordinary text drafts use a deterministic versioned JSON envelope in
  Application Support, atomically replaced with
  `completeUntilFirstUserAuthentication` data protection and excluded from
  backup
- each gateway/session owner advances a monotonic field revision and timestamp;
  stale or same-revision conflicting writes are rejected while exact replay is
  idempotent
- owner migration validates every expected source and destination record, then
  commits the complete text-record change set in one protected file replacement
- typing uses replaceable 350 ms writes and leaving the active scene requests an
  immediate flush
- Send and steer flush their captured recovery record before any Hermes
  mutation; an accepted mutation writes a newer empty tombstone, while a failed
  mutation rebases restored text ahead of newer local edits
- process restoration presents Android's duplicate-send warning, and deleting a
  gateway deletes all of its protected text records

Implemented photo-draft and attachment recovery storage:

- the `SessionAttachmentPersistenceRuntime` core is the only session feature
  object that declares the store capability, in-memory protected photo/marker
  authority, revision/timestamp state, and restoration/quarantine flags; its
  same-runtime transaction extension exclusively invokes the capability for
  writes, CAS, loading, migration, and quarantine persistence, while the
  recovery-lifecycle extension coordinates promotion, migration, recovered
  editing, and disconnect quarantine only through those primitives; its
  subordinate `SessionAttachmentRecoveredEditRuntime` owns only replaceable
  edit-task fencing and bounded retries through parent-supplied operations and
  marker callbacks; the bounded attachment-recovery core composes those
  primitives with read-only navigation for relaunch acceptance/quarantine,
  while its bounded composer extension reconstructs text/photo state through
  the core's existing dependencies and the attachment bridge applies only the
  returned visible presentation
- `SessionListModelCreation` composes immutable navigation and creation-draft
  outcomes for missing-owner creation without receiving protected-store,
  repository, or event-stream authority
- pending JPEG bytes and mutation markers use a versioned, atomically replaced
  Application Support envelope with
  `completeUntilFirstUserAuthentication` protection and backup exclusion
- every gateway/session photo revision rejects stale or conflicting writes;
  empty tombstones remain authoritative so a late writer cannot resurrect
  consumed photos
- ordinary draft ownership transfers atomically to an upload-pending marker,
  marker stage changes use compare-and-swap, and definite recovery transfers the
  bytes atomically back to a newer ordinary draft
- missing-owner creation promotes ordinary photo drafts before the remote
  mutation; after a successful create, all expected markers and photo records
  retarget in one protected file replacement only while the exact gateway and
  display generation still match
- recovered prompt edits consolidate into marker authority before the separate
  ordinary composer record is tombstoned; suffix-aware restoration makes an
  interruption between those two protected files idempotent, and a failed
  post-create migration leaves the source marker authoritative and visible
- the viewer cache is protected and backup-excluded, sanitizes filenames, and
  prunes oldest entries to at most 12 files and 96 MiB

Implemented model-pin storage:

- provider-aware pins use a deterministic versioned Application Support
  envelope with atomic after-first-unlock protection and backup exclusion
- legacy provider-less pins resolve only when exactly one catalog provider owns
  the model; unresolved pins remain visible and removable
- writes are FIFO and return the authoritative committed set; removing a gateway
  records a process-lifetime tombstone so a late queued write cannot resurrect it

Implemented session-pin storage:

- stored-session IDs use a deterministic, gateway-scoped versioned Application
  Support envelope with atomic after-first-unlock protection and backup
  exclusion
- UI changes are optimistic, while an app-scoped FIFO persists explicit desired
  values so rapid pin/unpin taps cannot invert across the actor boundary
- a failed write rolls back only when its desired value is still the visible
  intent; late results are gateway-generation fenced
- deleting a gateway removes its pins and records a process-lifetime tombstone,
  preventing an already queued write from recreating deleted local state

Apple documents the chosen Keychain accessibility as suitable for credentials
needed by background applications after the first device unlock, while keeping
items on the originating device. The matching file-protection level retains the
same after-first-unlock availability:

- [Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)
- [File protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication)

Gated dashboard state uses `WKWebsiteDataStore.default()` so the embedded login,
dashboard REST transport, ticket endpoint, and logout endpoint share the same
HttpOnly session. `WebKitGatewayCookieStore` performs cookie I/O only at that
boundary; the independent cookie-rotation gate serializes the read/request/save
sequence and shields admitted mutations from caller cancellation;
`GatewayCookiePolicy` filters values to the saved gateway URL scope and selects
only the chosen profile's eligible names/paths for deletion. None of these paths
writes cookie values into models, logs, fixtures, or artifacts. This follows
Apple's persistent-data-store and cookie-store contracts:

- [WebKit website data store](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
- [WebKit HTTP cookie store](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- [WebKit navigation delegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate)

Reachability is used only as a gate for when a reconnect attempt may run. A
satisfied path does not mean Hermes is healthy; only a completed gateway
handshake and session restoration do. The monitor is cancelled with its owner,
and network changes never bypass the first-wins retry coordinator:

- [Network path monitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- [Network path status](https://developer.apple.com/documentation/network/nwpath/status-swift.enum/satisfied)

Current build policy:

- Debug and LocalRelease include an ATS arbitrary-load exception and compile the
  explicit approval workflow so trusted local/VPN HTTP gateways can be tested.
- Release omits the exception, compiles out cleartext support, and therefore
  rejects arbitrary cleartext at both the app and platform boundaries.
- App logic requires explicit per-profile approval before any cleartext probe,
  dashboard sign-in credential use, or WebSocket connection.

The broad ATS exception is confined to non-App-Store configurations; it is not a
substitute for the app-level gate.

## Project generation

`project.yml` is authoritative and `Nile.xcodeproj` is checked in for direct use.
Regenerate after adding or moving source files. XcodeGen is a build-time developer
tool only and does not ship in the app.

The native app-icon asset is generated reproducibly from the canonical editable
`Artwork/NileAppIcon.svg` source:

```bash
swift scripts/assets/render-app-icon.swift \
  Artwork/NileAppIcon.svg \
  Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```
