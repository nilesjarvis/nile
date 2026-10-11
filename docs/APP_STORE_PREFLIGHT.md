# App Store preflight

Run this explicit submission check before preparing an App Store archive:

```bash
python3 scripts/app-store-preflight.py
```

It deliberately does not run during normal development builds. It exits with
status 1 and lists remaining blockers, including the public deployment values
that the publisher must provide in `Config/Info-Release.plist`:

- `NilePrivacyPolicyURL`: the real public HTTPS privacy policy URL.
- `NileSupportURL`: the real public HTTPS support page URL.

Both values are strings read by the app's privacy information screen. Do not
insert example URLs to make the check pass. Publish the pages, add their real
addresses, review their contents against the app's actual behavior, and confirm
that people and App Review can open them without authentication. The check
rejects unresolved placeholders, reserved/example/local hosts, private IP
addresses, embedded credentials, and credential query parameters. It does not
contact the URLs or establish that a hostname exists or a page is reachable.

After archiving with the `Release` configuration, also check the packaged app:

```bash
python3 scripts/app-store-preflight.py \
  --app-bundle build/Nile.xcarchive/Products/Applications/Nile.app
```

Use the actual archive path. This additionally verifies that the device app
contains the same public URLs as the Release source, the privacy manifest,
complete font/renderer licenses and attribution, production transport policy,
and the operating-system encryption exemption. It rejects Simulator builds and
SDKs older than iOS 26, the current submission minimum. Revisit the SDK minimum
when [Apple updates its submission requirements](https://developer.apple.com/news/upcoming-requirements/).

The check reports local configuration evidence only. Passing does not confirm
public-page availability or policy sufficiency, signing/provisioning, App Store
Connect metadata and privacy-label answers, review gateway access, or App
Review approval. `./scripts/test-lab/run.sh full` remains the final repository
test gate. Local signing settings are intentionally outside this check.

The privacy manifest's audited API reasons cover only app-owned settings,
private-cache file metadata, and monotonic prompt-expiry timers. They do not
replace the separate privacy-label review of the publisher's data handling and
the gateways/providers the app permits users to select.

Run the preflight's standard-library regression tests with:

```bash
python3 -m unittest discover -s scripts/tests -p 'test_app_store_preflight.py'
```
