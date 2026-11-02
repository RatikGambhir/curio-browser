# Plan: clipboard history

Status: draft, 2026-10-31. Nothing here is built yet.

Linear: [RAT-39 · Capture macOS clipboard history for later retrieval](https://linear.app/ratik-gambhir/issue/RAT-39/capture-macos-clipboard-history-for-later-retrieval)

> Capture and store clipboard history from the user's macOS machine so it can
> be retrieved later.

## Goals

1. **Capture what the user copies anywhere on the Mac** (not only inside Curio)
   while Curio is running: text, links, images and file references.
2. **Store it locally** in Curio's SQLite database, deduplicated, with a size
   and age limit. Nothing leaves the Mac.
3. **Get it back quickly.** The **Clipboard History** section of the Library
   (it already exists as an empty placeholder) lists and searches items. A
   shortcut (⌥⌘V) opens a quick picker in the command bar. Choosing an item
   puts it back on the clipboard.
4. **Respect privacy.** Skip passwords and anything password managers mark as
   concealed, let the user ignore apps, pause, clear everything, and turn the
   feature off.

## Non-goals (for now)

- Capturing while Curio is quit. macOS keeps no clipboard history, so anything
  copied while Curio isn't running is lost. A login-item helper could fix this
  later (see Follow-ups).
- Syncing history between Macs or to `curio-server`.
- Rich text (RTF/HTML) fidelity. We store the plain-text form; the original
  formatting is not restored.
- Pasting directly into the page or another app. Choosing an item copies it;
  the user presses ⌘V.

## Terms

| Term | Meaning |
|------|---------|
| **Clip** | One stored clipboard item: its kind, content, where it came from and when |
| **Change count** | `NSPasteboard.changeCount`, a number macOS bumps on every copy. Reading it is cheap and reads no content |
| **Watcher** | The code that polls the change count and reads the new content when it changes |
| **Concealed** | Content a password manager (1Password, Bitwarden, Keychain…) marks with `org.nspasteboard.ConcealedType` or similar. Never stored |

---

## 1. How it fits the current code

What's already there:

| Piece | Where | Relevance |
|-------|-------|-----------|
| Library with a **Clipboard History** section, icon, search placeholder and empty state | `curio-ui/src/window/library.rs` (`LibrarySection::ClipboardHistory`, `has_content()` returns `false` for it) | The UI home. We fill in its body |
| Library search helper `matches()` and `library_row()` | same file | Reused for clip rows |
| SQLite with numbered migrations (`PRAGMA user_version`) | `curio-storage/src/migrations.rs` | Add migration v2 |
| `Storage::with` + `cx.background_spawn` pattern | `curio-storage/src/lib.rs`, used across `curio-ui` | All DB work off the UI thread |
| Data dir `~/Library/Application Support/Curio` | `curio-storage/src/paths.rs` | Image files go in `Clipboard/` under it |
| Settings struct with `#[serde(default)]` sections | `curio-settings/src/lib.rs` | Add `ClipboardSettings` |
| Privacy settings page (history toggle, clear buttons) | `curio-ui/src/settings_view.rs::render_privacy` | Add clipboard rows |
| `objc2` / `objc2-app-kit` 0.3 already used for native calls | `curio-browser/src/native.rs`, `curio-app/src/main.rs` | Same approach for `NSPasteboard`. `objc2-app-kit` 0.3.2 has `changeCount`, `types`, `stringForType`, `dataForType` and `accessBehavior` |
| Typed ids via `define_id!` | `curio-core/src/ids.rs` | Add `ClipId` |
| Command bar with modes and async history lookup | `curio-ui/src/command_bar.rs` | Add a `Clipboard` mode |
| `cx.write_to_clipboard(ClipboardItem::…)` | `sidebar.rs`, `commands.rs`, `ai_panel.rs` | How we put a clip back |
| Window maintenance loop (60 s timer) | `curio-ui/src/window/mod.rs` | Pattern for the watcher's poll loop |

Why not just use GPUI's `cx.read_from_clipboard()`? It reads the full content
every time and doesn't expose the change count, the list of types (needed for
the concealed check) or the source app. We use it only to **write** clips back.

### Crate layout

