# App Store readiness audit

Audited 2026-10-11 against the Swift implementation and Apple's current public
submission guidance. **Not ready to submit yet.** Code changes reduce known
review risks; only Apple can decide whether the final submission is accepted.

## Implemented remediation

| Finding | Change and evidence boundary |
| --- | --- |
| Missing explicit AI-sharing permission | Versioned consent is required for each canonical gateway before a new connection, restored profile, or gateway switch. Disclosure covers the selected gateway and its configured AI/speech/tool services. Cancellation sends no connection request. Withdrawal disconnects and invalidates outstanding connection attempts. |
| Missing privacy controls | Privacy & Data is available before sign-in and from connected Settings. It describes local and remote storage, optional permissions, removal, withdrawal, and provider responsibilities. Public policy/support links appear when genuine deployment URLs are configured. The overview alone does not complete the public-policy requirement. |
| Missing required-reason manifest | Bundled manifest declares app-owned UserDefaults, private-file timestamps, and elapsed-time APIs. No tracking is declared; collection labels still need separate review. |
| Incomplete deletion and caching | Independent protected stores are all attempted before deleting a profile; failure retains the profile for retry. Explicit global cleanup erases downloaded previews and all WebKit website data while disconnected. Unmanaged URLSession caches are disabled. Canceled/stale attachment downloads are fenced before caching. |
| Missing static-library license packaging | FreeType and HarfBuzz licenses and attribution are copied into the app and accessible through Software Notices. |
| Permission/export metadata | Purpose strings explain gateway transmission. The current implementation uses operating-system encryption and declares no non-exempt encryption; revisit if cryptography changes. |
| Nonfunctional prefilled production endpoint | Release starts with an empty gateway URL and explains the requirement for a compatible user-managed HTTPS gateway. |
| Undersized session controls | Composer, attachment, model, usage, search, and session controls now expose at least 44-point targets; header actions retain the 48-point product contract. UI tests check the targets and semantic interactions. |
| No submission configuration check | `scripts/app-store-preflight.py` validates source and optional device app bundle without changing normal development builds. Missing public URLs are failures. |

