//! Small previews for the Library's Media grid.
//!
//! GPUI's own image loading decodes files at full size and keeps them until
//! the app quits, which doesn't scale to thousands of photos (one 48 MP photo
//! is about 190 MB decoded). Instead, each visible image is decoded on a
//! background thread, shrunk to a thumbnail, and kept in a small
//! least-recently-used cache. Only a few decode at once, newest request first,
//! so the tiles on screen fill in before ones scrolled past.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use curio_storage::media::MediaKind;
use gpui_kit::{App, AppContext as _, Context, RenderImage, Window};
use image::{DynamicImage, ImageDecoder as _, ImageReader};

/// Longest side of a thumbnail, in pixels. Tiles are 96 pt tall, so this is
/// sharp on Retina screens.
const THUMBNAIL_SIZE: u32 = 320;
/// Thumbnails kept in memory (about 400 KB each).
const CAPACITY: usize = 120;
/// Decodes running at once.
const MAX_IN_FLIGHT: usize = 3;
/// Requests waiting to decode. Older ones are dropped first, since they were
/// probably scrolled past; they're asked for again if they come back.
const MAX_PENDING: usize = 48;
/// Files larger than this aren't decoded; they show an icon instead.
const MAX_FILE_BYTES: u64 = 80 * 1024 * 1024;
/// Image formats the decoder supports. Others (HEIC, SVG) show an icon.
const DECODABLE: [&str; 8] = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff"];

/// What a tile should show.
pub(crate) enum Thumbnail {
    Ready(Arc<RenderImage>),
    Loading,
    /// A video, an unsupported format, or a file that failed to decode.
    Unavailable,
}

enum Entry {
    Pending,
    Loading,
    Ready(Arc<RenderImage>),
    Failed,
}

/// The thumbnail cache. Observe it to re-render when a thumbnail is ready.
pub(crate) struct MediaThumbnails {
    entries: HashMap<PathBuf, Entry>,
    /// Paths with a ready thumbnail, least recently used first.
    recent: VecDeque<PathBuf>,
    /// Paths waiting to decode, newest last.
    pending: VecDeque<PathBuf>,
    in_flight: usize,
}

impl MediaThumbnails {
    pub(crate) fn new() -> Self {
        Self {
            entries: HashMap::new(),
            recent: VecDeque::new(),
            pending: VecDeque::new(),
            in_flight: 0,
        }
    }

    /// The thumbnail for `path`, starting to load it if needed.
    pub(crate) fn get(
        &mut self,
        path: &Path,
        kind: MediaKind,
        cx: &mut Context<Self>,
    ) -> Thumbnail {
        if kind == MediaKind::Video || !is_decodable(path) {
            return Thumbnail::Unavailable;
        }
        match self.entries.get(path) {
            Some(Entry::Ready(image)) => {
                let image = image.clone();
                self.mark_used(path);
                Thumbnail::Ready(image)
            }
            Some(Entry::Failed) => Thumbnail::Unavailable,
            Some(Entry::Pending | Entry::Loading) => Thumbnail::Loading,
            None => {
                self.entries.insert(path.to_path_buf(), Entry::Pending);
                self.pending.push_back(path.to_path_buf());
                if self.pending.len() > MAX_PENDING
                    && let Some(stale) = self.pending.pop_front()
                {
                    self.entries.remove(&stale);
                }
                self.start_decodes(cx);
                Thumbnail::Loading
            }
        }
    }

    /// Frees every thumbnail, for when the library closes.
    pub(crate) fn clear(&mut self, window: &mut Window, cx: &mut App) {
        for (_, entry) in self.entries.drain() {
            if let Entry::Ready(image) = entry {
                cx.drop_image(image, Some(window));
            }
        }
        self.recent.clear();
        self.pending.clear();
        // Decodes already running finish and are discarded in `finish`.
    }

    fn mark_used(&mut self, path: &Path) {
        if let Some(index) = self.recent.iter().position(|p| p == path)
            && let Some(path) = self.recent.remove(index)
        {
            self.recent.push_back(path);
        }
    }