```
curio-core        + clip.rs        Clip, ClipKind, ClipContent, ClipId (pure data, serde)
curio-clipboard   NEW crate        Watcher (macOS NSPasteboard), capture filters, hashing
curio-storage     + clips          Migration v2, Database::{insert_clip, clips, …}
curio-settings    + clipboard      ClipboardSettings
curio-ui          + wiring         ClipboardService global, Library section, command bar mode, settings rows
```

`curio-clipboard` depends only on `curio-core` (+ `objc2*` on macOS). It does not
know about storage or GPUI: it hands captured clips to a callback/channel. That
keeps the platform code testable and keeps `curio-ui` as the only place that
wires things together, the same way `curio-browser` is used today.

---

## 2. Data model (`curio-core/src/clip.rs`)

```rust
define_id!(/// A stored clipboard item.
    ClipId);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClipKind { Text, Url, Image, Files }

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipContent {
    Text(String),
    Url(String),
    /// PNG bytes while capturing; a file path once stored.
    Image { png: Vec<u8>, width: u32, height: u32 },
    Files(Vec<PathBuf>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipSource {
    pub app_bundle_id: Option<String>,   // e.g. "com.apple.Safari"
    pub app_name: Option<String>,
    pub page_url: Option<String>,        // set when copied inside Curio
}

#[derive(Debug, Clone, PartialEq)]
pub struct Clip {
    pub id: ClipId,
    pub kind: ClipKind,
    pub text: Option<String>,        // text, URL, or file paths joined by "\n"
    pub image_path: Option<PathBuf>, // under <data>/Clipboard/<hash>.png
    pub preview: String,             // first ~200 chars, single line, for rows
    pub content_hash: String,        // dedup key (hex of a 64-bit hash or blake3)
    pub byte_len: u64,
    pub source: ClipSource,
    pub pinned: bool,
    pub first_copied_at: Timestamp,
    pub last_copied_at: Timestamp,
    pub copy_count: u32,
}
```

Kind detection order (first match wins): concealed → skip; file URLs →
`Files`; PNG/TIFF → `Image`; a string that parses as an `http(s)` URL (reuse
`url::Url`, trimmed, single line) → `Url`; any string → `Text`.

---

## 3. Capture (`curio-clipboard`)

### Watcher

- A `ClipboardWatcher` polls `NSPasteboard.generalPasteboard().changeCount()`
  every **500 ms** on the main thread (driven by a GPUI timer loop in
  `curio-ui`, like the existing maintenance task). macOS has no "clipboard
  changed" notification; every clipboard manager polls. Reading the change
  count is a single integer read and doesn't trigger any privacy prompt.
- When the count changes:
  1. Read `types()` only. If any type is in the **skip list**, record the new
     count and stop. Reading types doesn't read content.
  2. Otherwise read the content for the chosen kind (`stringForType`,
     `dataForType`, `pasteboardItems` for file URLs).
  3. Record the frontmost app (`NSWorkspace.sharedWorkspace.frontmostApplication`
     bundle id and name) as the source. It's a best guess; macOS doesn't say
     which app wrote to the pasteboard.
  4. Hand a `CapturedClip { content, source, hash }` to the UI through an
     `async_channel` (already a workspace dependency).
- Heavy work (PNG encoding of TIFF data, hashing large images, writing files)
  happens on the background executor, not in the poll tick.

### Skip list (never stored)

| Type | Who sets it |
|------|-------------|
| `org.nspasteboard.ConcealedType` | 1Password, Bitwarden, KeePassXC, most password managers |
| `org.nspasteboard.TransientType` | Content meant to vanish (e.g. one-time codes) |
| `org.nspasteboard.AutoGeneratedType` | Content not copied by the user |
| `com.agilebits.onepassword` | Older 1Password |
| `de.petermaurer.TransientPasteboardType` | Older convention, still used |

Also skipped:

- Copies while the frontmost app's bundle id is in `ignored_apps` (defaults:
  Keychain Access `com.apple.keychainaccess`, Passwords `com.apple.Passwords`,
  1Password `com.1password.1password`, Bitwarden `com.bitwarden.desktop`).
- Empty or whitespace-only text.
- Text over **1 MB** or images over **20 MB** (configurable constants).
- Everything while the user has paused capture or turned the feature off.

