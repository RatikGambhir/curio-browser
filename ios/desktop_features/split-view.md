# Split view

| | |
| --- | --- |
| **iOS status** | Built on iOS |
| **Built on desktop** | 2026-11-10, branch `feature/folders` (after commit `3022174`) |
| **Ticket** | |

## What you built

Two to four tabs can be shown side by side in one window, like Arc's and
Dia's split view, so you can read one page while writing in another or
compare pages without switching tabs. A split belongs to the space it was
made in, and to the folder it was made in, and is saved with the session.

## Functionality

### How to get to it

- **Split View** (`curio::SplitView`, ⌃⇧=; Tab menu; command bar "Split
  View"): adds a new tab beside the active tab and opens the command bar to
  choose its page. If the active tab is already in a split, the new tab
  becomes another pane right after it.
- **Open in Split View** in a tab's context menu (shown for any tab of the
  space other than the active one, when the active tab is not a favorite):
  shows that tab after the active tab.
- **Drag a tab onto the page:** while a tab is dragged from the sidebar, the
  page area splits into a left and a right drop zone. Dropping on the left
  puts the tab before the current page, on the right after it.
- **Separate Split View** (`curio::SeparateSplitView`, ⌃⇧-; Tab menu;
  command bar): the active tab's split becomes ordinary tabs again, in place.

### What the user sees

