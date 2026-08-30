# Nile visual comparer

`compare.sh` is the repository-owned Android/iOS screenshot normalizer and
strict visual gate. It uses only macOS/Xcode frameworks. Run its regression
suite with:

```sh
./scripts/visual/test.sh
```

Run a comparison with:

```sh
./scripts/visual/compare.sh fixture.json --output build/visual/fixture
```

Regenerate the pinned Android onboarding, canonical chat/expanded-session,
production-shell long-history/syntax, model-picker, session-rename,
standing-goal, context, gateway-statistics, gateway-removal, gateway-switch,
Hermes voice-settings, Talk listening, and delegation
references in an isolated disposable emulator with:

```sh
./scripts/visual/capture-android.sh
```

The capture command verifies the pinned APK SHA-256, creates an isolated Pixel
6/API 35 AVD below `build/`, sets a 1206-by-2478-pixel display with deterministic
72-pixel system bars to expose the iPhone 17 Pro's exact 402-by-778-point
app-content viewport at 3x, fixes dark mode/font scale/animation state, exports
screenshots plus UIAutomator hierarchies, and deletes the disposable emulator
and AVD on exit. It never modifies the Android source checkout or the user's
normal AVDs. The canonical chat/expanded-session pair runs the pinned
repository's existing deterministic instrumentation test unchanged. For the
additional connected production-shell states it creates a second exact-commit
clone, applies the tracked `android-model-picker-test.patch` only to
`app/src/androidTest`, and builds the unchanged app-under-test plus
instrumentation APK together so their disposable debug signatures match. It
then exports each screenshot plus all-root Compose semantics. The production
source and pinned production APK remain unchanged.

The Hermes voice checkpoint uses the same test-only exact-pin overlay to open
the real loaded voice sheet over `NileAppContent` with the connected Edge TTS /
Aria fixture. The capture script rejects production-source changes and verifies
the provider, current voice, global warning, and action copy before accepting
the PNG and all-root semantics.

The Talk checkpoint renders the real `TalkScreen` in its listening phase with
the same deterministic session title as iOS. Both platforms disable animation
for this source comparison; the production phase transitions and interactive
pause/resume/end journey remain exercised by their normal UI tests.

Image paths are resolved relative to the manifest. A manifest uses this shape:

```json
{
  "schemaVersion": 2,
  "fixture": "onboarding",
  "reference": {
    "path": "../../.reference/android/docs/screenshots/nile-onboarding.png",
    "nativeScale": 2.625,
    "systemChromeInsetsPixels": {
      "top": 63,
      "bottom": 63,
      "left": 0,
      "right": 0
    }
  },
  "candidate": {
    "path": "../../build/checkpoints/onboarding.png",
    "nativeScale": 3,
    "systemChromeInsetsPixels": {
      "top": 186,
      "bottom": 102,
      "left": 0,
      "right": 0
    }
  },
  "canonical": {
    "widthPixels": 1080,
    "heightPixels": 2274
  },
  "thresholds": {
    "minimumSSIM": 0.97,
    "maximumOutlierFraction": 0.03,
    "channelDelta": 18,
    "maximumLandmarkDeltaPoints": 2,
    "maximumMaskFraction": 0.02
  },
  "masks": [],
  "landmarks": [
    {
      "name": "header-panel-width",
      "kind": "size",
      "reference": {
        "axis": "horizontal",
        "fixedPoints": 120,
        "startPoints": 0,
        "endPoints": 402,
        "expectedHex": "#212121",
        "maximumChannelDelta": 0,
        "minimumRunPoints": 300,
        "measurement": "longestRunLength"
      },
      "candidate": {
        "axis": "horizontal",
        "fixedPoints": 120,
        "startPoints": 0,
        "endPoints": 402,
        "expectedHex": "#212121",
        "maximumChannelDelta": 0,
        "minimumRunPoints": 300,
        "measurement": "longestRunLength"
      },
      "tolerancePoints": 1
    }
  ],
  "colorSamples": [
    {
      "name": "canvas",
      "expectedHex": "#181818",
      "reference": {
        "xPoints": 4,
        "yPoints": 100,
        "radiusPoints": 1
      },
      "candidate": {
        "xPoints": 4,
        "yPoints": 100,
        "radiusPoints": 1
      }
    }
  ],
  "manualReview": {
    "status": "pending",
    "reviewedBy": null,
    "notes": null
  }
}
```

Historical captures taken from a taller responsive viewport may declare an
optional full-width spacer after `systemChromeInsetsPixels`:

```json
"solidVerticalSpacerPixels": {
  "top": 400,
  "height": 180,
  "expectedHex": "#181818"
}
```

Its coordinates are relative to the system-chrome-cropped image. The comparer
removes the band before normalization only when every pixel is exactly the
declared flat color, the band is internal to app content, and its height is at
most 10% of that content. This preserves every rendered UI pixel while
normalizing blank responsive space; it is not a mask and cannot hide text,
controls, borders, or other non-background content.

The comparer:

- permits only top/bottom system-chrome cropping and rejects any side crop;
- rejects a chrome crop over 15% of source height;
- permits an optional, exactly validated solid vertical layout spacer for
  cross-viewport captures and rejects non-solid or oversized bands;
- permits manifest gates from SSIM 0.82–1 and outliers 0–10%, while the strict
  default remains SSIM ≥ 0.97 and outliers ≤ 3%;
- reserves the wider SSIM ≥ 0.82/outliers ≤ 10% tier for explicitly reviewed
  native cross-platform presentation differences, with exact state, copy,
  flat colors, landmark movement ≤ 2 points, and masks ≤ 2% still mandatory;
- rejects every individual mask over 1%, requires a technical reason, and
  accepts only `systemChrome`, `textCursor`, `timestamp`, or
  `dynamicAnimation`;
- samples flat app-owned colors in each native image before normalization;
- derives landmark edges, spans, and run sizes from bounded horizontal or
  vertical color probes over each native cropped app-content image;
- emits normalized reference/candidate images, RGB diff, heatmap, mask,
  measurements, and a machine-readable result.

Landmark probes declare only how to inspect each image: scan axis and bounds,
expected color, optional per-channel tolerance up to 18, optional minimum
contiguous-run length, and the edge/span/run measurement to extract. The
reference and candidate values in `result.json` are measured from their PNGs;
the comparer rejects different reference/candidate probe instructions, and
manifests cannot supply the resulting coordinates. The comparer self-test
changes the candidate pixels and proves that the extracted landmark delta
fails independently of the aggregate image metric.

An aggregate metric cannot waive a visible defect. `manualReview.status` must
be `accepted` with a reviewer and notes before the gate exits successfully.
`pending` exits 2; a metric or review failure exits 1; an invalid manifest exits
64. Baseline replacement is outside this tool by design.