The review rationale comes from Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
particularly privacy/consent, support, completeness, and licensed materials.
API declarations follow [Apple's required-reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Existing submission foundations were also checked: Release disables cleartext
gateway support and includes no arbitrary-load ATS exception; debug fixtures are
compiled out; the archive scheme uses Release; and the 1024×1024 app icon has no
alpha channel. The project targets iPhone on iOS 17 and later. These checks do
not validate distribution signing or establish compatibility on every supported
OS version. The current version/build (`0.1.0` / `1`) must be checked against
App Store Connect before upload.

## Submission blockers owned by the publisher

1. **Publish and verify policy/support pages.** Supply the publisher's legal
   identity and reachable support contact. Review the policy content against
   actual operations, publish it without a login requirement, then configure
   `NilePrivacyPolicyURL` and `NileSupportURL` in the shipping plist. Set matching
   App Store Connect URLs. Do not invent addresses or use reserved examples.
2. **Provide live review access.** Maintain a compatible HTTPS Hermes gateway
   and review credentials throughout review. Enable representative supported
   features and disclose the configured AI, transcription, speech, and tool
   services. Send credentials only through App Store Connect's private review
   information. Debug fixtures are excluded from Release and do not substitute
   for review access. See [Apple's complete-review guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review).
3. **Complete privacy labels and provider review.** Inventory who can access and
   retain chat content, photos, audio, authentication information, and diagnostics.
   Assess configured services and their policies; do not select “Data Not
   Collected” solely because Nile has no developer-operated backend. Explain
   provider identities and retention for the review deployment. User-managed
   gateways can change providers, so do not promise a universal retention period
   or that all processing is on-device. See [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
4. **Complete release evidence.** Pass the repository's full deterministic and
   credentialed real-Hermes gate. Test the signed Release app on a physical
   iPhone, including camera, microphone denial/recovery, biometrics, networking,
   backgrounding, large text, and the supported minimum OS. Test on the current
   shipping OS too. An unsigned build and Simulator tests are not a distribution
   validation.
5. **Finish App Store Connect setup.** Confirm the bundle ID, publisher ownership,
   unique version/build, distribution signing, availability and pricing; upload
   real app screenshots, accurate metadata, age-rating answers, review contact
   details, export-compliance answers, and applicable trader information. Use
   Apple's [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions),
   [export guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/),
   and [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements).
6. **Resolve the chatbot/plug-in review classification.** Guideline 4.7 explicitly
   includes software offered outside the app binary, including chatbots and
   plug-ins. Nile's private, user-configured protocol-client architecture is
   relevant context, but does not establish an exemption. Explain the model,
   agent, and tool capabilities to App Review. If the rule applies, demonstrate
   content filtering, reporting and response, abusive-user blocking, software
   indexing and universal links, per-software consent, age controls, and the
   restriction on exposing native APIs. Current gateway-level consent alone
   does not establish compliance. The required product and gateway support must
   be resolved before claiming readiness; cosmetic local filters would not
   establish an operational moderation process. See [Apple Guideline 4.7](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators).

## Review notes to finalize with the deployment

Nile is a native iPhone client for a user-managed Hermes agent gateway. Hermes
is not bundled. Explain the business model and gateway prerequisite prominently
in the store description. The app offers native session management, streaming
transcripts, attachments, voice input/output, permissions for agent actions,
goals, delegation, and optional biometric locking.

Provide the review gateway address and credentials in the private review fields,
then give these instructions:

1. Open Nile, choose Add Gateway, and enter the supplied HTTPS address.
2. Review and allow the gateway data-sharing disclosure. Use the supplied
   legacy token or complete dashboard sign-in, as configured for review.
3. Open or create the supplied review session, send a prompt, and exercise the
   enabled attachment, voice, model, goal, and approval features.
4. Open Settings → Privacy & Data for privacy details, withdrawal, deletion
   guidance, and software notices. State the actual privacy/support page URLs.

Describe any gateway-dependent feature availability and third-party service
costs truthfully. Do not claim affiliation with Hermes or rights to third-party
branding unless authorized. Select age-rating answers based on the actual
unrestricted AI/content capabilities, not just screenshots of benign prompts.

The current source has no Nile account creation, purchases, purchase links,
public social feed, or local execution of downloaded agent code. No separate
Nile account-deletion, IAP, or Sign in with Apple system was added. Reassess these
requirements against the actual deployment and business model. The absence of
a public social feed does not resolve the separate Guideline 4.7 concern above.

## Verification record

The initial read-only test-lab doctor passed with Xcode 26.6 and the canonical
iPhone 17 Pro/iOS 26.5 Simulator. The toolchain meets the current
[Xcode 26 / iOS 26 SDK upload minimum](https://developer.apple.com/news/upcoming-requirements/?id=04282026a).

The final `./scripts/test-lab/run.sh full` attempt is recorded in
`build/test-lab-results/20261011T115711Z-54667/`:

| Check | Result |
| --- | --- |
| Doctor and disposable Simulator setup | Passed |
| Static analysis | Passed |
| Unit/protocol tests | 753 passed, no failures or skips |
| Unsigned device Release build, Swift warnings treated as errors | Passed |
| UI contracts | 59 passed, no failures or skips |
| Large-text/Reduce Motion accessibility contracts | 2 passed, no failures or skips |
| Production app and real-Hermes test-bundle compilation | Passed |
| Pinned Hermes setup and credentialed smoke | Installation completed, then fixture setup failed at secure credential acquisition; smoke was blocked |
| Retained-artifact secret scan | Passed |

**The full gate did not pass.** No one-use OpenRouter key handoff was supplied,
and the noninteractive run could not read a key from a terminal. No live model
turn or real-service smoke test ran. Supply a mode-600 one-use key file through
`NILE_LAB_OPENROUTER_KEY_FILE` and rerun `full`; never place the key in chat,
source, shell history, or retained artifacts. The Hermes compatibility pin was
not changed, and the runner used its isolated profile.

The submission preflight's 13 Python regression tests pass. Source and built
device-bundle preflight fail only on the two missing public URLs described
above; packaged manifest, licenses, SDK, encryption, and transport checks pass.
Simulator screenshots of the privacy, consent, and session interfaces were
inspected, including the consent screen at accessibility-extra-large text.
Signed distribution, physical-device checks, minimum-OS coverage, public-page
availability, and App Store Connect validation remain unverified. Test artifacts
remain local under `build/` and are not committed.
