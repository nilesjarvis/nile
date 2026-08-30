# Real-world user edge-case audit

Date: 2026-07-29

Android source of truth: `nilesjarvis/nile` commit
`bd5451da891f2d886b9bc35f8ea67d6920df1d98`, tree
`3b954e5844f05276d34aaee34a7d3f69169ef9f5`

## Method

This audit treats Nile as a remote-control surface for a long-running Hermes
assistant, not as a collection of isolated screens. Each scenario starts with a
specific real-world use, adds a failure or race that can occur outside a demo,
and maps that behavior to an existing deterministic unit/protocol or XCUITest.
The audit also added adversarial tests where the existing suite did not exercise
the discovered boundary.

The pinned Android checkout was verified before testing. The clean baseline
passed 422 unit/protocol tests, analyzer, optimized unsigned Release build,
secret scan, and disposable-Simulator cleanup at
`build/test-lab-results/20260728T225151Z-96928`.

## Scenario inventory

| Area | Real-world example and edge case | Primary evidence | Result |
| --- | --- | --- | --- |
| Gateway onboarding | A user connects to a Hermes instance on a home-lab HTTP address over local Wi-Fi. A malformed, origin-confusing, or proxy-prefixed URL must be rejected, while intentional cleartext remains visible and explicitly approved. | `GatewayEndpointTests`; `testCleartextOnboardingRequiresExplicitApproval`; `testInvalidGatewayFailsClosedWithVisibleError` | Pass after WS-05 |
| Status discovery | A reverse proxy is old enough to return 404 for `/api/status`, while a hostile or broken proxy returns a huge document. Legacy detection must survive, but a successful oversized response must fail closed before JSON decoding. | `GatewayStatusClientTests`, including `testProbeBoundsUntrustedStatusPayloadBeforeDecoding` | Pass after WS-01 |
| Browser sign-in | A company gateway redirects to its identity provider and back. The user must see the gateway origin, cannot continue before a successful page load, and unrelated navigation must not inherit an authenticated app session. | `testGatewaySignInShowsOriginAndRequiresLoadedPageBeforeContinue`; `testGatewaySignInEnforcesNavigationPolicyInWebKitDelegate`; authentication request-factory tests | Pass |
| Cookie/ticket authentication | A user has two saved gateways behind the same host with different proxy prefixes. Cookies, one-shot WebSocket tickets, token rotation, logout, and 401 expiry must stay profile-scoped; ambiguous overlapping scopes must fail before credentials are used. | `GatewayAuthenticationTests`; cookie-store and gateway-expiry model tests | Pass |
| Saved gateway recovery | A commuter opens Nile in a tunnel, airplane mode, or after the server restarts. The transcript remains visible through offline/reconnecting/restoring, controls stay blocked, and connection is published only after session restoration. | `GatewayReconnectCoordinatorTests`; `testRecoveryStatesRetainTranscriptAndBlockInteraction`; reconnect model tests | Pass |
| Gateway switching/removal | An operator switches environments while the current assistant is running, or deletes a retired profile. Switching requires an explicit one-shot confirmation; deletion scrubs credentials, cookies, drafts, attachments, and profile-owned state. | running-turn gateway-switch model/UI tests; gateway-removal model/UI tests | Pass after WS-04 |
| Session discovery | A user with a large history searches by title/source/ID, pins an incident session, and switches while the new history is slow. The old transcript stays until replacement content is ready and stale loads cannot win. | session list/pin/filter/selection model tests; session sheet and switch XCUITests | Pass |
| Terminal-owned session | A developer opens a session still owned by a desktop CLI. Nile remains a read-only mirror, explains why Claim is disabled while busy, and rechecks runtime status immediately before a later Claim. | `SessionOwnershipCoordinatorTests`; Claim race tests; `testBusyTerminalMirrorExplainsWhyClaimIsDisabled` | Pass |
| New session with unsent work | A user starts a fresh task while text and a photo are still drafted in the current session. Nile must atomically park the old draft/attachment owner before creation and stop if protected persistence fails. | session-creation protection tests; attachment/draft CAS and migration tests; create-session XCUITests | Pass |
| Prompt, steer, stop, retry | A mobile network drops just after Send, a queued follow-up becomes a steer, or a late Stop acknowledgement arrives after another turn began. Nile must distinguish definite from uncertain delivery and reject stale owner/runtime callbacks. | prompt/steer/stop repository and recovery tests; composer/runtime model tests; composer state XCUITests | Pass |
| Transcript and tools | A long coding turn streams partial prose, tool updates, todos, diffs, media, syntax, and a wide Markdown table. Segments remain chronological, no false final bubble appears, and reading position survives keyboard/session changes. | projector/live-transcript/scroll tests; streaming, syntax, table, long-history, and keyboard XCUITests | Pass after WS-06 |
| Blocking input | Hermes asks a clarification, sudo password, secret, or approval while other requests queue. Requests remain FIFO and one-shot, secret text never enters semantics or retained state, and malformed prompts are visible but non-actionable. | `BlockingPromptCoordinatorTests`; projector tests; four blocking-input XCUITests | Pass |
| Model and reasoning controls | A cost-conscious user searches a large provider catalog, selects an expensive model, changes reasoning, and pins a choice per gateway. Confirmation, capability constraints, stale result fencing, and ordered pin persistence must hold. | model codec/repository/store/model tests; picker/menu/pin XCUITests | Pass |
| Slash commands | A user types aliases and profile-management commands from the phone. Recursive or malformed aliases are rejected, desktop-only commands are blocked, and uncertain execution preserves recoverable draft state. | slash-command policy/coordinator/repository tests | Pass |
| Photo attachment delivery | A field user photographs an error screen, sends it with or without text, and loses connectivity between upload and prompt acceptance. Image size/encoding is bounded and delivery leases cannot be consumed by another session or runtime. | image encoder, attachment delivery/recovery/store tests; attachment composer XCUITests | Pass |
| Downloaded files and previews | Hermes returns a report through redirects or with an oversized body or very long filename. Redirects must not leak credentials, downloads/cache remain bounded and protected, and the cached filename must retain `.pdf` so Quick Look can identify it. | dashboard attachment redirect/bounds tests; `PrivateAttachmentCacheTests`, including `testLongFilenameKeepsExtensionForSystemPreview`; media XCUITests | Pass after WS-03 |
| Standing goals | A user starts a multi-turn refactor with a budget, backgrounds it, then pauses or resumes it later. Goal mutation is owner-fenced, preserves the composer draft, and waits for authoritative status. | goal codec/repository/model tests; goal quick-start/details XCUITests | Pass |
| Delegated agents | A lead task fans out to subagents, one finishes while another is interrupted, and the user reopens the parent later. Sparse events merge with snapshots, terminal state is sticky, and controls target the correct child. | delegation codec/coordinator/model tests; active/settled delegation XCUITests | Pass |
| Usage and statistics | A long-lived or compromised gateway reports negative, out-of-range, duplicated, or near-64-bit token/session counters. Context percentages, totals, momentum, and heatmap aggregation must remain bounded without an integer trap. | `testExtremeUsageCountersSaturateWithoutOverflow`; usage/stats codec and UI tests | Pass after WS-02 |
| Voice dictation | A user dictates in a noisy room, gets several blank transcriptions, cancels, or switches sessions during a late callback. Draft text is preserved, blank-result policy pauses safely, and old owners cannot submit. | speech engine/repository tests; `VoiceCoordinatorTests` | Pass |
| Talk and spoken replies | A user runs hands-free while locking the phone, receiving a blocking request, interrupting speech, or moving to another session. Partials remain private, each reply is admitted once, and audio work is owner/turn fenced. | Talk coordinator/model/sanitizer tests; Talk and spoken-reply XCUITests | Pass |
| Background completion | A user leaves a long turn running and taps its completion notification from a cold launch. The notification contains generic copy only, background expiration requeues safely, and routing loads only the exact saved gateway/session. | `TurnNotificationControllerTests`; notification education XCUITest | Pass |
| Accessibility and input | A user relies on accessibility-extra-large text, Reduce Motion, a localized system keyboard, and secure entry. Controls remain reachable and at least 44 points, animations respect policy, focus advances semantically, and secrets stay redacted. | dedicated `NileAccessibilityTests`; typography/motion/semantics tests | Pass after WS-07 |
| Untrusted dashboard documents | A misconfigured server sends tens of megabytes for history, session source, analytics, connection tickets, or logout. Nile must stop buffering at an operation-appropriate cap and return a safe error instead of exhausting memory. | bounded status/dashboard/auth focused tests plus existing bounded speech/media tests | Pass after WS-01 |

