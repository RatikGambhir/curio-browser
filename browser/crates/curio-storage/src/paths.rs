//! Locations of Curio's on-disk data.

use std::path::PathBuf;

use crate::{Result, StorageError};

/// Overrides the data directory, mainly for tests and portable installs.
pub const DATA_DIR_ENV: &str = "CURIO_DATA_DIR";

/// The directory holding Curio's database and engine data. Created on demand.
///
/// # Errors
/// Fails when the directory cannot be created.
pub fn data_dir() -> Result<PathBuf> {
    let dir = std::env::var_os(DATA_DIR_ENV)
        .map(PathBuf::from)
        .or_else(|| dirs::data_dir().map(|d| d.join(curio_core::APP_NAME)))
        .unwrap_or_else(|| PathBuf::from(".curio"));
    std::fs::create_dir_all(&dir).map_err(|source| StorageError::DataDir {
        path: dir.clone(),
        source,
    })?;
    Ok(dir)
}

/// The SQLite database path.
///
/// # Errors
/// Fails when the data directory cannot be created.
pub fn database_path() -> Result<PathBuf> {
    Ok(data_dir()?.join("curio.db"))
}

/// Directory for web engine data (cookies, caches, local storage), kept
/// apart from Curio's own database.
///
/// # Errors
/// Fails when the directory cannot be created.
pub fn webdata_dir() -> Result<PathBuf> {
    let dir = data_dir()?.join("WebData");
    std::fs::create_dir_all(&dir).map_err(|source| StorageError::DataDir {
        path: dir.clone(),
        source,
    })?;
    Ok(dir)
}

/// The default downloads directory.
#[must_use]
pub fn default_download_dir() -> PathBuf {
    dirs::download_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
        .unwrap_or_else(std::env::temp_dir)
}