- **Panes:** the panes sit next to each other with an 8pt gap. Each pane is
  its own rounded page card. The focused pane (the space's active tab) has
  an accent-colored outline and the normal page bar (back, forward,
  address, assistant). Other panes show a slim header instead: favicon,
  title, a "Remove from Split View" button (unlink icon) and a close button
  (✕, or − for saved tabs, which unload). The focused pane's page bar also
  has a "Remove from Split View" button.
- **Focus:** clicking anywhere in a pane, including inside the web page,
  makes it the active tab. The address bar, find in page, zoom, reload,
  selection actions and the assistant's "current tab" all follow the
  focused pane.
- **Resizing:** dragging the gap between two panes resizes them. Each pane
  keeps at least 15% of the split. Double-clicking a gap makes all panes
  equal. Sizes are saved.
- **Orientation:** panes are side by side by default. "Stack Panes" in a
  pane's tab menu puts them top to bottom; "Show Side by Side" switches
  back. Saved per split.
- **Sidebar:** a split is one row, in the place of its first tab: a
  rounded, outlined box with one segment per pane (favicon and title,
  divided by thin lines). The segment of the focused pane is highlighted,
  and the box gets a hover background while it holds the active tab.
  Clicking a segment focuses that pane; ⌘-click attaches it to the
  assistant; middle-click closes it. Right-clicking a segment shows the
  tab's usual menu with split items first: Remove from Split View, Stack
  Panes / Show Side by Side, Equal Pane Sizes, Separate Split View.
- **Horizontal tab layout:** the split's tabs appear as ordinary tabs in the
  strip; the page area still shows the panes, without the per-pane headers.

### Where a split lives (the "saved in its space and folder" rule)

- A split's tabs are always next to each other, in pane order, in **one**
  container: the pinned section, the unpinned section, or one folder.
- A new split forms where the **active** tab is. Splitting a tab that is in
  a folder brings the other tab into that folder (so it becomes a saved tab
  with a home URL, like any folder tab). Splitting a pinned tab pins the
  other one.
- Moving any pane (drag, Pin/Unpin, Move to Folder, Move to Space) moves the
  whole split. Moving a folder to another space takes its splits along.
  Moving a split to another space keeps its orientation and sizes.
- Nothing can be placed between a split's panes: a tab dropped or opened
  "between" them ends up right after the split. New tabs opened from a pane
  (links, ⌘T) open after the whole split.

### Edge cases

- **Closing a pane** (⌘W, close button): the tab closes as usual and the
  pane beside it (the next one, or the previous one for the last pane)
  becomes active. A split left with one tab dissolves.
- **Unloading a saved pane** (pinned or folder tab): it leaves the split
  first (otherwise showing the split would load it again), then unloads.
- **Remove from Split View:** the tab leaves the split and is placed right
  after it; a split left with one tab dissolves.
- **Full split:** a fifth pane is refused with the message "A split view
  shows up to 4 tabs".
- **Favorites** can't be in a split. Split View with a favorite active
  shows "Favorites can’t be shown in a split view". Dropping a tab on the
  page while a favorite is active just switches to the dropped tab.
- **A tab can be in only one split.** Adding it to another takes it out of
  the first (which dissolves if it drops below two).
- **Tabs from another space** dropped on the page move to the active space
  first.
- **Reopen closed tab** brings back the tab but not its split.
- **Empty pane:** a Split View pane starts on the new tab page; dismissing
  the command bar leaves it there. If the pane is pinned or in a folder,
  its first navigation sets its home URL for later unloads.

## Requirements

### Functional

- [ ] On iPad and on the iPhone Duo inner display, show 2–4 tabs of one
      space side by side or stacked when the page area can fit the panes,
      each with its own live web view.
- [ ] The space's active tab is the focused pane; every other pane is
      visible but not focused.
- [ ] Only the panes of the visible split keep their web views shown;
      other tabs stay hidden and may sleep as usual. Visible panes never
      sleep.
- [ ] Splits follow the container rule above and move as one.
- [ ] Pane sizes (min 15% each) and orientation persist.
- [ ] Splits are restored on launch in the same space and folder.

### Data and storage

New model type in `curio-core` (Swift: next to `TabGroup` in
`Core/Tabs/`):

```text
TabSplit {
  id: SplitId          // UUID, like GroupId
  tabs: [TabId]        // pane order: left→right or top→bottom; 2…4 items
  sizes: [Float]       // one share per pane, sums to 1, each ≥ 0.15
  orientation: "horizontal" | "vertical"   // default horizontal
}
```

The tab strip (`TabStrip`) gains `splits: [SplitId: TabSplit]`. It is
serialized with the strip (`#[serde(default)]`, so older data loads with no
splits).

Desktop SQLite migration **v4**:

```sql
CREATE TABLE tab_splits (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    data TEXT NOT NULL      -- the TabSplit as JSON
);
CREATE INDEX tab_splits_space ON tab_splits(space_id);
```

On iOS, store the splits inside each space's strip in the workspace JSON
(`WorkspaceStore`). When loading, repair them exactly like desktop's
`TabStrip::repair_splits`: drop panes whose tabs are gone, keep a tab only
in the first split (by id order) that lists it, drop splits with fewer than
two panes, reset unusable sizes to equal, then gather each split's tabs
after its first pane.

### Settings

None.

### Commands and shortcuts

| Action name | Default shortcut | Menu |
| --- | --- | --- |
| `curio::SplitView` | ⌃⇧= (`ctrl-shift-=`) | Tab › Split View |
| `curio::SeparateSplitView` | ⌃⇧- (`ctrl-shift--`) | Tab › Separate Split View |

Both are also in the command bar's command list ("Split View", "Separate
Split View").

### Permissions, network and AI

None. The page bridge script gained one message: `{"type": "focus"}` posted
on `pointerdown` (capture, passive), which the app uses to focus the
clicked pane. It carries no page data.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-core/src/tab.rs` | `TabSplit`, `SplitOrientation`: equal panes, add/remove a pane, resize a divider with the 15% minimum, normalize sizes |
| `browser/crates/curio-core/src/ids.rs` | `SplitId` |
| `browser/crates/curio-tabs/src/lib.rs` | Splits in `TabStrip`: `create_split`, `add_to_split`, `remove_from_split`, `dissolve_split`, `resize_split`, `flip_split`, `equalize_split`, `split_of`, `Row::Split`, `repair_splits` (keeps panes together), whole-split moves in `move_tab`, `TakenGroup` for moving folders with their splits |
| `browser/crates/curio-spaces/src/lib.rs` | `move_tab_to_space` moves a whole split; `close_tab` activates the neighboring pane |
| `browser/crates/curio-storage/src/migrations.rs`, `database.rs` | v4 `tab_splits` table, save and load |
| `browser/crates/curio-browser/src/scripts.rs`, `ipc.rs`, `tab.rs` | The `focus` bridge message → `BrowserTabEvent::Focused` |
| `browser/crates/curio-ui/src/window/split.rs` | Pane layout, dividers and resizing, pane headers, drop zones, the split commands |
| `browser/crates/curio-ui/src/window/content.rs` | `render_page_card`, shared by single pages and panes |
| `browser/crates/curio-ui/src/window/tabs.rs` | `sync_active_tab` shows every pane of the visible split; focusing on click |
| `browser/crates/curio-ui/src/window/sidebar.rs` | The split row and split menu items |
| `browser/crates/curio-ui/src/actions.rs` | `SplitView`, `SeparateSplitView` with shortcuts and menu items |

Tests that define the behavior:

- `curio-core/src/tab.rs`: `split_starts_with_equal_unique_panes`,
  `split_resize_keeps_panes_above_the_minimum`,
  `removing_a_pane_gives_its_room_to_a_neighbor`,
  `split_normalize_repairs_bad_sizes`
- `curio-tabs/src/lib.rs`: `create_split_gathers_tabs_next_to_the_first`,
  `a_split_made_in_a_folder_is_saved_in_that_folder`,
  `moving_one_pane_moves_the_whole_split`, `tabs_never_land_inside_a_split`,
  `closing_a_pane_dissolves_a_split_of_two`,
  `remove_from_split_puts_the_tab_after_it`, `a_tab_joins_only_one_split`,
  `split_resize_flip_and_dissolve`, `splits_move_with_their_folder`,
  `from_parts_repairs_splits`
- `curio-spaces/src/lib.rs`: `a_split_moves_to_another_space_as_a_whole`,
  `closing_a_pane_shows_the_pane_beside_it`
- `curio-storage/src/database.rs`:
  `split_views_survive_a_restart_in_their_space_and_folder`
- `curio-browser/src/ipc.rs`: `focus_messages_need_the_token`
- `curio-ui/src/window/split.rs`: `divider_fraction_ignores_the_gaps`

## iOS implementation

| File | What it does |
| --- | --- |
| `Core/Tabs/TabSplit.swift` | `TabSplit`, `SplitOrientation`: equal panes, add/remove a pane, resize with the 15% minimum, normalize sizes |
| `Core/Tabs/TabStrip.swift` | Splits in the strip: `createSplit`, `addToSplit`, `removeFromSplit`, `dissolveSplit`, `resizeSplit`, `flipSplit`, `equalizeSplit`, `adoptSplit`, `split(of:)`, `.split` rows, `repairSplits`, whole-split moves, `TakenGroup`; saved as `splits` in each strip of `workspace.json` |
| `Core/Spaces/Workspace.swift` | `moveTab(_:toSpace:)` moves a whole split; `closeTab` focuses the pane beside |
| `Session/SplitRoom.swift` | Whether the page area can show a split (240pt per side-by-side pane, 180pt per stacked pane) and the divider math |
| `Session/BrowserSession.swift` | Visible panes stay awake, the split commands, drop handling, unloading a pane, focusing a pane |
| `Browser/PageScripts.swift`, `BrowserTab.swift` | The bridge's `focus` message |
| `UI/Page/SplitContainerView.swift`, `PaneView.swift`, `SplitDropOverlay.swift`, `PageViewController.swift` | Panes, dividers (44pt touch target, double-tap to equalize), pane headers and placeholders, drop zones |
| `UI/Sidebar/SplitRowCell.swift`, `SidebarViewController.swift`, `SidebarMenus.swift` | The split row, its segment menus, Open in Split View |
| `UI/Commands/CurioCommand.swift`, `MainMenuBuilder.swift`, `BrowserViewController+Commands.swift` | `SplitView` (⌃⇧=) and `SeparateSplitView` (⌃⇧-), hidden and disabled while no split fits |
| `CurioTests/SplitViewTests.swift` | The desktop tests above, ported |

## iOS notes

- **Availability:** enable Split View on iPad and on the iPhone Duo inner
  display when the page area has room for the panes. Check the available
  page area after accounting for the sidebar and assistant. Regular iPhones
  use the single-page layout in portrait and landscape, including when
  landscape uses Curio's wide layout.
- **Single-page layout:** on the iPhone Duo outer display or when an iPad
  or iPhone Duo window becomes too small, show the focused tab and list
  the panes as individual tabs. Hide Split View menu items, command bar
  actions and split drop zones, and disable its keyboard shortcuts. Keep
  the split, pane sizes and orientation saved. Restore the split when the
  page area can fit it again and a member tab is active.
- **Split picker:** choosing an open tab puts it in the blank pane's slot.
  Choosing a pane from another space moves only that tab. Dismissing the
  picker removes the blank pane and restores the prior focus and sizes.
- **Touch instead of hover and right-click:** the split row's segments get
  the tab context menu on long press, with the split items first. Drag the
  gap with a pan gesture (make the hit target at least 44pt even though the
  visible gap is 8pt). Double-tap the gap to equalize.
- **Drop zones:** use a drop interaction on the page area for tabs dragged
  from the sidebar; on iPad, also accept a tab dragged from the tab switcher.
- **Focusing a pane:** a tap in a web view doesn't reach UIKit gesture
  recognizers reliably; use the same bridge `focus` message (already
  validated by token in the bridge) or a simultaneous tap recognizer on
  the pane container.
- **Hardware keyboard and the iPad menu bar:** add `SplitView` and
  `SeparateSplitView` to `UI/Commands/CurioCommand.swift` with ⌃⇧= and ⌃⇧-
  and put them in the Tab menu.
- **Memory:** each pane is a live web view. Keep the desktop rule that only
  the visible split's panes are exempt from sleeping, and cap at four.
- Suggested places: model and repair logic in `Core/Tabs/TabStrip.swift`
  (new `TabSplit.swift`), space moves in `Core/Spaces/Workspace.swift`,
  persistence in `Storage/WorkspaceStore.swift`, visibility in
  `Session/BrowserSession.swift`, and a `SplitContainerView` under
  `UI/Page/`.

## Acceptance criteria

- [ ] Split View (⌃⇧= or menu) opens a new pane beside the active tab with
      the command bar; choosing a page loads it in that pane.
- [ ] Open in Split View from a tab's menu shows it after the active tab.
- [ ] Dropping a tab on the left/right of the page puts it before/after.
- [ ] Tapping a pane (or its sidebar segment) focuses it; the address bar,
      reload, find and the assistant follow.
- [ ] Dragging a gap resizes; panes stop at 15%; double-tap equalizes.
- [ ] Stack Panes / Show Side by Side switches orientation.
- [ ] A split made from a tab in a folder stays in that folder after
      relaunch, with both tabs saved (unload instead of close).
- [ ] Pinning, moving to a folder, or moving to another space moves the
      whole split; sizes and orientation survive the move.
- [ ] Closing a pane focuses the pane beside it; a two-pane split
      dissolves into a normal tab.
- [ ] A fifth pane and favorites are refused with the messages above.
- [ ] Relaunching restores every split, its sizes and orientation.
- [ ] Split View is available on iPad and on the iPhone Duo inner display
      when the page area can fit the panes. Regular iPhones in portrait and
      landscape and the iPhone Duo outer display show the single-page
      layout without Split View controls or shortcuts.
- [ ] Resizing an iPad window or folding an iPhone Duo shows the focused
      tab when the split no longer fits. Widening the window or unfolding
      restores the split with its saved pane sizes and orientation.
- [ ] Light and dark themes, Dynamic Type, VoiceOver labels ("Split view:
      <title> and <title>"), Reduce Motion.
- [ ] Unit tests ported for the logic (match the Rust tests above).

## Open questions

- Should reopening a closed pane put it back into its split? Desktop
  doesn't yet.
