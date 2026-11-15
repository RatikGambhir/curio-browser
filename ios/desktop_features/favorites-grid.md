# Favorites grid with an add slot

| | |
| --- | --- |
| **iOS status** | Partly built (iOS has the 4-column grid; the add slot and narrow fallback are new) |
| **Built on desktop** | 2026-11-06, uncommitted at time of writing |
| **Ticket** | None |

## What you built

Favorites show as a grid of tiles at the top of the sidebar, like Dia. The
next free slot is a dashed "+" tile, so the grid is visible and usable even
before you have any favorites.

## Functionality

- **Layout:** fixed columns, four to a row. When the sidebar is too narrow
  for four tiles of at least 48pt (desktop: sidebar under 230px, i.e. inner
  width under 210px), it drops to three. Tiles stretch to fill the row; a
  short last row is padded so tiles keep the same width.
- **Tile:** 40pt tall, 10pt corner radius, the field fill (translucent white
  on light themes), favicon 18pt centered. The active favorite uses the
  selected-row look. Tooltip: the page title.
- **Add slot:** appears in the next free cell when the last row has room, or
  as the only tile when there are no favorites. A full last row doesn't get
  one (no row of just a "+"). Dashed 1pt border in the faint text color at
  28% alpha, a "+" icon, hover fill. Click adds the **current tab** to
  Favorites (ignored for the new-tab page or a tab that's already a
  favorite). Tooltip: "Add Current Tab to Favorites".
- **Drop:** dropping a tab anywhere on the grid adds it (unchanged).
- Context menu on a tile is unchanged (Go to Saved Address, Remove from
  Favorites).

## Requirements

### Functional

- [ ] Add slot shown when favorites are empty or the last row isn't full.
- [ ] Tapping the add slot favorites the current tab.
- [ ] Three columns when four tiles would be narrower than 48pt.

### Data and storage

None.

### Settings

None.

### Commands and shortcuts

None new (`AddFavorite` is unchanged).

### Permissions, network and AI

None.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-ui/src/window/sidebar.rs` | `render_favorites`, `favorite_columns`, `FAVORITE_TILE_HEIGHT`, `FAVORITE_GAP` |

Test: `browser/crates/curio-ui/src/window/sidebar.rs`
(`favorites_fit_four_across_unless_the_sidebar_is_narrow`).

## iOS notes

- `UI/Sidebar/SidebarViewController.swift` already lays favorites out at
  `fractionalWidth(0.25)`. Add an `.addFavorite` item to the favorites
  section under the same rule, and switch to `1/3` when the sidebar's content
  width is under 210pt.
- Show the favorites section (with just the add slot) even when empty; today
  its bottom inset collapses when there are none.
- Touch: tap the add slot; the tile is 40pt tall, so keep the hit target at
  least 44pt by extending it vertically.

## Acceptance criteria

- [ ] No favorites: one dashed "+" tile at the top of the sidebar; tapping it
      favorites the current tab.
- [ ] Six favorites: rows of 4 and 2, with the "+" in the 7th slot.
- [ ] Eight favorites: two full rows, no "+".
- [ ] Narrow sidebar: three per row.
- [ ] VoiceOver label "Add current tab to Favorites" on the slot.

## Open questions

None.
