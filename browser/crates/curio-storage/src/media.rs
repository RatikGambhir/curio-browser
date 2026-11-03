//! Finds images and videos in the user's own folders for the Library's Media
//! section: Desktop, Documents, Downloads, Pictures, Movies, and loose files
//! in the home folder.
//!
//! The scan is bounded (depth, entries visited, files kept) so it stays fast
//! on large home folders, and it skips places that hold app data rather than
//! the user's own media: hidden folders, packages such as `.app` or
//! `.photoslibrary`, and build or dependency folders.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// File extensions treated as images.
pub const IMAGE_EXTENSIONS: [&str; 10] = [
    "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "bmp", "tiff",
];

/// File extensions treated as videos.
pub const VIDEO_EXTENSIONS: [&str; 6] = ["mp4", "mov", "m4v", "webm", "mkv", "avi"];

/// Folders that hold code, builds or dependencies, not the user's media.
const SKIPPED_DIRS: [&str; 9] = [
    "node_modules",
    "target",
    "build",
    "dist",
    "DerivedData",
    "Pods",
    "vendor",
    "__pycache__",
    "venv",
];

/// Folder extensions macOS shows as a single file (packages and libraries).
const PACKAGE_EXTENSIONS: [&str; 20] = [
    "app",
    "appex",
    "bundle",
    "framework",
    "plugin",
    "kext",
    "photoslibrary",
    "photolibrary",
    "musiclibrary",
    "tvlibrary",
    "imovielibrary",
    "fcpbundle",
    "logicx",
    "xcodeproj",
    "xcworkspace",
    "xcassets",
    "pages",
    "numbers",
    "key",
    "rtfd",
];

/// Whether a file is an image or a video.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKind {
    Image,
    Video,
}

impl MediaKind {
    /// The kind for a path, from its extension (case-insensitive).
    #[must_use]
    pub fn from_path(path: &Path) -> Option<Self> {
        let ext = path.extension()?.to_string_lossy().to_lowercase();
        if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
            Some(Self::Image)
        } else if VIDEO_EXTENSIONS.contains(&ext.as_str()) {
            Some(Self::Video)
        } else {
            None
        }
    }
}

/// One image or video found on disk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaFile {
    pub path: PathBuf,
    /// The file name, for display and search.
    pub name: String,
    /// The folder it was found under, such as "Desktop" or "Downloads".
    pub folder: String,
    pub kind: MediaKind,
    pub modified: SystemTime,
}

/// A folder to look in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaRoot {
    /// Shown on each file found under it.
    pub label: String,
    pub path: PathBuf,
    /// Whether to look inside subfolders, or only at files directly in it.
    pub recursive: bool,
}

impl MediaRoot {
    fn new(label: &str, path: PathBuf, recursive: bool) -> Self {
        Self {
            label: label.to_owned(),
            path,
            recursive,
        }
    }
}

/// The folders Media looks in, under `home`. The home folder itself is only
/// checked for loose files; its subfolders are covered by the other roots.
#[must_use]
pub fn default_roots(home: &Path) -> Vec<MediaRoot> {
    vec![
        MediaRoot::new("Desktop", home.join("Desktop"), true),
        MediaRoot::new("Downloads", home.join("Downloads"), true),
        MediaRoot::new("Pictures", home.join("Pictures"), true),
        MediaRoot::new("Movies", home.join("Movies"), true),
        MediaRoot::new("Documents", home.join("Documents"), true),
        MediaRoot::new("Home", home.to_path_buf(), false),
    ]
}

/// Bounds that keep a scan fast on large folders.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ScanLimits {
    /// How many folders deep to look below each root.
    pub max_depth: usize,
    /// Stop after visiting this many directory entries in total.
    pub max_entries: usize,
    /// Keep only this many files, newest first.
    pub max_files: usize,
}

impl Default for ScanLimits {
    fn default() -> Self {
        Self {
            max_depth: 6,
            max_entries: 60_000,
            max_files: 5_000,
        }
    }
}

