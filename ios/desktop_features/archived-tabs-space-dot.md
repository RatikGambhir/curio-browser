# Archived Tabs: space dot and close time

| | |
| --- | --- |
| **iOS status** | Not started |
| **Built on desktop** | 2026-11-03, not yet committed |
| **Ticket** | None |

## What you built

Archived Tabs on desktop now survive a restart (iOS already did, through
`workspace.json`). Each row now shows a small dot in its space's color, so
it's clear at a glance which space a closed tab came from. Each closed tab
also records when it was closed, so the list stays newest first after a
restart.

## Functionality

- **Where:** Library › Archived Tabs.
- **Each row:** favicon, title, subtitle "host · Space name" (unchanged),
  and on the right an **8 pt dot** in the space's accent color (with
  gradient themes, the theme's accent; see `space-gradient-themes.md`).
- **Order:** newest first, by close time.
- **Tooltip / hint:** "Reopen in ⟨Space name⟩" (was "Reopen Tab").
- **Search** now also matches the space name, so typing "work" lists tabs
  closed in Work.
- Tabs whose space was deleted are dropped (unchanged).

## Requirements

### Functional

- [ ] Dot in the space's accent color, 8 pt, at the trailing end of the row.
- [ ] Newest first by `closedAt`; ties keep their saved order.
- [ ] Search matches title, URL and space name, every word.
- [ ] Hint/tooltip "Reopen in ⟨Space name⟩".

### Data and storage

- Desktop: a new `closed_tabs` table (migration v3) holds each closed tab as
  JSON, including `closed_at` (milliseconds since the Unix epoch, default 0
  for older rows), at most 50.
- iOS: add `closedAt: Timestamp` to `Core/Spaces/ClosedTab.swift`, set it in
  `Workspace.closeTab`, and decode it with a default of 0 so existing
  `workspace.json` files still load. Sort by it when restoring
  (`Workspace.init(spaces:favorites:closed:)`).

### Settings

None.

### Commands and shortcuts

None.

### Permissions, network and AI

None.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-spaces/src/lib.rs` | `ClosedTab.closed_at`, `restore_closed_tabs` (drops missing spaces, sorts newest first, keeps 50). |
| `browser/crates/curio-storage/src/{migrations,database}.rs` | The `closed_tabs` table, saved and loaded with the session. |
| `browser/crates/curio-ui/src/window/library.rs` | `render_library_archive`: the dot, search by space name, tooltip. |

Tests: `curio-spaces` `restored_closed_tabs_are_newest_first_and_skip_missing_spaces`;
`curio-storage` `closed_tabs_survive_a_restart_newest_first`.

## iOS notes

- The row lives in `UI/Library/LibraryViewController.swift`
  (`workspace.closedTabs…`). Add the dot as a trailing `ColorDotView`.
- VoiceOver: include the space name in the row's label, e.g.
  "Google Search, google.com, closed in Work".
- Narrow and wide layouts: no difference.

## Acceptance criteria

- [ ] Each archived row shows its space's dot.
- [ ] Order is newest first, and stays that way after relaunching.
- [ ] Searching a space's name filters to that space's tabs.
- [ ] An old `workspace.json` without `closedAt` still loads.
- [ ] VoiceOver reads the space name.

## Open questions

None.
