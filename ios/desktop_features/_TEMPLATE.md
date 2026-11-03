# Feature name

| | |
| --- | --- |
| **iOS status** | Not started / In progress / Built on iOS |
| **Built on desktop** | YYYY-MM-DD, commit or PR link |
| **Ticket** | Linear link, if any |

## What you built

One or two sentences, from the user's point of view: what they can do now that
they couldn't before, and why it's useful.

## Functionality

How the feature behaves, concretely enough to rebuild it without reading the
Rust code.

- **How to get to it:** menu items, shortcuts, buttons, command bar entries,
  context menus, settings.
- **What happens:** step by step, including what the user sees at each step.
- **States:** empty, loading, error, disabled, and what each one shows.
- **Edge cases:** e.g. no tabs, many items, offline, a page that blocks
  scripts, the feature turned off.

## Requirements

### Functional

- [ ] Requirement 1
- [ ] Requirement 2

### Data and storage

New or changed data: fields, types, limits, and how long it's kept. Include
the desktop SQLite migration if there is one (iOS stores the same data as
JSON files in `ios/Curio/Storage`).

### Settings

| Setting key | Type | Default | Meaning |
| --- | --- | --- | --- |
| | | | |

### Commands and shortcuts

| Action name | Default shortcut | Menu |
| --- | --- | --- |
| | | |

Use the exact desktop action names, since users rebind shortcuts by name and
iOS mirrors them in `UI/Commands/CurioCommand.swift`.

### Permissions, network and AI

System permissions, Info.plist keys, network requests, AI prompts or provider
calls, and what data leaves the device. Write "None" if there are none.

## Desktop implementation

Where the Rust code lives, so the iOS developer can read it.

| File | What it does |
| --- | --- |
| `browser/crates/...` | |

Tests that define the behavior: `browser/crates/.../src/...rs` (`test_name`).

## iOS notes

- **Narrow layout** (iPhone, folded foldable, Slide Over): where it lives and
  how it opens (sheet, drawer, bottom bar).
- **Wide layout** (iPad, unfolded foldable): where it lives.
- **Touch instead of hover and right-click:** swipe actions, long press,
  context menus.
- **Hardware keyboard and the iPad menu bar:** shortcuts and menu placement.
- **iOS limits:** anything iOS doesn't allow (other apps' data, arbitrary
  folders, background work) and what to do instead. If part of the feature
  can't be built on iOS, say so and why.
- Suggested place in the Swift code (e.g. `Session/BrowserSession.swift`,
  `UI/Library/`).

## Acceptance criteria

- [ ] Criterion the iOS build can be tested against
- [ ] Works in narrow and wide layouts and when the width changes
- [ ] Light and dark themes, Dynamic Type, VoiceOver labels, Reduce Motion
- [ ] Unit tests ported for the logic (match the Rust tests above)

## Open questions

Anything the desktop work left undecided, or that iOS needs to decide.
