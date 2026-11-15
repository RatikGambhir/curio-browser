# Archived Tabs survive restarts and deleted spaces

| | |
| --- | --- |
| **iOS status** | Not started |
| **Built on desktop** | 2026-11-06, uncommitted at time of writing |
| **Ticket** | None |

## What you built

Archived Tabs (the Library section and Reopen Closed Tab) no longer lose
history. Closed tabs are kept across restarts even when the session isn't
restored, and they stay in the archive after their space is deleted.

## Functionality

- **How to get to it:** unchanged. Library → Archived Tabs, and the Reopen
  Closed Tab command (`ReopenClosedTab`, ⇧⌘T).
- **Deleting a space:** its closed tabs stay in the archive. Before, they were
  removed along with the space.
- **Reopening a tab whose space was deleted:** it opens in the **active
  space**, next to the active tab if that tab is a regular (unpinned) tab,
  otherwise at the top of the unpinned section. It becomes the active tab.
  Tabs whose space still exists reopen in their original space and position,
  as before.
- **Reopen Closed Tab** takes the newest archived tab, whatever its space.
  Before, it skipped tabs from deleted spaces (and threw them away).
- **Archived Tabs list:** a tab whose space was deleted is still listed.
  - Subtitle: just the host (`example.com`), with no ` · Space name` suffix.
  - No space color dot.
  - Tooltip / accessibility hint: `Reopen in <active space name>`.
  - Search matches its title and URL (there's no space name to match).
- **"Restore previous session" off, or the session fails to load:** the app
  starts with a fresh workspace but still loads the saved archive. Before,
  the archive started empty and the first save erased it.
- **Limit:** unchanged, the newest 50 (`CLOSED_TAB_LIMIT`).

## Requirements

### Functional

- [ ] `deleteSpace` no longer removes that space's closed tabs.
- [ ] Restoring saved closed tabs keeps tabs whose space is missing (still
      sorted newest first by `closedAt`, still capped at 50).
- [ ] `reopenClosedTab` and `reopenClosed(_:)` open a tab whose space is
      missing in the active space instead of skipping or dropping it.
- [ ] `archivedTabs(matching:)` returns tabs whose space is missing, with no
      space.
- [ ] When the session isn't restored, the saved closed tabs are still loaded
      into the fresh workspace before anything is saved.

### Data and storage

No schema change. Desktop already stores closed tabs in the `closed_tabs`
table (migration v3), one JSON `ClosedTab` per row. On quit, desktop now also
runs `PRAGMA wal_checkpoint(TRUNCATE)` so `curio.db` holds everything; iOS
stores JSON files, so there's nothing to port for that part.

### Settings

None new. Uses the existing `restore_session` (`browsing.restoreSession`).

### Commands and shortcuts

None new.

### Permissions, network and AI

None.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-spaces/src/lib.rs` | `delete_space` keeps closed tabs; `restore_closed_tabs` keeps orphans; `reopen_closed_tab` / `reopen_closed` share `reopen`, which falls back to `open_tab_in_active_space` |
| `browser/crates/curio-storage/src/database.rs` | `load_closed_tabs` is public; new `checkpoint` |
| `browser/crates/curio-app/src/main.rs` | Loads the archive into `Workspace::first_run()` when the session isn't restored |
| `browser/crates/curio-ui/src/window/library.rs` | `render_library_archive` lists orphaned tabs without a space dot |
| `browser/crates/curio-ui/src/window/mod.rs` | `save_now` checkpoints the database on quit |

Tests: `browser/crates/curio-spaces/src/lib.rs`
(`restored_closed_tabs_are_newest_first_and_keep_missing_spaces`,
`closed_tabs_outlive_their_space_and_reopen_in_the_active_one`) and
`browser/crates/curio-storage/src/database.rs`
(`archived_tabs_persist_in_the_database_file`).

## iOS notes

- Logic lives in `Curio/Core/Spaces/Workspace.swift`: remove
  `closedTabs.removeAll { $0.space == id }` from `deleteSpace`, drop the
  `guard space(closed.space) != nil` checks in `reopenClosedTab` /
  `reopenClosed(_:)` in favor of an active-space fallback, and make
  `archivedTabs(matching:)` return `space: Space?`.
- `Curio/Session/BrowserSession.swift:20`: when `restored` is nil, load the
  stored closed tabs into the fresh workspace.
- Library row UI (`UI/Library/`): hide the dot and the space suffix when
  `space` is nil.
- Narrow and wide layouts, touch and keyboard: no change.

## Acceptance criteria

- [ ] Close a tab, delete its space: the tab is still in Archived Tabs, with
      no color dot and no space name.
- [ ] Tap it: it opens in the active space and becomes the active tab.
- [ ] Reopen Closed Tab with an orphaned tab newest: it reopens in the
      active space instead of being skipped.
- [ ] Turn off "Restore previous session", close a tab, quit, relaunch: the
      tab is still in Archived Tabs.
- [ ] Close a tab, quit, relaunch with restore on: the tab is still there
      (unchanged behavior).
- [ ] VoiceOver reads `Reopen in <active space>` for orphaned rows.
- [ ] Unit tests ported from the Rust tests above.

## Open questions

None.