/// Finds images and videos under `roots`, plus any `extra` files (such as
/// downloads saved outside those folders), newest first.
///
/// Folders that can't be read, for example because macOS privacy settings
/// deny access to Desktop or Documents, are skipped.
#[must_use]
pub fn scan(
    roots: &[MediaRoot],
    extra: impl IntoIterator<Item = (PathBuf, String)>,
    limits: ScanLimits,
) -> Vec<MediaFile> {
    let mut found = Vec::new();
    let mut seen = HashSet::new();
    let mut visited = 0usize;

    'roots: for root in roots {
        let mut stack = vec![(root.path.clone(), 0usize)];
        while let Some((dir, depth)) = stack.pop() {
            let entries = match fs::read_dir(&dir) {
                Ok(entries) => entries,
                Err(error) => {
                    tracing::debug!(dir = %dir.display(), %error, "skipping unreadable folder");
                    continue;
                }
            };
            for entry in entries.flatten() {
                visited += 1;
                if visited > limits.max_entries {
                    tracing::debug!("media scan stopped at the entry limit");
                    break 'roots;
                }
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') {
                    continue;
                }
                // `file_type` doesn't follow symlinks, so links are skipped
                // and can't send the scan in a loop.
                let Ok(file_type) = entry.file_type() else {
                    continue;
                };
                let path = entry.path();
                if file_type.is_dir() {
                    if root.recursive && depth < limits.max_depth && !skips_dir(&name) {
                        stack.push((path, depth + 1));
                    }
                } else if file_type.is_file() {
                    push_file(&mut found, &mut seen, path, name, &root.label);
                }
            }
        }
    }

    for (path, folder) in extra {
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        push_file(&mut found, &mut seen, path, name, &folder);
    }

    found.sort_by(|a, b| {
        b.modified
            .cmp(&a.modified)
            .then_with(|| a.name.cmp(&b.name))
    });
    found.truncate(limits.max_files);
    found
}

/// [`scan`] of the current user's [`default_roots`] with default limits.
/// Empty when the home folder is unknown.
#[must_use]
pub fn scan_home(extra: impl IntoIterator<Item = (PathBuf, String)>) -> Vec<MediaFile> {
    dirs::home_dir().map_or_else(Vec::new, |home| {
        scan(&default_roots(&home), extra, ScanLimits::default())
    })
}

fn push_file(
    found: &mut Vec<MediaFile>,
    seen: &mut HashSet<PathBuf>,
    path: PathBuf,
    name: String,
    folder: &str,
) {
    let Some(kind) = MediaKind::from_path(&path) else {
        return;
    };
    if seen.contains(&path) {
        return;
    }
    let Ok(metadata) = fs::metadata(&path) else {
        return;
    };
    if !metadata.is_file() || metadata.len() == 0 {
        return;
    }
    seen.insert(path.clone());
    found.push(MediaFile {
        path,
        name,
        folder: folder.to_owned(),
        kind,
        modified: metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH),
    });
}

fn skips_dir(name: &str) -> bool {
    if SKIPPED_DIRS.contains(&name) {
        return true;
    }
    Path::new(name).extension().is_some_and(|ext| {
        let ext = ext.to_string_lossy().to_lowercase();
        PACKAGE_EXTENSIONS.contains(&ext.as_str())
    })
}

#[cfg(test)]
mod tests {
    use std::fs::File;
    use std::time::Duration;

    use super::*;

