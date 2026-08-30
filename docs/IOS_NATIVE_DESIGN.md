# Historical iOS-native design direction

## Status

This is a historical implementation record, not an acceptance-contract
override. It records presentation decisions adopted on the former
`codex/ios-native-glass` branch and explains current divergences in the source
tree. The main branch remains governed by `AGENTS.md` and
`IOS_PORT_GOAL.md`: the pinned Android app-owned design is the visual
acceptance target, and strict comparison failures remain incomplete parity.

## Recorded principles

- Follow the user's system appearance instead of forcing dark mode.
- Use semantic system colors so contrast adapts across light and dark
  appearances.
- Use San Francisco and Dynamic Type metrics for app text.
- Use SF Symbols for familiar actions and status affordances.
- Present settings, goals, model selection, usage, voice configuration, and
  Talk mode with native navigation, sheets, toggles, fields, and buttons.
- Use Liquid Glass on iOS 26 for interactive chrome and material fallbacks on
  iOS 17–25.
- Keep transcript content visually primary. User messages use an iMessage-like
  accent bubble; assistant content remains quiet and readable.
- Preserve stable accessibility identifiers and 44-point minimum interactive
  targets.

## Recorded visual verification

The redesign was reviewed on an iPhone 17 Pro / iOS 26.5 Simulator in both
system appearances. Captures cover:

- connected chat and composer;
- session-header action rail with direct Settings and an anchored Rename/Usage
  popover that preserves the complete title bar;
- model picker;
- standing-goal creation;
- clean and expanded gateway onboarding;
- compact expanded-session sheet, progressive search, and keyboard state;
- settings;
- Talk mode.

Local before/after evidence is retained under
`build/ios-native-redesign/`. Functional UI captures are also retained in the
`onboarding.xcresult`, `goal.xcresult`, and `talk.xcresult` bundles in that
directory. The focused action-rail and open-popover captures are retained in
`build/DerivedData-HeaderPopover/Logs/Test/`.

The expanded-session review additionally retains dark, forced-light, and
search-with-keyboard captures under `build/session-list-polish/`. The surface
uses an adaptive-height Liquid Glass sheet, a 16% scrim, grouped 62-point rows,
explicit selected and needs-input states, a grabber dismissal target, and
on-demand search. Its focused UI contract covers pinning, dismissal, keyboard
appearance and dismissal, filtering, switching, and read-only selection.

These choices made the strict Android pixel-comparison lane red on the original
branch. On `main`, those results are evidence of incomplete visual parity, not
accepted failures. Unit/protocol tests and functional UI contracts remain
required alongside the strict Android comparisons.
