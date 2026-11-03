# Space gradient themes

| | |
| --- | --- |
| **iOS status** | Not started |
| **Built on desktop** | 2026-11-03, not yet committed |
| **Ticket** | None |

## What you built

Each space used to pick one of 10 accent colors, and the chrome showed a
plain two-color tint of it in light or dark mode. Now each space picks one of
**20 gradient themes**: 10 light and 10 dark. They are soft, atmospheric
gradients with 4 color stops and 2–3 faint radial glows, inspired by Arc.
The theme also decides whether that space's chrome is light or dark,
regardless of the system appearance. Switching spaces cross-fades from one
theme to the next.

## Functionality

- **How to get to it:** the space editor (New Space, or Edit Space from the
  space's menu). The old **Color** row is replaced by **Theme**, with a row
  of 10 light tiles above a row of 10 dark tiles. Each tile previews its
  gradient, its tooltip is the theme's name, and the selected tile has a
  2 pt accent ring. The banner at the top of the editor previews the theme,
  the space's icon, its name, and the theme name on the right.
- **The themes** (picker order):
  - Light: Lavender Blush, Sky Haze, Mint Cream, Peach Glow, Rose Fog,
    Aurora, Iris, Periwinkle, Sand, Citrus.
  - Dark: Midnight Indigo, Forest, Ocean Depths, Plum Night, Burgundy, Slate,
    Teal Drift, Blue Flame, Sunset Dusk, Ember.
- **What it changes:**
  - The gradient fills the whole window behind the sidebar, toolbar and
    page card.
  - **Light or dark:** a light theme gives the sidebar, menus, dialogs,
    command bar and assistant the light look; a dark theme gives the dark
    look. This holds even when the system is in the other mode.
  - **Web pages** still follow the **Theme** setting (System, Light, Dark),
    which now has the description "For web pages. The sidebar, menus and
    assistant follow each space's theme."
  - Each theme has its own accent (selection, focus rings, primary
    buttons), and the small space dots in the sidebar footer and Library use
    that accent.
- **Switching spaces:** the new gradient fades in over the old one in
  320 ms, ease-in-out (instant with Reduce Motion). Text colors switch
  immediately.
- **New spaces** start with the theme after the last space's, in the same
  tone (light stays light, dark stays dark).
- **Existing spaces** saved before themes get one from their old accent:
  Iris → Iris, Ocean → Sky Haze, Lagoon → Aurora, Sage → Mint Cream,
  Citrine → Citrus, Amber → Sand, Coral → Peach Glow, Rose → Rose Fog,
  Plum → Lavender Blush, Graphite → Aurora. All of these are light, so
  nobody's sidebar suddenly goes dark.
- **First run:** Personal is Lavender Blush, Work is Sky Haze.
- Tab group (folder) colors are unchanged and still use the 10 accents.

## Requirements

### Functional

- [ ] 20 themes with the exact names, order and tone above.
- [ ] Each theme is a linear gradient at **162°** (CSS degrees: mostly top
      to bottom, tilted toward the bottom right) with 4 stops, plus 2–3
      radial glows. Exact colors, stop positions and glows are in
      `browser/crates/curio-core/src/gradient.rs` (`SpaceGradient::spec`),
      which is the source of truth. Copy the table from there.
- [ ] Blend stops and glows in **OKLab**, not sRGB, so the middles don't go
      muddy. Glow falloff is Gaussian: `amount = strength * exp(-2 * d² /
      radius²)`, where `d` is measured in window heights with `x` scaled
      by the aspect ratio.
- [ ] Coordinates span the whole window (`x` 0→1 left to right, `y` 0→1
      top to bottom), so the sidebar shows the left fifth of the gradient.
- [ ] Add ±1 level of triangular dither when writing 8-bit pixels, so wide
      ramps don't band.
- [ ] The theme's tone sets the chrome's light or dark look; the Theme
      setting sets web pages only.
- [ ] Contrast across the whole sidebar area of every theme: main text at
      least 7:1, secondary text at least 4.5:1, and selected-row text at
      least 4.5:1 on its raised background. The desktop test
      `text_stays_readable_on_every_gradient` checks this; port it.
- [ ] Cross-fade between spaces as described, and respect Reduce Motion.
- [ ] Migrate old spaces from their accent as listed.

### Data and storage

- Desktop adds a nullable `gradient` column to the `spaces` table
  (migration v2), stored as the snake_case name (e.g. `"midnight_indigo"`).
  It still writes `color` with the closest old accent
  (`SpaceGradient::legacy_accent`) for older builds.
- **iOS** stores spaces as JSON (`Storage/WorkspaceStore.swift`). Add an
  optional `gradient` key with the same snake_case names. When it's
  missing, derive it from `color` using the mapping above. Keep writing
  `color` too.

### Settings

| Setting key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `appearance.theme` (existing) | `system` / `light` / `dark` | `system` | Now applies to web pages only. |

### Commands and shortcuts

None new.

### Permissions, network and AI

None.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-core/src/gradient.rs` | `SpaceGradient` (the 20 themes, names, tone, accent, `next`, `from_accent`, `legacy_accent`), `GradientSpec` (stops and glows), OKLab blending, `sample`, `render_rgba` with dithering. No UI code; port it directly. |
| `browser/crates/curio-ui/src/components/gradient_backdrop.rs` | Paints each theme once into a 480×300 bitmap (96×60 for picker tiles), caches it, and stretches it to fill. |
| `browser/crates/curio-ui/src/theme.rs` | `CurioTheme::new(gradient)`: tokens from the theme, with light or dark taken from its tone. |
| `browser/crates/curio-ui/src/window/mod.rs` | The window backdrop and cross-fade; `apply_theme` splits chrome (space) from web pages (setting). |
| `browser/crates/curio-ui/src/window/dialogs.rs` | The space editor's Theme picker and preview banner. |
| `browser/crates/curio-spaces/src/lib.rs` | `Space.gradient`, `create_space`, `set_space_gradient`. |
| `browser/crates/curio-storage/src/{migrations,database}.rs` | The `gradient` column and migrating old spaces. |

Tests that define the behavior:

- `curio-core/src/gradient.rs`: `twenty_themes_split_evenly_by_tone`,
  `specs_have_three_to_five_ordered_stops`,
  `light_themes_stay_light_and_dark_themes_stay_dark`, `oklab_round_trips`,
  `rendering_is_smooth_with_no_hard_edges`, `next_stays_within_the_tone`,
  `old_accents_map_to_light_themes`, `names_are_stable_for_storage`.
- `curio-ui/src/theme.rs`: `text_stays_readable_on_every_gradient`,
  `tone_sets_the_appearance`.
- `curio-storage/src/database.rs`:
  `space_gradients_round_trip_and_old_spaces_get_one`.

## iOS notes

- **Rendering:** `CAGradientLayer` blends in sRGB and its radial mode has
  hard limits, so it won't match. Port `render_rgba` to Swift (it is plain
  math), draw into a `CGContext` bitmap at about 480×300 (portrait windows:
  swap to 300×480), and show it in a `UIImageView` with `.scaleToFill`.
  Cache one image per theme. This replaces the two-color tint in
  `UI/Components/GradientView.swift`.
- **Light or dark per space:** set `overrideUserInterfaceStyle` on the
  window's chrome (sidebar, bottom bar, sheets the browser presents) from
  the theme's tone, and drive `ThemeCenter` from the space's theme instead
  of the trait collection. Keep the web view's appearance on the Theme
  setting.
- **Narrow layout** (iPhone, folded foldable, Slide Over): the gradient sits
  behind the bottom bar and fills the tabs drawer. Check that the address
  bar and toolbar icons meet the contrast rules on every theme.
- **Wide layout** (iPad, unfolded foldable): matches desktop, with the
  gradient behind the sidebar column and around the page card.
- **Picker** (`UI/Dialogs/SpaceEditorViewController.swift`): two rows of 10
  are tight on iPhone. Use two rows of five per tone (four rows), or a
  horizontally scrolling row per tone, with tiles at least 44 pt tall for
  touch. VoiceOver label: the theme name plus "selected".
- **Rotation and resizing:** the bitmap stretches, so nothing needs
  re-rendering when the size changes.

## Acceptance criteria

- [ ] All 20 themes look the same as on desktop (compare with
      `render_rgba` output for the same size).
- [ ] No visible banding on any theme, including on a large iPad.
- [ ] A dark theme gives that space dark chrome in system light mode, and a
      light theme gives light chrome in system dark mode; web pages follow
      the Theme setting.
- [ ] Switching spaces cross-fades in 320 ms (instant with Reduce Motion).
- [ ] Existing spaces keep a similar look after updating (light themes from
      their old colors).
- [ ] Text contrast passes the ported test on every theme.
- [ ] Works in narrow and wide layouts and when the width changes.
- [ ] Light and dark, Dynamic Type, VoiceOver labels on picker tiles.

## Open questions

- Should a theme also tint the iOS status bar and home indicator area, or
  leave them to the system?
- Desktop doesn't yet offer custom gradients (pick your own colors). If
  that's wanted, do it on both platforms together.