## Weak spots found and fixed

### WS-01: Ordinary gateway responses were unbounded

Status discovery, dashboard JSON, connection-ticket, and logout reads used the
ordinary data-loading path even though their contents are controlled by a
remote gateway. A broken or hostile endpoint could make the app buffer an
arbitrarily large response before decoding.

The production clients now stream status/ticket/logout through a 64 KiB cap and
ordinary history/session/analytics JSON through a 32 MiB cap. HTTP 401,
non-success, and legacy 404 classifications remain intact; oversized successful
documents fail closed with safe user-facing errors. Focused validation passed
29 status, dashboard, and authentication tests.

Commit: `cdcfbb6 fix: bound gateway HTTP responses`

### WS-02: Extreme counters could trap integer conversion or aggregation

JSON `Double` values at the rounded upper edge of `Int`/`Int64`, derived
`used * 100` percentages, token totals, duplicate daily counters, and heatmap or
momentum reductions could overflow. These are remotely supplied analytics
values, so a malformed payload could terminate the app.

Representability checks now avoid the rounded conversion edge. Negative counts
clamp to zero, reported percentages clamp to 0...100, derived percentages use
an overflow-safe helper, and token/session/call aggregates saturate. The focused
usage/goal codec suite passed all 7 tests, including the new adversarial case.

