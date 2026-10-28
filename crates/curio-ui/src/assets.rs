//! Embedded assets: Curio's brand artwork plus the GPUI Kit icon set.

use std::borrow::Cow;

use gpui_kit::{AssetSource, Result, SharedString};

/// The full-color logo on a transparent background.
pub const LOGO: &str = "curio/logo.png";

const BRAND: [(&str, &[u8]); 1] = [(LOGO, include_bytes!("../../../assets/brand/curio-logo.png"))];

/// Curio's asset source.
pub struct CurioAssets;

impl AssetSource for CurioAssets {
    fn load(&self, path: &str) -> Result<Option<Cow<'static, [u8]>>> {
        if let Some((_, bytes)) = BRAND.iter().find(|(name, _)| *name == path) {
            return Ok(Some(Cow::Borrowed(bytes)));
        }
        gpui_kit::assets::AllAssets.load(path)
    }

    fn list(&self, path: &str) -> Result<Vec<SharedString>> {
        let mut out: Vec<SharedString> = BRAND
            .iter()
            .filter(|(name, _)| name.starts_with(path))
            .map(|(name, _)| SharedString::from(*name))
            .collect();
        out.extend(gpui_kit::assets::AllAssets.list(path)?);
        Ok(out)
    }
}
