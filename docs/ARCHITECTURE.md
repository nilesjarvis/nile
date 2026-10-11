# Nile iOS architecture

Nile is a standalone native iOS client for the Hermes `tui_gateway`. The app is
implemented in Swift with SwiftUI for product surfaces and focused UIKit/WebKit
bridges where platform control is necessary.

## Design goals

- Keep untrusted gateway data outside presentation code until it has been
  decoded and validated.
- Keep session ownership explicit across reconnects, navigation, backgrounding,
  delayed callbacks, and mutations.
- Fail closed for credentials, blocking prompts, ambiguous authentication,
  malformed wire data, and uncertain delivery.
- Preserve useful local state without putting secrets in ordinary preferences,
  logs, screenshots, fixtures, or backups.
- Make important behavior observable through stable accessibility identifiers
  and deterministic tests.

## Layers

```text
Features  ->  App runtime  ->  Domain contracts  <-  Gateway data layer
                    |
                 Core services
```

### `Sources/Nile/Domain`

Domain types describe gateways, sessions, messages, goals, delegated agents,
models, usage, blocking requests, media, and repository capabilities. They do
not depend on UI frameworks or transport payloads.

### `Sources/Nile/Data/Gateway`

The gateway layer owns REST and WebSocket communication with Hermes. It
contains endpoint canonicalization, origin policy, authentication, cookie and
ticket handling, bounded downloads, JSON-RPC framing, codecs, event projection,
retry classification, and repository services. Wire formats stay in this layer
so feature code cannot silently depend on gateway JSON details.

### `Sources/Nile/Core`

Core services provide typography and Markdown rendering, protected persistence,
Keychain integration, attachment caching, image encoding, speech input/output,
notifications, and platform helpers. These services expose narrow contracts to
the app runtime.

### `Sources/Nile/App`

The app layer composes dependencies and owns long-lived state machines. It
coordinates gateway setup and recovery, session navigation, transcript
projection, drafts, attachments, turn submission, blocking requests, model
controls, goals, delegation, usage, voice, Talk mode, background work, and
notification routing.

`SessionListModel` is the primary presentation model. Responsibilities are
split into focused extensions and lifecycle objects so each asynchronous flow
can fence callbacks by gateway, session, turn, or operation owner.

### `Sources/Nile/Features`

Feature surfaces render app state and forward user intent. They do not decode
gateway payloads or own credential storage. Stable identifiers in
`NileAccessibilityID` are part of the UI testing contract.

## Application composition

`NileAppGraph` constructs production dependencies. Debug-only fixture assembly
is selected through launch arguments and cannot alter Release behavior. Fixture
data must be deterministic, secret-free, and visibly synthetic.

The app selects one gateway profile at a time. Switching or removing a profile
is an explicit operation that fences in-flight callbacks and profile-owned
state. Connection state is published only after authentication and required
session restoration have completed.

## Gateway and authentication

Gateway URLs are canonicalized before use. Profile identity includes the
scheme, host, port, and proxy prefix so credentials and cookies cannot drift
between overlapping origins.

Production transport requires HTTPS/WSS. Debug and LocalRelease may use HTTP/WS
only through the visible per-profile approval workflow compiled into those
configurations.

Dashboard authentication uses a constrained WebKit navigation policy and a
managed persistent cookie store. Legacy session tokens and reusable gateway
credentials are stored in non-synchronizing, this-device-only Keychain items.
One-shot tickets, rotations, expiry, logout, and removal remain scoped to the
owning profile.

REST bodies and downloads are bounded before decoding or persistence. Redirect
policy prevents credentials from following an unapproved origin. WebSocket
frames are decoded through explicit codecs and malformed state-changing input
fails closed.

## Sessions, turns, and transcripts

Session discovery, pinning, search, rename, creation, navigation, and history
loading are coordinated by owner-scoped tasks. A slower request cannot replace
newer state after the user changes gateway or session.

Turn submission distinguishes prompt, steer, stop, retry, and uncertain
delivery. Draft and attachment state is retained until the gateway outcome is
authoritative. Terminal-owned sessions remain read-only until Claim is both
available and revalidated immediately before mutation.

Transcript projection merges stored history and live events into chronological
presentation segments. Markdown, code, tables, todos, diffs, tools, media, and
delegation updates have stable identities. Scroll state separates intentional
reading from bottom-following and survives keyboard, viewport, and asynchronous
size changes.

## Blocking input