    fn touch(path: &Path, age_secs: u64) {
        fs::create_dir_all(path.parent().expect("has parent")).expect("create dirs");
        fs::write(path, b"data").expect("write file");
        let modified = SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000 - age_secs);
        File::options()
            .write(true)
            .open(path)
            .expect("open file")
            .set_modified(modified)
            .expect("set modified time");
    }

    fn names(files: &[MediaFile]) -> Vec<&str> {
        files.iter().map(|f| f.name.as_str()).collect()
    }

    #[test]
    fn kind_comes_from_the_extension() {
        assert_eq!(
            MediaKind::from_path(Path::new("/a/Photo.JPG")),
            Some(MediaKind::Image)
        );
        assert_eq!(
            MediaKind::from_path(Path::new("/a/clip.mov")),
            Some(MediaKind::Video)
        );
        assert_eq!(MediaKind::from_path(Path::new("/a/notes.txt")), None);
        assert_eq!(MediaKind::from_path(Path::new("/a/README")), None);
    }

    #[test]
    fn finds_media_in_the_user_folders_newest_first() {
        let home = tempfile::tempdir().expect("temp dir");
        let home = home.path();
        touch(&home.join("Desktop/screenshot.png"), 10);
        touch(&home.join("Downloads/clip.mp4"), 30);
        touch(&home.join("Pictures/Trips/2026/beach.jpg"), 20);
        touch(&home.join("Documents/notes.txt"), 5);
        touch(&home.join("loose.gif"), 40);

        let files = scan(&default_roots(home), [], ScanLimits::default());

        assert_eq!(
            names(&files),
            ["screenshot.png", "beach.jpg", "clip.mp4", "loose.gif"]
        );
        let folders: Vec<&str> = files.iter().map(|f| f.folder.as_str()).collect();
        assert_eq!(folders, ["Desktop", "Pictures", "Downloads", "Home"]);
        assert_eq!(files[2].kind, MediaKind::Video);
    }

    #[test]
    fn skips_hidden_folders_packages_and_build_output() {
        let home = tempfile::tempdir().expect("temp dir");
        let home = home.path();
        touch(&home.join("Desktop/keep.png"), 1);
        touch(&home.join("Desktop/.hidden.png"), 1);
        touch(&home.join("Desktop/.cache/inside.png"), 1);
        touch(&home.join("Desktop/Tool.app/Contents/icon.png"), 1);
        touch(
            &home.join("Pictures/Photos Library.photoslibrary/originals/a.heic"),
            1,
        );
        touch(&home.join("Documents/site/node_modules/pkg/logo.png"), 1);
        touch(&home.join("Documents/game/target/debug/sprite.png"), 1);
        // The home folder is only checked for loose files.
        touch(&home.join("Code/project/assets/logo.png"), 1);

        let files = scan(&default_roots(home), [], ScanLimits::default());

        assert_eq!(names(&files), ["keep.png"]);
    }

    #[test]
    fn respects_the_depth_and_file_limits() {
        let home = tempfile::tempdir().expect("temp dir");
        let home = home.path();
        touch(&home.join("Desktop/a.png"), 1);
        touch(&home.join("Desktop/one/b.png"), 2);
        touch(&home.join("Desktop/one/two/c.png"), 3);

        let shallow = ScanLimits {
            max_depth: 1,
            ..ScanLimits::default()
        };
        assert_eq!(
            names(&scan(&default_roots(home), [], shallow)),
            ["a.png", "b.png"]
        );

        let few = ScanLimits {
            max_files: 2,
            ..ScanLimits::default()
        };
        assert_eq!(
            names(&scan(&default_roots(home), [], few)),
            ["a.png", "b.png"]
        );
    }

    #[test]
    fn adds_extra_files_once() {
        let home = tempfile::tempdir().expect("temp dir");
        let elsewhere = tempfile::tempdir().expect("temp dir");
        let in_downloads = home.path().join("Downloads/photo.jpg");
        let saved_elsewhere = elsewhere.path().join("video.webm");
        touch(&in_downloads, 1);
        touch(&saved_elsewhere, 2);

        let files = scan(
            &default_roots(home.path()),
            [
                (in_downloads.clone(), "Downloads".to_owned()),
                (saved_elsewhere, "Downloads".to_owned()),
                (elsewhere.path().join("missing.png"), "Downloads".to_owned()),
            ],
            ScanLimits::default(),
        );

        assert_eq!(names(&files), ["photo.jpg", "video.webm"]);
    }

    #[test]
    fn unreadable_roots_are_skipped() {
        let roots = [MediaRoot::new(
            "Desktop",
            PathBuf::from("/definitely/not/here"),
            true,
        )];
        assert!(scan(&roots, [], ScanLimits::default()).is_empty());
    }
}
