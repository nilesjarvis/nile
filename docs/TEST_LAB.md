# Disposable iOS and Hermes test lab

The repository-owned test lab validates Nile in fresh, isolated environments.
Each run creates a disposable iPhone 17 Pro/iOS 26.5 Simulator, uses isolated
app and Hermes state, retains sanitized evidence, and deletes the temporary
environment on exit.

## Commands

Inspect prerequisites without changing the workspace:

```bash
./scripts/test-lab/doctor.sh full
```

Run a lane:

```bash
./scripts/test-lab/run.sh unit
./scripts/test-lab/run.sh ui
./scripts/test-lab/run.sh accessibility
./scripts/test-lab/run.sh smoke
./scripts/test-lab/run.sh full
./scripts/test-lab/run.sh drive
./scripts/test-lab/run.sh installer
```

## Lanes

| Lane | Contract |
| --- | --- |
| `unit` | Analyze the current source, run unit and protocol tests, and produce an optimized unsigned Release build with warnings treated as errors. |
| `ui` | Run deterministic user journeys through accessibility identifiers in a fresh Simulator. |
| `accessibility` | Exercise accessibility-extra-large text, Reduce Motion, minimum touch targets, keyboard order, and secret redaction. |
| `smoke` | Build the production app and test bundle, install a fresh pinned Hermes revision, create an isolated gateway/session, and run credentialed integration journeys. |
| `full` | Run every deterministic lane, build the real-service bundle, and start the credentialed lane only if the prerequisites pass. |
| `drive` | Leave a disposable Simulator and isolated Hermes instance available for manual inspection until interrupted. |
| `installer` | Verify a fresh pinned Hermes installation without starting a model. |

The Hermes revision is recorded in `scripts/test-lab/hermes.ref`. The lab clones
that exact unmodified revision into a temporary directory and never reads the
operator's normal Hermes home or profile.

## Isolation

The runner replaces its process environment with an allowlist before invoking
external tools. It creates temporary locations for:

- the Simulator and derived data;
- `HOME` and `HERMES_HOME`;
- the Hermes installation and workspace;
- package-manager caches;
- gateway credentials and session fixtures; and
- build and test intermediates.

Only the sanitized result directory survives by default. Set
`NILE_LAB_KEEP=1` only for local diagnosis, and inspect retained temporary state
before sharing it.

## Credential handling

Never export `OPENROUTER_API_KEY`. Real-Hermes lanes request the key from the
controlling terminal only after the production app and test bundle have built.
For non-interactive CI, provide a one-use regular file with mode `600` through
`NILE_LAB_OPENROUTER_KEY_FILE`.

The runner removes the handoff file before reading it, keeps the value only in
the isolated process environment, and scans retained artifacts for both the
provider key and gateway token. Any contaminated artifact is removed and fails
the lane.

## Artifact contract

Results are retained under:

```text
build/test-lab-results/<run-id>/
```

Depending on the lane, the directory contains:

- `run.properties` with toolchain, Simulator, app, model, and Hermes revision;
- `lane-results.tsv` with pass, fail, or blocked state and timestamps;
- analyzer, build, test, and service logs;
- `.xcresult` bundles and exported attachments;
- a final Simulator screenshot and recent app log;
- crash reports created during the run; and
- `secret-scan.txt` describing the retention scan.

Fixtures and attachments must remain synthetic. Do not retain provider keys,
gateway tokens, cookies, real conversations, personal photos, microphone
recordings, or user-specific paths.

## Release evidence

A successful compile proves only that the source builds. Feature and release
claims require the relevant unit, UI, accessibility, security, and real-service
evidence. The `full` lane is the final repository gate and blocks paid model use
when a deterministic prerequisite is red.
