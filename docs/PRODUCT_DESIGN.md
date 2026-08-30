# Nile product design system

Nile is designed as a native iPhone application for sustained work with Hermes.
Its interface is content-first: transcripts remain visually primary, controls
stay compact without sacrificing touch area, and state is communicated through
structure, copy, and restrained semantic color.

The current visual language draws inspiration from
[Beautiful UI](https://www.beautifului.dev/) while remaining implemented in
SwiftUI and UIKit with native accessibility behavior.

## Visual tokens

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| page | `#FAFAFB` | `#17181A` | transcript and sheet background |
| canvas | `#F1F2F3` | `#1C1D1F` | recessed workspace and activity canvas |
| surface | `#FFFFFF` | `#232427` | cards, composer, and headers |
| inset | `#F7F8F9` | `#1F2022` | nested content |
| field | `#F2F2F3` | `#2B2C2F` | fields and user messages |
| hover | `#F4F5F6` | `#2A2B2E` | pressed and selected rows |
| line | `#ECEDEF` | `#2E3033` | one-pixel separators |
| strong line | `#E0E2E5` | `#3A3C40` | controls and focus boundaries |
| ink | `#1F2124` | `#F2F3F4` | primary text |
| secondary ink | `#62656B` | `#A5A8AD` | metadata |
| faint ink | `#9A9DA3` | `#6C6F75` | disabled and tertiary state |
| accent | `#0285FF` | `#3D9AFF` | selection and primary action |
| green | `#189A4D` | `#3DBB72` | completed activity |
| orange | `#EF720C` | `#F68F3C` | needs-input state |
| red | `#E3474C` | `#EE5C61` | destructive and failed state |

Geometry uses 8-point control, 10-point card, and 14-point window radii.
Typography uses the checked-in compact hierarchy and scales through Dynamic
Type. Hairline borders and tonal layers establish hierarchy without decorative
chrome.

## Interaction model

- The transcript is the stable workspace. Assistant output remains unboxed;
  user text uses a neutral raised field.
- The composer owns target, attachment, draft, model, context, speech, stop,
  and send state in one anchored surface.
- Blocking clarification, approval, sudo, and secret requests appear inline.
  Continue stays disabled until input is valid, and malformed prompts remain
  visible but non-actionable.
- Session navigation keeps recent work close while search, filtering, pinning,
  and full history remain available in the expanded session surface.
- Tool activity, todos, delegation, goals, context, and usage data use dense
  rows and progressive disclosure instead of modal interruption.
- Model and reasoning changes are session-specific and require confirmation
  when they could disrupt active work.
- Talk mode enlarges the active state and primary controls while keeping
  transcript content private during capture.
- Destructive actions require explicit confirmation and expose in-progress
  state so they cannot be submitted twice.

## Native behavior

- Follow the user's system appearance.
- Respect Dynamic Type and Reduce Motion.
- Keep interactive targets at least 44 by 44 points.
- Use semantic focus order and stable accessibility identifiers.
- Use secure entry for credentials and keep secret values out of accessibility
  labels, screenshots, logs, and retained fixtures.
- Use platform sheets, navigation, keyboard behavior, photo pickers, camera,
  biometrics, notifications, and Quick Look where they improve the iPhone
  experience.
- Preserve user context across keyboard changes, backgrounding, reconnects,
  session switches, and delayed asynchronous callbacks.

## Verification

Design changes require more than a successful build. Review the affected
journey on the canonical iPhone 17 Pro/iOS 26.5 Simulator in light and dark
appearances, exercise large text and Reduce Motion when relevant, and run the
focused UI contracts using accessibility identifiers. Inspect screenshots at
native scale and verify copy, hierarchy, clipping, touch targets, keyboard
order, loading state, error state, and destructive confirmations.

Generated captures belong under ignored `build/` directories and must not
contain credentials, real conversations, personal photos, or other user data.
