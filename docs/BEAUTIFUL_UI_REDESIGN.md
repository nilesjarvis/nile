# Beautiful UI design system

Status: implemented and selected for mainline integration on 2026-08-15.

Reference: [Beautiful UI](https://www.beautifului.dev/), inspected on
2026-08-13 in both light and dark appearances.

## Status and intent

This implementation is a complete alternate visual direction for Nile. It ports the
Beautiful UI component language to native SwiftUI while retaining Nile's
existing domain, security, accessibility, and Hermes interaction contracts.
It does not replace or waive the Android source-of-truth contract in
`IOS_PORT_GOAL.md`; it should be evaluated as a product-design proposal.

The redesign is intentionally content-first: flat graphite layers replace
glass, one-pixel borders establish hierarchy, blue is reserved for a current
selection or primary action, orange is reserved for blocking input, and green
is reserved for successful tool activity. Controls keep a compact visual
footprint while retaining at least 44 by 44 points of touch area.

## Native visual system

The SwiftUI tokens are sampled directly from the reference implementation.

| Role | Light | Dark | Nile use |
| --- | --- | --- | --- |
| page | `#FAFAFB` | `#17181A` | transcript and sheet background |
| canvas | `#F1F2F3` | `#1C1D1F` | recessed workspace and activity canvas |
| surface | `#FFFFFF` | `#232427` | cards, composer, headers |
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

Geometry follows the reference's 8-point control, 10-point card, and 14-point
window radii. Typography uses the native system face at the reference's compact
10, 11, 13, 14, and 21-point hierarchy. This is the closest platform-native
equivalent to the reference's Inter-first stack and preserves Dynamic Type and
the repository's Android text-measurement contracts.

## Component and interaction mapping

| Beautiful UI element | Nile placement | Interaction decision |
| --- | --- | --- |
| Loading State | startup and Talk canvas | The 3-by-3 pixel grid communicates transient work without a large branded spinner. Reduced Motion freezes the grid. |
| Thinking | live turn and tool activity | Status remains inline with the transcript and expands only when details are requested. |
| Streaming Text | assistant Markdown | Text streams directly on the page; a quiet 44-point copy target appears at the trailing edge. |
| Approval Card | blocking clarification, approval, and credential prompts | The card interrupts visually without becoming a modal. Continue remains disabled until the response is valid; malformed prompts remain non-actionable. |
| Tool Chips | transcript tool groups and command affordances | Compact state color identifies running, completed, failed, and waiting work. Details disclose in place. |
| Task Rows | delegated agents and todo activity | Dense rows expose status first and keep interrupt or navigation actions at the trailing edge. |
| Chat | session workspace | Assistant output stays unboxed; user text alone receives a neutral raised field. |
| Prompt Bar | composer | One anchored surface owns target, attachment, draft, model, context, speech, stop, and send controls. Send is high-contrast ink, while blue is kept for selection. |
| Recommendation Card | standing-goal status | Goal summary, progress, budget, and next action stay in one persistent card before opening details. |
| Context Cards | context breakdown | Token categories use nested inset cards and restrained chart colors. |
| Diff Table | transcript diff tool | Existing additions and removals inherit the reference borders, compact type, and semantic success/error colors. |
| Records Table | statistics and structured tool output | Rows use hairline division rather than individual floating containers. |
| Filter Table | expanded sessions | Search, status filtering, timestamps, pinning, and current selection are combined in the pull-down session window. |
| Sidebar Nav | collapsed session strip and expanded session window | The desktop sidebar becomes a horizontal recent-session strip on a phone; pulling the handle reveals the full navigable list without replacing the transcript. |
| Search | session search and command palette | Search is contextual and dismissible; results preserve stable row targets and keyboard navigation behavior. |
| Insight Cards | gateway usage and goal summaries | Summary metrics remain scannable cards, while detailed records move below them. |
| Code Block | terminal and code tool output | Monospaced output sits on the field layer with semantic syntax color and no ornamental chrome. |
| Fine-tune Card | model, provider, and reasoning controls | Session-specific settings stay behind the model line and require confirmation when changing an active session. |
| Selection Actions | message copy, steering, and response actions | Actions stay visually quiet until the relevant message or run state makes them useful; destructive actions use red and explicit confirmation. |

## Complete component audit

The site exposed 19 component demos on 2026-08-13. The audit opened every demo
and its full source panel, then compared geometry, color, type, hierarchy, and
interaction state against the corresponding iPhone surface. “Adapted” means the
web pattern is deliberately expressed through the equivalent accessible iOS
interaction rather than copied as a non-native control.

| Reference component | Before this audit | Resolution on this branch |
| --- | --- | --- |
| Loading State | Matched | Retained the pixel-grid loading and Talk treatments, including reduced-motion behavior. |
| Thinking | Partial | Compact disclosure headers, status metadata, current activity, and the one-pixel trace now share the reference hierarchy. |
| Streaming Text | Matched | Retained unboxed streaming Markdown and suppressed settled-only actions while a response is live. |
| Approval Card | Matched | Retained inline, fail-closed approval/clarification cards with semantic state and explicit Continue. |
| Tool Chips | Partial | Default tool and terminal rows now use compact inset chips, 8-point corners, hairlines, monospaced detail, and in-place disclosure. |
| Task Rows | Partial | Delegated agents and todos now use dense inset rows, status-first metadata, compact disclosure, and a vertical detail trace. |
| Chat | Matched | Retained unboxed assistant content, neutral user bubbles, and quiet message-level actions. |
| Prompt Bar | Matched | Retained the single bordered composer surface and its model, attachment, speech, send, stop, and context states. |
| Recommendation Card | Partial | Standing-goal summary and detail surfaces now use 10-point cards, inset content, hairlines, and 8-point actions. |
| Context Cards | Missing treatment | Replaced the translucent 250-point sheet and plain rows with an opaque 14-point window, useful 420-point initial detent, inset category cards, and complete visible composition. |
| Diff Table | Partial | Added the framed header, divider, inset diff body, stronger semantic row tints, and compact monospaced lines. |
| Records Table | Matched | Retained dense session/stat records with stable row targets and hairline hierarchy. |
| Filter Table | Matched | Retained searchable, pinnable session filtering and stable current-selection state in the expanded session window. |
| Sidebar Nav | Adapted | The phone-sized recent-session strip and pull-down directory retain the reference’s navigation hierarchy without installing a desktop sidebar. |
| Search | Partial | Removed native material and oversized rounding from session/model search; both now use the reference inset field, 8-point radius, and one-pixel boundary. |
| Insight Cards | Partial | Usage cards now use 10-point outer surfaces, 8-point metric insets, visible hairlines, compact values, and the reference’s restrained accent hierarchy. |
| Code Block | Missing treatment | Added a framed 10-point block, language/icon header, divider, inset syntax body, and compact Copy action. |
| Fine-tune Card | Partial | Removed the translucent, 24–32-point model sheet; reasoning and model controls now use opaque 14/10/8-point nested surfaces and explicit field borders. |
| Selection Actions | Adapted | iOS text selection remains contextual through the system selection menu; whole-response Copy retains a 44-point target without persistent toolbar chrome or fabricated unavailable actions. |

The audit also removed residual translucent material from context, goal,
statistics, model, search, and voice presentation; normalized app-owned card and
window radii; and retained capsules only where the reference uses a progress,
status, or drag-handle pill.

## Mobile interaction model

- The transcript remains the spatial anchor. Session navigation, model tuning,
  goal details, usage, and context are progressive disclosures rather than new
  permanent navigation layers.
- The compact recent-session strip exposes switching at launch. A downward pull
  or handle tap opens the full Beautiful UI-style records window, including
  search and creation.
- The composer behaves as one Prompt Bar. Its controls may occupy multiple
  visual rows for long drafts or accessibility text, but still read as one
  bordered surface.
- Blocking input is placed immediately before the disabled composer so the
  required response and the reason sending is unavailable are adjacent.
- Talk mode translates the loading component into an audio-state surface and
  keeps Transcript, Pause/Resume, and End as three stable bottom actions.
- Shadows are deliberately shallow. Hierarchy comes from page/surface contrast
  and one-pixel borders, matching the reference in both appearances.
- First launch is a dedicated connection journey: brand, one sentence, one
  primary Add Gateway action, and a secondary App Security route. It is not
  presented as a settings dashboard before a gateway exists.
- Connected Settings is a large contextual sheet over the active session. The
  first level contains only grouped Hermes and Security choices; saved URLs,
  switching, adding, and destructive removal move into the Gateways detail.
  Voice remains a sibling Hermes row, and removal remains behind the row menu
  and explicit confirmation.

## Visual and behavioral verification

Reviewed at iPhone 17 Pro / iOS 26.5 with Large content size and reduced-motion
fixtures. Retained captures and result bundles are under `build/visual-review/`:

- `beautiful-ui-session-dark.png`
- `beautiful-ui-session-light.png`
- `beautiful-ui-approval-dark.png`
- `beautiful-ui-onboarding-light.png`
- `ui-test-attachments/29F5527E-35D7-4025-A0AE-C7AC10AAD4FE.png`
  (Talk listening)
- `ui-test-attachments/65AA9025-5484-4DD9-AA25-76C4E29EF46C.png`
  (expanded sessions)
- `beautiful-ui-audit-20260813.xcresult` and
  `audit-attachments-20260813/` (seven affected journeys, including model,
  code, delegation, goal, context, and insights)
- `beautiful-ui-audit-final-20260813.xcresult` and
  `audit-final-attachments-20260813/` (post-iteration goal, context, and stats)
- `build/settings-hierarchy-verified.xcresult` and
  `build/settings-hierarchy-verified-attachments/` (all-green system-level
  light/dark onboarding, connected Settings, gateway detail, large text,
  secure keyboard, removal, switch, and voice journeys)

Verification on 2026-08-13:

- all 719 `NileTests` pass;
- the 61 architecture contracts and ten focused UI executions pass, including
  code rendering, model tuning, goal creation/detail, context, statistics, and
  collapsed/expanded delegation;
- the unsigned generic-device Release build succeeds; and
- the reference was reviewed in light and dark, and every retained iPhone
  capture above was inspected at original resolution after the final pass.

The Settings follow-up on 2026-08-15 additionally inspected true system light
and dark appearances at original resolution. It verified page/panel/inset
contrast, hairline separation, semantic blue/green/orange use, centered sheet
navigation, 44-point-or-larger actions, large-text wrapping, keyboard order,
progressive disclosure, and confirmation layering on disposable iPhone 17 Pro
/ iOS 26.5 simulators. The audit increased the onboarding heading, shortened
the Voice summary, stabilized the centered Settings title, and expanded the
Add Gateway form's Cancel hit target. These captures evaluate the selected
product design; they do not satisfy the repository's strict Android visual
comparison contract.

The reference site is a living external source. Any later token or component
change should be reviewed against a dated capture before updating this branch.
