# Media from the user's folders

| | |
| --- | --- |
| **iOS status** | Not started |
| **Built on desktop** | 2026-11-03, not yet committed |
| **Ticket** | None |

## What you built

The Library's **Media** section used to show only images and videos the user
downloaded in Curio. It now shows every image and video in the user's own
folders: Desktop, Documents, Downloads, Pictures, Movies, and loose files in
the home folder. Downloads saved anywhere else still appear. Media becomes a
browsable gallery of the user's own files, not just a download log.

## Functionality

- **How to get to it:** open the Library (sidebar library button or the
  `ToggleLibrary` action) and choose **Media** in the rail. Nothing else
  changed about getting there.
- **What happens:**
  1. When Media is shown (the library opens with Media selected, or the user
     switches to Media), Curio scans the folders on a background thread.
     It scans again each time, so new files appear without a restart, but
     never starts a second scan while one is running.
  2. While the first scan runs and nothing has been found yet, the pane shows
     "Looking for images and videos…".
  3. Results appear as a grid of **two tiles per row**, newest first (by file
     modification time). Each tile shows a 96 pt preview (cover-cropped,
     10 pt corners), the file name, and on a second line the folder it was
     found in ("Desktop", "Pictures", "Home", ...).
  4. Image previews load in the background as small thumbnails (longest
     side 320 px), upright according to the photo's orientation flag.
     Videos, HEIC and SVG files, files over 80 MB, and files that fail to
     decode show a film or photo icon instead.
  5. Clicking a tile shows the file in Finder. The tooltip is "Show in Finder".
- **Search:** the search field filters by file name **and** folder label;
  every word must match (so "desktop png" works). With no match the pane shows
  "No results / Nothing in Media matches “…”".
- **States:**
  - Scanning with nothing found yet: "Looking for images and videos…".
  - Nothing found: "No media yet. Images and videos in your Desktop,
    Documents, Downloads, Pictures and Movies folders show up here. If some
    are missing, allow Curio in System Settings › Privacy & Security ›
    Files & Folders."
  - Thumbnail still loading: the empty tile background.
- **Edge cases:**
  - macOS asks for permission for Desktop, Documents and Downloads the first
    time. If the user says no, those folders are silently skipped, and the
    others still show.
  - Thousands of files: only the rows on screen are built, and at most 120
    thumbnails stay in memory. All thumbnails are freed when the library
    closes.
  - The same file found twice (scanned and also a download record) shows
    once.

## Requirements

### Functional

- [ ] Find images and videos in the user's folders, newest first.
- [ ] Recognized extensions (case-insensitive). Images: `png jpg jpeg gif
      webp heic heif svg bmp tiff`. Videos: `mp4 mov m4v webm mkv avi`.
- [ ] Skip hidden files and folders (names starting with `.`) and symlinks.
- [ ] Skip folders that aren't the user's media: `node_modules`, `target`,
      `build`, `dist`, `DerivedData`, `Pods`, `vendor`, `__pycache__`,
      `venv`, and packages by extension: `app appex bundle framework plugin
      kext photoslibrary photolibrary musiclibrary tvlibrary imovielibrary
      fcpbundle logicx xcodeproj xcworkspace xcassets pages numbers key rtfd`.
- [ ] Skip empty (0-byte) files.
- [ ] Limits: 6 folders deep below each root, stop after visiting 60,000
      entries, keep the newest 5,000 files.
- [ ] Include completed downloads saved outside the scanned folders, labeled
      "Downloads". Never list a file twice.
- [ ] Search matches file name and folder label, every word.
- [ ] Thumbnails are decoded off the main thread, at most 3 at a time,
      newest request first, with at most 48 waiting (older requests dropped
      and re-requested if they scroll back into view). Keep at most 120 in
      memory, least recently used first out. Free them when the library
      closes.
- [ ] The grid only builds the rows in view.

### Data and storage

Nothing is stored. The list is rebuilt from disk each time Media is shown, and
thumbnails live only in memory. Download records are read from the existing
downloads store (the 200 most recent).

### Settings

None.

### Commands and shortcuts

None new. Media is still opened with the existing `ToggleLibrary` action.

### Permissions, network and AI