### Curio's own writes

When the user picks a clip to copy it back, Curio writes to the clipboard,
which bumps the change count. The dedup hash catches it: the existing clip's
`last_copied_at` and `copy_count` update and it moves to the top. That's the
behaviour we want, so no special "ignore our own write" flag is needed.

When the copy comes from Curio itself (a page, Copy Link, the assistant's copy
button), `source.page_url` is the active tab's URL, so rows can show the page
it came from.

### Universal Clipboard

Content copied on an iPhone shows up with `com.apple.is-remote-clipboard`.
Reading it makes macOS fetch it over the network, which can be slow. Capture
it, but only read its types in the poll tick and fetch the content on the
background executor. Mark it with a small "From iPhone" badge if the type is
present.

### macOS clipboard privacy prompt

Apple announced that macOS will alert the user when an app reads the
clipboard without user action, and added `NSPasteboard.accessBehavior`
(`default`, `ask`, `alwaysAllow`, `alwaysDeny`). As of macOS 26 this is reported
to be off unless a developer flag is set, but it's coming, and it matters for a
clipboard manager.

- Read `types()` first (no prompt), and content only for kinds we keep.
- On macOS versions that have it (check `respondsToSelector:` before calling
  `accessBehavior`, so older systems don't crash), if access is `alwaysDeny`,
  stop polling and show "Curio can't read the clipboard. Allow it in System
  Settings › Privacy & Security › Paste from Other Apps." in the Library
  section.
- Test with the developer flag:
  `defaults write app.curio.browser EnablePasteboardPrivacyDeveloperPreview -bool yes`

### Errors

`curio-clipboard` defines `ClipboardError` with `thiserror` (unreadable
image data, image too large, file write failure). Errors are logged once with
`tracing` (never the clip content itself) and the item is dropped; capture
keeps going.

---

## 4. Storage (`curio-storage`)

### Migration v2

```sql
CREATE TABLE clips (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('text', 'url', 'image', 'files')),
    text TEXT,
    image_path TEXT,
    preview TEXT NOT NULL DEFAULT '',
    content_hash TEXT NOT NULL UNIQUE,
    byte_len INTEGER NOT NULL,
    source_app_bundle TEXT,
    source_app_name TEXT,
    source_url TEXT,
    pinned INTEGER NOT NULL DEFAULT 0,
    first_copied_at INTEGER NOT NULL,
    last_copied_at INTEGER NOT NULL,
    copy_count INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX clips_recent ON clips(pinned DESC, last_copied_at DESC);
```

### `Database` methods

| Method | Notes |
|--------|-------|
| `upsert_clip(&Clip) -> Result<ClipId>` | `INSERT … ON CONFLICT(content_hash) DO UPDATE SET last_copied_at, copy_count = copy_count + 1, source_*`. Returns the existing id on a duplicate |
| `clips(query: &str, limit: usize) -> Result<Vec<Clip>>` | Pinned first, then newest. Search with `LIKE` on `text`, `preview`, `source_app_name`, `source_url`, every word must match (same as history) |
| `set_clip_pinned(ClipId, bool)` | |
| `delete_clip(ClipId) -> Result<Option<PathBuf>>` | Returns the image path so the caller deletes the file |
| `clear_clips(keep_pinned: bool) -> Result<Vec<PathBuf>>` | For "Clear clipboard history" |
| `prune_clips(max_items, older_than: Timestamp) -> Result<Vec<PathBuf>>` | Never prunes pinned clips |

`LIKE` is fine for a few thousand rows. If search gets slow, add an FTS5
table later (the bundled SQLite in `rusqlite` includes FTS5).

### Image files

- Stored at `<data>/Clipboard/<content_hash>.png`. Add `paths::clipboard_dir()`.
- Written before the row is inserted; if the insert fails, the file is removed.
- Deleted when the row is deleted or pruned. On startup, a cleanup pass removes
  files with no row (crash leftovers).

---

## 5. Settings (`curio-settings`)

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ClipboardSettings {
    pub enabled: bool,          // default: false (opt-in, see Open questions)
    pub capture_images: bool,   // default: true
    pub max_items: usize,       // default: 1000, sanitized to 50..=10_000
    pub keep_days: u32,         // default: 30; 0 = forever
    pub ignored_apps: Vec<String>, // bundle ids; defaults listed in section 3
}
```

Add `pub clipboard: ClipboardSettings` to `Settings`, and clamp values in
`Settings::sanitized()`.

---

## 6. UI (`curio-ui`)

### `ClipboardService` (new `clipboard.rs`)

A GPUI global, set up in `curio_ui::init` so there's one watcher for the app
(not one per window):

- Owns the watcher and the poll task. Starts or stops when
  `settings.clipboard.enabled` changes (`cx.observe_global::<SettingsStore>`).
- Receives `CapturedClip`s, fills in `source.page_url` if Curio was frontmost,
  then on the background executor writes the image file and calls
  `upsert_clip`.
- Runs `prune_clips` once on startup and then hourly.
- Holds a `paused_until: Option<Instant>` for "Pause for 1 hour".
- Bumps a `generation: u64` after each stored clip so open views know to
  reload.

### Library › Clipboard History

In `library.rs`:

- `has_content()` returns `true` for `ClipboardHistory`.
- `Library` gets `clips: Vec<Clip>`, loaded the same way as downloads
  (`reload_library_clips`, called on open, on section change, when the search
  changes and when `ClipboardService.generation` changes).
- `render_library_clipboard(query, theme, cx)`:
  - Grouped under **Pinned**, **Today**, **Yesterday**, **Earlier** headers.
  - Each row uses `library_row`: icon by kind (text, link favicon, image
    thumbnail via `img(path)`, file icon), the preview as title, and
    "App name · 3 min ago" as subtitle.
  - Click: copy back to the clipboard and show a "Copied" notification.
  - URL rows: a second button to open the link in a new tab.
  - Hover buttons: Pin/Unpin and Delete.
  - Right-click menu: Copy, Open link, Pin, Delete, "Don't save from <App>"
    (adds it to `ignored_apps`).
- Empty states:
  - Feature off: "Clipboard history is off" with a **Turn On** button.
  - On, nothing yet: today's "Nothing copied yet" copy.
  - Access denied by macOS: the message from section 3.

### Quick picker (⌥⌘V)

- New action `ShowClipboardHistory`, bound to `alt-secondary-v` (⇧⌘V is left
  alone because pages use it for "Paste and Match Style"). Also in the Edit
  menu and the command palette list.
- Opens the command bar in a new `CommandMode::Clipboard`: the input searches
  clips, rows show previews, Enter copies the selected clip and closes the bar,
  ⌘Enter opens a URL clip in a new tab. Lookup uses the same generation-checked
  async pattern as `CommandBar::refresh`.

### Settings › Privacy

Add rows to `render_privacy`:

- **Save clipboard history** switch, with "Keeps text, links and images you
  copy on this Mac. Passwords from password managers are never saved."
- **Keep items for**: 1 day / 7 days / 30 days / Forever.
- **Save images** switch.
- **Ignored apps**: list with remove buttons (adding happens from the
  right-click menu).
- **Clear clipboard history** danger button (keeps pinned items; a confirm
  dialog offers "Also remove pinned").

---

## 7. Work breakdown

Each step builds and passes tests on its own.

| # | Step | Files | Done when |
|---|------|-------|-----------|
| 1 | Data model and settings | `curio-core/src/clip.rs`, `ids.rs`, `lib.rs`; `curio-settings/src/lib.rs` | Types compile, serde round-trip and sanitizer tests pass |
| 2 | Storage | `curio-storage/src/migrations.rs`, `database.rs`, `paths.rs`, `lib.rs` | v1 → v2 migration test, upsert/dedup, search, prune (pinned survive), clear tests pass |
| 3 | `curio-clipboard` crate: filters + kind detection + hashing (platform-free) | `crates/curio-clipboard/{Cargo.toml,src/lib.rs,src/filter.rs}` | Unit tests for skip list, size caps, URL vs text detection, dedup hashing |
| 4 | macOS watcher | `curio-clipboard/src/macos.rs` (`objc2-app-kit` features `NSPasteboard`, `NSPasteboardItem`, `NSWorkspace`, `NSRunningApplication`) | Manual test: copying in other apps produces `CapturedClip`s; 1Password copy is skipped |
| 5 | `ClipboardService` + wiring | `curio-ui/src/clipboard.rs`, `lib.rs` (`init`) | Copies land in the DB while Curio runs; turning the setting off stops polling |
| 6 | Library section | `curio-ui/src/window/library.rs` | List, search, copy back, pin, delete, open link, empty states all work |
| 7 | Quick picker + action + menu | `curio-ui/src/actions.rs`, `command_bar.rs`, `window/commands.rs` | ⌥⌘V opens the picker; Enter copies |
| 8 | Privacy settings | `curio-ui/src/settings_view.rs` | All rows work; clear removes rows and image files |
| 9 | README features list | `README.md` | Feature documented |

Steps 1–3 are independent of each other's code beyond the shared types and
could be done in parallel once step 1 lands.

## 8. Testing

- **Unit** (`#[cfg(test)]` modules, `use super::*`):
  - `curio-clipboard`: classify `["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]` → skipped; `"https://x.com  "` → `Url`; `"see https://x.com"` → `Text`; 2 MB string → skipped; same content → same hash.
  - `curio-storage`: in-memory DB like the existing tests; duplicate upsert bumps `copy_count` and keeps one row; prune keeps pinned and returns image paths; search requires every word.
  - `curio-settings`: missing `clipboard` key loads defaults; out-of-range `max_items` is clamped.
- **Platform code** stays thin: `macos.rs` only reads pasteboard values into
  plain Rust types, and the logic on those types is what's unit tested.
- **Manual checklist** (macOS):
  1. Copy text in Notes, a link in Safari, an image in Preview, a file in Finder → all four appear with the right icon and source app.
  2. Copy a password from 1Password and from Passwords → nothing stored.
  3. Copy the same text twice → one row, moved to the top.
  4. Pick a clip, ⌘V into TextEdit → pasted.
  5. Turn the setting off → no new rows; turn on → resumes.
  6. Quit and relaunch → history still there; image thumbnails load.
  7. With `EnablePasteboardPrivacyDeveloperPreview` on: no alerts from polling
     alone; check what happens on first content read and that the denied state
     shows its message.
- `cargo clippy --workspace` clean under the workspace lints (`unwrap_used`,
  `undocumented_unsafe_blocks`: every `unsafe` objc call gets a `// SAFETY:`
  comment, as in `native.rs`).

## 9. Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | macOS clipboard privacy alert becomes default and nags users on every read | Read types before content; detect `accessBehavior`; document the System Settings switch in the empty state. Re-check on each macOS beta |
| R2 | Storing something sensitive the password manager didn't mark | Ignored-apps list with sensible defaults, "Don't save from this app" in one click, pause, opt-in by default, local-only storage |
| R3 | Polling cost | 500 ms integer read is negligible. Content is only read on change. Stop the loop entirely when disabled |
| R4 | Big images bloat the data folder | 20 MB cap per image, `capture_images` toggle, pruning by count and age |
| R5 | Source app is wrong (e.g. a background app writes the clipboard) | Label it as a hint only; never use it for security decisions |
| R6 | Capturing stops when Curio quits, so users expect more than it does | Say so in the setting's description: "while Curio is open" |

## 10. Open questions

1. **On by default or opt-in?** Recommendation: opt-in, with a **Turn On**
   button in the Library empty state. A browser silently recording the
   system-wide clipboard would surprise people.
2. **Shortcut**: ⌥⌘V inside Curio only, or a global hotkey that works from
   any app? Global needs a registered hotkey (Carbon `RegisterEventHotKey`)
   and bringing Curio forward; suggest Curio-only first.
3. **Retention defaults**: 1000 items / 30 days OK?
4. Should the assistant be able to use clipboard items as context (an
   "Attach from clipboard" chip)? Easy to add after this lands.

## 11. Follow-ups

- Login-item helper (`SMAppService`) so capture continues while Curio is
  closed.
- FTS5 search if history grows large.
- Assistant context: attach a clip, or "summarize what I copied today".
- Rich text: keep RTF/HTML alongside plain text and restore it on copy back.
- Sync clips across a user's Macs through `curio-server` once accounts exist
  (see `profiles-accounts-integrations.md`), end-to-end encrypted.
