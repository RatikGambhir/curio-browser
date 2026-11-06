# Arc-style folders

| | |
| --- | --- |
| **iOS status** | Not started (iOS already has folders; this adds empty folders, inline rename and saved tabs) |
| **Built on desktop** | 2026-11-06, uncommitted at time of writing |
| **Ticket** | None |

## What you built

Folders in the sidebar now work like Arc's. You can make an empty folder and
name it right where it appears, double-click a folder to rename it, and tabs
you put in a folder stay there: closing one unloads it instead of deleting it.
Everything is saved with the session.

## Functionality

- **How to get to it:**
  - New empty folder: `NewFolder` action, ⌥⌘N, Tab menu → **New Folder**,
    command bar → **New Folder**, or right-click empty space at the bottom of
    the sidebar → **New Folder**.
  - Folder from the current tab: `NewGroupFromTab`, ⌥⌘G (unchanged; label is
    now **New Folder from Tab**).
  - Tab context menu → **Move to Folder** → **New Folder…** or an existing
    folder; **Remove from Folder**.
  - Folder context menu: **Rename Folder**, **Color**, **Move Folder to
    Space**, **Remove Folder, Keep Tabs**, **Delete Folder and Tabs**.
- **New folder:** named "New Folder", colored with the next accent color in
  `AccentColor.ALL` (`(folderCount + 1) % count`), placed at the **top of the
  unpinned section** of the active space, and opened for renaming right away.
  If the Library is open it closes; if the sidebar is hidden it peeks.
- **Rename in place:** the folder's title becomes a text field with the whole
  name selected. **Enter** or clicking away saves; **Escape** cancels. A
  blank name keeps the old one. Double-clicking a folder row starts it (the
  first click's collapse/expand is undone, so the folder ends up as it was).
  This replaces the old Rename dialog.
- **Collapse:** single click on the folder row toggles it (unchanged). The
  collapsed state is saved.
- **Tabs in folders are saved:** a tab is "saved" when it's pinned **or** in
  a folder (`TabStrip::is_saved`). When a tab enters a folder it remembers
  its current URL as `home_url` (if it doesn't have one). When it leaves the
  pinned section and every folder, `home_url` is cleared.
  - **Close Tab / ⌘W** on a saved tab unloads it: the page is released, the
    URL resets to `home_url`, scroll resets, and it stays in the folder.
  - The tab context menu shows **Unload Tab** for saved tabs, plus a new
    **Delete Tab** that really closes it (it goes to Archived Tabs).
  - ⌘W on a pinned tab now unloads too (before it closed it), matching the
    context menu.
- **New tabs open outside folders** (`TabStrip::placement_for_new_tab`):
  from a regular tab, right after it; from a tab in a regular (unpinned)
  folder, right after the folder; from a pinned tab (in a folder or not) or
  with no active tab, at the top of the unpinned section. This applies to
  ⌘T, links opened in a new tab, and URLs from other apps. Duplicate Tab
  still puts the copy next to the original, inside its folder.
- **Empty folders** are allowed and stay until deleted, including after their
  last tab is closed or moved out.
- **Edge cases:** horizontal tab layout doesn't show folders, so New Folder
  still creates one but skips the rename. Folders don't nest.

## Requirements

### Functional

- [ ] New Folder creates an empty folder at the top of the unpinned section
      and starts an inline rename.
- [ ] Inline rename: Enter/click-away saves, Escape cancels, blank ignored.
- [ ] Tabs moved into a folder get `home_url` = current URL if unset; tabs
      moved out of all folders and the pinned section lose `home_url`.
- [ ] Close on a pinned or folder tab unloads and resets it to `home_url`.
- [ ] Delete Tab on a saved tab closes it into Archived Tabs.
- [ ] Empty folders survive restarts; name, color, collapsed state and tab
      order survive restarts.

### Data and storage

No schema change. Folders are the existing `tab_groups` table (`id`,
`space_id`, `name`, `color`, `collapsed`) plus `layout` rows; tabs' `home_url`
is the existing `tabs.home_url` column. iOS: same fields in the workspace JSON.

### Settings

None.

### Commands and shortcuts

| Action name | Default shortcut | Menu |
| --- | --- | --- |
| `curio::NewFolder` (new) | ⌥⌘N (`alt-secondary-n`) | Tab → New Folder |
| `curio::NewGroupFromTab` (relabeled) | ⌥⌘G | Tab → New Folder from Tab |
| `curio::CloseTab` (behavior change) | ⌘W | unloads saved tabs |

### Permissions, network and AI

None.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-tabs/src/lib.rs` | `is_saved`, `sync_home` (called from `insert` and `move_tab`), `placement_for_new_tab` |
| `browser/crates/curio-spaces/src/lib.rs` | `placement_near_active` uses `placement_for_new_tab` |
| `browser/crates/curio-ui/src/window/tabs.rs` | `open_url_in_new_tab` uses `placement_for_new_tab` |
| `browser/crates/curio-ui/src/actions.rs` | `NewFolder` action, shortcut and menu item |
| `browser/crates/curio-ui/src/command_bar.rs` | New Folder command |
| `browser/crates/curio-ui/src/window/commands.rs` | `new_folder`, `new_group_with`, ⌘W → `close_or_unload_tab`, Escape cancels rename |
| `browser/crates/curio-ui/src/window/sidebar.rs` | `FolderRename`, `rename_group` / `commit_folder_rename` / `cancel_folder_rename`, folder row double-click and inline field, menus, empty-area context menu |

Tests: `browser/crates/curio-tabs/src/lib.rs`
(`tabs_in_folders_are_saved_with_a_home_url`,
`an_empty_folder_stays_until_deleted`, `new_tabs_open_outside_folders`),
`browser/crates/curio-spaces/src/lib.rs`
(`a_new_tab_from_a_folder_tab_opens_below_the_folder`) and
`browser/crates/curio-storage/src/database.rs` (`folders_survive_a_restart`).

## iOS notes

- **Narrow and wide layouts:** New Folder from the sidebar's "+" or
  long-press menu on empty sidebar space; rename in place with a text field in
  the folder row (keyboard appears, Return saves, tapping away saves).
- **Touch:** single tap toggles collapse; use the context menu (long press)
  for **Rename Folder** instead of double-tap, which would conflict with tap.
- **Hardware keyboard:** ⌥⌘N for New Folder via `CurioCommand.newFolder =
  "curio::NewFolder"`; Escape cancels a rename.
- Logic goes in `Curio/Core/Tabs/TabStrip.swift` (`isSaved`, home URL sync on
  insert/move) and `Session/BrowserSession.swift` (close → unload for saved
  tabs; `newFolder`).

## Acceptance criteria

- [ ] ⌥⌘N makes "New Folder" at the top of the tabs with its name selected
      for editing; typing a name and Return saves it.
- [ ] Escape during rename leaves the old name.
- [ ] Drag a tab into a folder, close it: it stays in the folder, unloaded,
      and reopens at the URL it had when added.
- [ ] With a folder tab active, ⌘T opens the new tab directly below the
      folder, not inside it.
- [ ] Delete Tab removes it and it shows in Archived Tabs.
- [ ] Collapse a folder, quit, relaunch: still collapsed, same name, color
      and tabs. An empty folder is still there.
- [ ] Unit tests ported from the Rust tests above.

## Open questions

- Nested folders (Arc has them) aren't supported on desktop yet.