- macOS: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`
  and `NSDownloadsFolderUsageDescription` added to the app bundle's Info.plist
  (`browser/script/bundle-macos.sh`).
- No network or AI calls. Nothing leaves the device.

## Desktop implementation

| File | What it does |
| --- | --- |
| `browser/crates/curio-storage/src/media.rs` | The scanner: `MediaKind`, `MediaFile`, `MediaRoot`, `default_roots`, `ScanLimits`, `scan`, `scan_home`. No UI code; port it directly. |
| `browser/crates/curio-ui/src/window/thumbnails.rs` | `MediaThumbnails`: background decoding, the LRU cache, request queue limits. |
| `browser/crates/curio-ui/src/window/library.rs` | `reload_library_media` (when to scan), `render_library_media` (the grid with `uniform_list`), `media_tile`, the empty-state copy. |
| `browser/script/bundle-macos.sh` | Folder-access messages in Info.plist. |

Tests that define the behavior:

- `curio-storage/src/media.rs`: `kind_comes_from_the_extension`,
  `finds_media_in_the_user_folders_newest_first`,
  `skips_hidden_folders_packages_and_build_output`,
  `respects_the_depth_and_file_limits`, `adds_extra_files_once`,
  `unreadable_roots_are_skipped`.
- `curio-ui/src/window/thumbnails.rs`: `only_supported_formats_are_decoded`,
  `thumbnails_are_small_and_bgra`, `missing_or_broken_files_give_no_thumbnail`.

## iOS notes

iOS can't read the user's Desktop, Documents or home folder, so the desktop
behavior can't be copied directly. The closest matches, in suggested order:

1. **Photos library (recommended main source).** On iPhone and iPad the
   user's images and videos live in Photos. Read them with PhotoKit
   (`PHAsset.fetchAssets`, newest first by `creationDate`) and load
   thumbnails with `PHCachingImageManager`, which also handles HEIC and video
   frames, so iOS can show real previews where desktop shows icons. Needs
   `NSPhotoLibraryUsageDescription` (read access; the app only has
   `NSPhotoLibraryAddUsageDescription` today). Support **limited access**
   (iOS 14+), and show a button to change the selection
   (`PHPhotoLibrary.shared().presentLimitedLibraryPicker`).
2. **Curio's own folder in Files** (`Documents/Downloads` and the rest of
   the app's Documents, visible in Files › Curio): scan it with the same
   rules as `media.rs`. This covers downloads, as today.
3. **Folders the user picks (optional).** A "Add Folder…" button using
   `UIDocumentPickerViewController` for folders, kept with security-scoped
   bookmarks. That is the iOS equivalent of "my Desktop folder" and works
   with iCloud Drive, where Mac Desktop and Documents may be synced.

Other notes:

- **Folder label:** use "Photos" for Photos assets, "Downloads" for
  downloads, and the picked folder's name for added folders, so search by
  folder still works.
- **Tapping a tile:** there is no Finder. Keep the current
  `libraryPreview(url)` (Quick Look) for files; for Photos assets, open a
  Quick Look-style preview of the asset. Long press for a context menu
  (Share, Save to Files, Copy).
- **Narrow layout** (iPhone, folded foldable, Slide Over): the library is a
  sheet. Keep two columns. **Wide layout** (iPad, unfolded foldable): the
  library column. Consider three columns when the column is wider than
  about 420 pt.
- **Rows in view only:** `LibraryViewController.mediaRows` builds a
  `UIStackView` for every tile up front. Switch Media to a
  `UICollectionView` (compositional layout, two columns) so thousands of
  items stay fast, and cancel thumbnail requests for cells that scroll away.
- **Memory:** `MediaTileView` decodes with `UIImage(contentsOfFile:)` then
  `preparingThumbnail`, which reads the full image first. For files use
  `CGImageSourceCreateThumbnailAtIndex` with
  `kCGImageSourceThumbnailMaxPixelSize` of 320 and
  `kCGImageSourceCreateThumbnailWithTransform`, and cache with `NSCache`
  (about 120 items).
- Suggested places: a `MediaLibrary` model under `Storage/` (scanning and
  Photos fetch, ported from `media.rs`), the grid in `UI/Library/`.

## Acceptance criteria

- [ ] Media shows images and videos from the Photos library and Curio's
      Files folder (plus any picked folders, if built), newest first.
- [ ] With full, limited and denied Photos access, Media still works and
      explains how to grant access when it's denied.
- [ ] Hidden files, packages and build folders are skipped in scanned
      folders, matching `media.rs`.
- [ ] Search by file name and folder label, every word.
- [ ] Scrolling through 5,000 items stays smooth; memory stays flat.
- [ ] Previews are upright, and videos and HEIC show real thumbnails.
- [ ] Tapping opens a preview; long press offers Share and Save.
- [ ] Works in narrow and wide layouts and when the width changes.
- [ ] Light and dark themes, Dynamic Type, VoiceOver labels (file name and
      folder), Reduce Motion.
- [ ] Unit tests ported for the scan rules (the six `media.rs` tests).

## Open questions

- Should the Photos library be the main source on iOS, or should Media stay
  files-only with a separate Photos section? (Recommendation: include
  Photos; it is where iOS users' media is.)
- Build "Add Folder…" now, or later?
- Desktop decodes previews only for `png jpg gif webp bmp tiff`. A follow-up
  could use macOS Quick Look thumbnails to give HEIC and video previews
  there too.
