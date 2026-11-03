# AGENTS.md: Curio desktop (`browser/`)

Instructions for AI coding agents working in `browser/`, the Rust + GPUI
desktop app. Curio also has a native Swift/UIKit port for iPhone and iPad in
[`../ios`](../ios). **If you build a feature here that the iOS app doesn't
have, you must write it up for the iOS team** (see
[iOS parity](#ios-parity-required)).

## Build, test, lint

Run from `browser/`:

```bash
cargo run --release                           # run the app
cargo test --workspace --exclude curio-app    # unit tests (no window needed)
cargo clippy --workspace --all-targets        # must be warning-free
cargo fmt --all
script/bundle-macos.sh                        # standalone app in dist/Curio.app
```

- `CURIO_DATA_DIR=/tmp/curio-dev` uses a throwaway data directory, so testing
  doesn't touch the real session.
- `RUST_LOG=debug` turns on verbose logs.
- Before you call a task done, run `cargo fmt`, `cargo clippy` and the tests.

## Crate map

| Crate | What it owns | UI deps? |
| --- | --- | --- |
| `curio-core` | Typed IDs, tab/group/favorite and chat records, accent palette, omnibox input classification | No |
| `curio-tabs` | One space's tab strip: pinned and regular sections, folders, drag and drop placement | No |
| `curio-spaces` | The `Workspace`: spaces, favorites, active tabs, closed-tab stack | No |
| `curio-settings` | Preferences (serde, forward-compatible defaults) | No |
| `curio-storage` | SQLite persistence and migrations | No |
| `curio-ai` | Provider wire formats, SSE streaming, page-context prompts, secrets | No |
| `curio-browser` | WebKit tabs: webview lifecycle and sleep, page bridge, scripts, find, downloads | Engine |
| `curio-ui` | Everything drawn with GPUI: window, sidebar, tab strip, command bar, AI panel, settings, dialogs, theme | Yes |
| `curio-app` | Startup, session restore, menus, window | Yes |

Put logic in the lowest crate that can hold it. The organization crates
(`core`, `tabs`, `spaces`, `settings`, `storage`, `ai`) must not depend on
GPUI or the engine, and every behavior in them gets a unit test. These crates
are what the iOS app ports one-to-one into Swift (`ios/Curio/Core`, `AI`,
`Storage`), so keep them plain and well tested.

## GPUI skills

GPUI skills are installed globally. Load the right one **before** writing
GPUI code instead of guessing at APIs:

| Task | Skill |
| --- | --- |
| Contexts, windows, render model, how GPUI fits together | `gpui-fundamentals` |
| View state, `Entity`/`WeakEntity`, `cx.notify()`, subscriptions, observers | `gpui-entities` |
| Building element trees, custom `RenderOnce` components, conditional rendering | `gpui-elements` |
| Layout, flexbox, spacing, colors | `gpui-styling` |
| `actions!`, key bindings, menus, mouse and keyboard events | `gpui-actions` |
| `cx.spawn`, `background_spawn`, tasks, channels from engine or AI threads | `gpui-async` |
| Modals, lists, forms, dropdowns, shared state | `gpui-patterns` |
| `#[gpui::test]`, `TestAppContext`, simulated input | `gpui-testing` |
| Borrow panics ("already mutably borrowed"), lifetime errors, odd rendering | `gpui-troubleshooting` |
| Reviewing or refactoring GPUI code | `gpui-code-quality` |
| General Rust (ownership, errors, API design) | `rust-skills` |

**Curio uses GPUI through GPUI Kit, not the `gpui` crate directly.**

- Import from `gpui_kit::` (e.g. `use gpui_kit::{App, Window, Entity, px}`)
  where the skills write `gpui::`. Webviews come from `gpui_webview`.
- The workspace pins `gpui-kit` 0.8.1 with the `gpui-fast` backend, which
  composites native WebKit views under GPUI overlays. If a skill's example
  doesn't compile, the pinned GPUI Kit API wins. Check the crate source in
  `~/.cargo/registry` or how existing Curio code does it.
- `gpui-init` is for new projects. Don't scaffold anything here; the app
  already exists.

## Project conventions

- **Components first.** Build views from `curio-ui/src/components` (e.g.
  `IconButton`, `ListItem`, `SearchField`, `SettingRow`) instead of
  styling raw `div`s. New reusable pieces go there as `RenderOnce` builder
  structs that implement `Styled`. Read `components/mod.rs` for the rules.
- **Colors come from the theme.** Use tokens from the global `CurioTheme`
  (`theme.rs`), never hard-coded colors. The chrome follows the active
  space's accent and light/dark mode.
- **Commands are actions.** Every user command is an action in
  `curio-ui/src/actions.rs` with a default shortcut and a menu item. Users can
  rebind shortcuts by action name, so don't rename existing actions.
  Shortcuts that must work while a page has focus belong in
  `forwarded_keystrokes`.
- **Settings** go in `curio-settings` with a serde default, so old settings
  files keep loading. The iOS app uses the same setting and keybinding names.
- **Storage changes** are new migrations in `curio-storage/src/migrations.rs`.
  Never edit a migration that has already shipped.
- **Errors:** no `unwrap()` or `expect()` outside tests (clippy warns). Use
  `anyhow`/`thiserror` and `?`, and log with `tracing` at the boundary.
- **Async:** do blocking or network work off the main thread (`curio-ai`
  streams on background threads) and return to the UI with `cx.spawn` +
  `this.update(...)`. Call `cx.notify()` after any state change that affects
  rendering. Detach or store tasks; a dropped task is cancelled.
- **Entities:** never update an entity from inside its own `update` closure;
  that panics with "already mutably borrowed". Hold back-references as
  `WeakEntity`.
- **Docs:** if a change affects users, update the Features, Keyboard shortcuts
  or Known limitations section of the root `README.md`.

## iOS parity (required)

The iOS app (`../ios`) aims to have every desktop feature, adapted for touch.
Whenever you **add a user-facing feature or change behavior here that the iOS
app doesn't have yet**, write a spec for it in
[`../ios/desktop_features/`](../ios/desktop_features). The iOS team builds the
Swift version from that spec.

### Does this need a spec?

Write one for anything a user could notice: a new command, shortcut, view,
setting, Library section, assistant capability, storage of new data, or a
change to how an existing feature behaves.

You don't need one for refactors, performance work with no visible change,
desktop-only plumbing (bundling, macOS signing), or fixes to bugs the iOS app
doesn't have.

To check whether iOS already has the feature:

1. Read the Features list in [`../ios/README.md`](../ios/README.md).
2. Search the Swift code, e.g. `grep -rni "<feature keyword>" ../ios/Curio`.
   Ported pieces usually share names (`Workspace` and `WorkspaceStore`,
   `omnibox` and `OmniboxTests`, the same action names in
   `ios/Curio/UI/Commands/CurioCommand.swift`).
3. Check whether `../ios/desktop_features/` already has a spec for it. If it
   does, update that file instead of making a new one.

If you're not sure, write the spec. A spec that turns out to be unneeded
costs little; a missing feature on iOS costs more.

### How to write the spec

1. Copy [`../ios/desktop_features/_TEMPLATE.md`](../ios/desktop_features/_TEMPLATE.md)
   to `../ios/desktop_features/<feature-name>.md`, in lowercase kebab case
   (e.g. `tab-audio-mute.md`).
2. Fill in every section:
   - **What you built:** the feature in a sentence or two, from the user's
     point of view.
   - **Functionality:** exactly how it behaves: entry points (menu,
     shortcut, button, command bar), each state, and edge cases.
   - **Requirements:** the functional requirements, data and storage
     (schema or migration), settings and their names, action names and
     default shortcuts, permissions, and network or AI calls.
   - **Desktop implementation:** the files, types and tests that implement
     it, so the iOS developer can read the Rust code.
   - **iOS notes:** what will differ on iPhone and iPad (touch instead of
     hover, narrow vs. wide layout, sheets vs. panels, Files app vs. any
     folder, APIs iOS doesn't allow). If part of it can't be built on iOS,
     say so and why.
   - **Acceptance criteria:** a checklist the iOS build can be tested
     against.
3. Write it for a Swift developer who won't read the whole Rust diff:
   concrete behavior and values, not "same as desktop".
4. Write the spec in the same change as the feature, and keep it up to date
   if the feature changes before it ships.
5. Mention the spec's path in your final summary to the user.

Don't change the Swift code in `../ios` as part of desktop work unless the
user asks you to. The spec is the hand-off.