Clarifications, approvals, sudo requests, and secret prompts use a FIFO,
one-shot coordinator. A request can be answered only by its current owner.
Malformed blocking payloads remain visible for diagnosis but expose no submit
action. Secret text is excluded from ordinary drafts, semantics, logs, fixtures,
screenshots, and retained artifacts.

## Attachments and media

Photo intake uses system camera and photo-library flows. Encoding is bounded
off the main actor. Draft persistence and delivery leases are scoped to their
gateway, session, and runtime owner so retries cannot consume another session's
attachment.

Downloaded attachments use a protected, backup-excluded cache with entry and
byte limits. Filenames are sanitized while preserving useful extensions for
Quick Look. Redirects, MIME handling, preview decoding, and body sizes are
validated before a file becomes visible to the UI.

## Voice and Talk mode

Voice input owns an audio-session and capture lifecycle, converts bounded PCM,
and submits audio to the configured gateway for transcription. Late callbacks
are rejected after cancellation, navigation, or owner changes. Blank-result and
retry policy preserve the user's draft.

Talk mode coordinates listening, transcription, turn admission, spoken replies,
pause/resume, interruption, blocking requests, and session changes. Partial
speech remains private and each response is admitted at most once.

## Goals, delegation, models, and usage

Goal and delegated-agent state combine stream events with authoritative
snapshots. Mutations are operation-fenced, terminal state is sticky, and sparse
updates cannot erase known data.

Model catalogs, model selection, reasoning controls, and per-gateway pins are
capability-gated. Potentially disruptive changes require confirmation. Usage,
context, momentum, and heatmap calculations clamp or saturate untrusted numeric
input to avoid overflow and misleading percentages.

## Concurrency

UI state is isolated to `@MainActor`. Network, persistence, audio, image, and
rendering work move off the main actor through narrow async boundaries. Every
long-lived task has explicit cancellation and ownership rules. Continuations
must resume exactly once, and stale callbacks are ignored rather than projected
into the current session.

## Persistence and privacy

| Data | Storage | Boundary |
| --- | --- | --- |
| Reusable gateway credentials | Keychain | this-device-only, non-synchronizing |
| Gateway metadata | protected file | excluded from backup; no token material |
| Composer and photo drafts | protected files | gateway/session scoped; excluded from backup |
| Model and session pins | protected files | gateway scoped; excluded from backup |
| Downloaded attachments | protected bounded cache | excluded from backup |
| Dashboard cookies | managed WebKit store | profile-scoped cleanup policy |
| Notifications | system notification center | generic copy; no transcript content |

Nile has no developer-operated cloud service or bundled analytics/advertising
SDK. Runtime content is exchanged with the gateway and sign-in origins selected
by the user.

The app bundles its required-reason privacy manifest and software notices.
Gateway sharing consent is versioned and scoped to a hashed canonical endpoint;
connection, restoration, and switching wait for explicit permission. Withdrawal
stops local session/voice work before disconnecting and fences stale connection
callbacks. Consent records contain no endpoint text, credentials, or content.

Privacy & Data offers explicit cleanup of all downloaded previews and WebKit
website data while disconnected. Ordinary profile removal retains its identity
until every protected local store has been erased so failed cleanup is retryable.
Foundation response, cookie, and credential caches are disabled; authentication
continues to supply only explicitly managed cookie headers.

The publisher must still supply public privacy/support pages and review data
labels before App Store distribution. See [`APP_STORE_READINESS.md`](APP_STORE_READINESS.md)
and [`APP_STORE_PREFLIGHT.md`](APP_STORE_PREFLIGHT.md).

## Build configurations

- `Debug`: deterministic fixtures and explicit cleartext approval for local
  development.
- `LocalRelease`: optimized local validation with the same explicit cleartext
  workflow.
- `Release`: production behavior, no debug fixtures, and no arbitrary-load ATS
  exception.

Do not check in a development team, provisioning profile, signing identity,
credential, local override, or generated test artifact.

## Verification

Unit tests cover domain policy, codecs, persistence, security boundaries, and
runtime state machines. UI tests exercise user-visible journeys through stable
accessibility identifiers. Accessibility tests cover large text, Reduce Motion,
touch targets, keyboard order, and secret redaction. Credentialed smoke tests
exercise the production app against a fresh pinned Hermes installation.

The disposable test lab owns the repository's complete verification workflow;
see [`TEST_LAB.md`](TEST_LAB.md).

## Project generation

`project.yml` is the source for the checked-in Xcode project. After changing
targets, files, settings, or dependencies, run `xcodegen generate`, inspect the
generated diff, and verify both Simulator and unsigned device builds. Never
commit Xcode user state or personal signing configuration.