Commit: `8807011 fix: prevent usage counter overflows`

### WS-03: Long cached filenames lost their type extension

The private attachment cache truncated sanitized filenames from the right.
A long `quarterly-report-....pdf` therefore lost `.pdf`, leaving Quick Look and
share targets without their normal filename type hint.

Truncation now reserves room for a conventional extension while retaining the
existing 120-character safety limit and fallback behavior. All 4 private-cache
tests pass, including a real write/read assertion for a long PDF filename.

Commit: `8755657 fix: preserve attachment preview extensions`

### WS-04: Gateway removal returned drifted empty-state copy

The full UI audit caught a post-removal message that no longer matched the
pinned Android source. This made the destructive journey end in inconsistent
guidance even though protected data cleanup itself was correct.

The source-owned empty-state sentence is restored exactly, and the focused
removal confirmation journey passes through deletion to the final empty state.

Commit: `34a99af fix: restore gateway removal empty-state copy`

### WS-05: Onboarding tests enforced obsolete fixed geometry

The standard onboarding journey still required exact 48-point Add and Connect
buttons after the intentional native-iOS redesign moved those controls to
Liquid Glass. On iOS 26 the semantic controls are 64 points high and satisfy
the branch's 44-point accessibility contract, but the stale assertion made
valid native UI red.

Both assertions now enforce the durable minimum-target contract. The clean
onboarding journey passes on a fresh disposable simulator.

Commit: `18f049c fix: align onboarding test with native controls`

### WS-06: A long switched transcript could disappear under the keyboard

The existing focus guard preserved a short transcript during keyboard opening,
but prevented a newly selected 40-message transcript from following its tail
while the viewport shrank. Removing the guard unconditionally fixed the long
case and regressed the one-message case.

Transcript focus now snapshots whether content genuinely extends above the
viewport. Only a scrollable transcript remains bottom-pinned during keyboard
resize; short content retains natural bottom alignment. The one-message
journey and four-cycle switched-session journey pass together on a fresh
simulator and in the complete UI lane.

Commit: `26733df fix: preserve long transcripts during keyboard resize`

### WS-07: The accessibility lab enforced pre-redesign field expansion

The dedicated accessibility-extra-large test still required each gateway field
to grow beyond 64 points. Native fields now use a 50-point interactive surface;
the branch contract is scaled text with reachable controls of at least 44
points. The obsolete size assertion stopped the journey before it could test
keyboard focus and secret redaction.

The lab now checks the native minimum target while retaining its scaled-title,
Next/Done navigation, Reduce Motion, and secure-value assertions. The fresh
accessibility lane passes 1/1 and exports the form, final screen, and sanitized
hierarchy.

Commit: `aefddaf fix: align accessibility lab with native fields`

## Final deterministic validation

- Pinned Android source verification passed for commit
  `bd5451da891f2d886b9bc35f8ea67d6920df1d98`, tree
  `3b954e5844f05276d34aaee34a7d3f69169ef9f5`.
- The unit lane passed analyzer, 427/427 unit and protocol tests, the optimized
  unsigned Release build, secret scan, crash check, and simulator cleanup at
  `build/test-lab-results/20260728T234055Z-18012`.
- The standard UI lane passed 52/52 journeys, attachment export, secret scan,
  crash check, and simulator cleanup at
  `build/test-lab-results/20260728T234502Z-20631`.
- The accessibility-extra-large lane passed 1/1, attachment export, secret
  scan, crash check, and simulator cleanup at
  `build/test-lab-results/20260728T235940Z-26509`.

## Validation boundaries

Deterministic tests cover the app-owned behavior above. The separately gated
real-Hermes lane still requires an operator-provided OpenRouter credential, and
the repository's final full parity gate remains red until both that credentialed
lane and all strict Android/iOS visual comparisons pass. This audit does not
claim those external acceptance conditions were completed.