    fn start_decodes(&mut self, cx: &mut Context<Self>) {
        while self.in_flight < MAX_IN_FLIGHT {
            let Some(path) = self.pending.pop_back() else {
                break;
            };
            self.entries.insert(path.clone(), Entry::Loading);
            self.in_flight += 1;
            let task = cx.background_spawn({
                let path = path.clone();
                async move { decode_thumbnail(&path) }
            });
            cx.spawn(async move |this, cx| {
                let image = task.await;
                let _ = this.update(cx, |this, cx| this.finish(path, image, cx));
            })
            .detach();
        }
    }

    fn finish(&mut self, path: PathBuf, image: Option<RenderImage>, cx: &mut Context<Self>) {
        self.in_flight = self.in_flight.saturating_sub(1);
        // Cleared while decoding: drop the result.
        if matches!(self.entries.get(&path), Some(Entry::Loading)) {
            match image {
                Some(image) => {
                    self.entries
                        .insert(path.clone(), Entry::Ready(Arc::new(image)));
                    self.recent.push_back(path);
                    self.evict(cx);
                }
                None => {
                    self.entries.insert(path, Entry::Failed);
                }
            }
            cx.notify();
        }
        self.start_decodes(cx);
    }

    fn evict(&mut self, cx: &mut App) {
        while self.recent.len() > CAPACITY {
            let Some(oldest) = self.recent.pop_front() else {
                break;
            };
            if let Some(Entry::Ready(image)) = self.entries.remove(&oldest) {
                cx.drop_image(image, None);
            }
        }
    }
}

fn is_decodable(path: &Path) -> bool {
    path.extension().is_some_and(|ext| {
        let ext = ext.to_string_lossy().to_lowercase();
        DECODABLE.contains(&ext.as_str())
    })
}

/// Decodes `path` into a thumbnail GPUI can draw, upright and in BGRA order.
fn decode_thumbnail(path: &Path) -> Option<RenderImage> {
    let result = (|| -> image::ImageResult<RenderImage> {
        if std::fs::metadata(path)?.len() > MAX_FILE_BYTES {
            return Err(std::io::Error::other("file too large for a thumbnail").into());
        }
        let mut decoder = ImageReader::open(path)?
            .with_guessed_format()?
            .into_decoder()?;
        let orientation = decoder.orientation()?;
        let mut image = DynamicImage::from_decoder(decoder)?;
        // Phone photos are often stored sideways with a rotation flag.
        image.apply_orientation(orientation);
        let mut pixels = image.thumbnail(THUMBNAIL_SIZE, THUMBNAIL_SIZE).into_rgba8();
        for pixel in pixels.as_chunks_mut::<4>().0 {
            pixel.swap(0, 2);
        }
        Ok(RenderImage::new(vec![image::Frame::new(pixels)]))
    })();
    result
        .map_err(|error| {
            tracing::debug!(path = %path.display(), %error, "no thumbnail");
        })
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_supported_formats_are_decoded() {
        assert!(is_decodable(Path::new("/a/Photo.JPG")));
        assert!(is_decodable(Path::new("/a/shot.png")));
        assert!(!is_decodable(Path::new("/a/IMG_0001.HEIC")));
        assert!(!is_decodable(Path::new("/a/logo.svg")));
    }

    #[test]
    fn thumbnails_are_small_and_bgra() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("red.png");
        image::RgbaImage::from_pixel(1200, 600, image::Rgba([255, 0, 0, 255]))
            .save(&path)
            .expect("save png");

        let thumbnail = decode_thumbnail(&path).expect("decodes");
        let size = thumbnail.size(0);
        assert_eq!((size.width.0, size.height.0), (320, 160));
        // Red in RGBA becomes [0, 0, 255, 255] in BGRA.
        assert_eq!(
            &thumbnail.as_bytes(0).expect("pixels")[..4],
            &[0, 0, 255, 255]
        );
    }

    #[test]
    fn missing_or_broken_files_give_no_thumbnail() {
        let dir = tempfile::tempdir().expect("temp dir");
        let broken = dir.path().join("broken.jpg");
        std::fs::write(&broken, b"not an image").expect("write");
        assert!(decode_thumbnail(&broken).is_none());
        assert!(decode_thumbnail(&dir.path().join("missing.png")).is_none());
    }
}
