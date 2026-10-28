//! Local persistence for Curio.
//!
//! Structured application state lives in a single SQLite database in the
//! platform data directory (`~/Library/Application Support/Curio` on macOS).
//! Web engine state (cookies, caches, site storage) is kept separately under
//! [`paths::webdata_dir`] and is owned by the engine.
//!
//! [`Database`] is synchronous. [`Storage`] wraps it in a shareable handle so
//! the UI can hand writes to background threads.

mod database;
mod migrations;
pub mod paths;

use std::sync::{Arc, Mutex, MutexGuard};

pub use database::{Bookmark, Database, DownloadRecord, HistoryEntry, PermissionDecision};

/// Errors from the storage layer.
#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("database error")]
    Sqlite(#[from] rusqlite::Error),
    #[error("could not create data directory {path}")]
    DataDir {
        path: std::path::PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("stored data is corrupt: {0}")]
    Corrupt(String),
}

/// Result alias for storage operations.
pub type Result<T, E = StorageError> = std::result::Result<T, E>;

/// A cloneable, thread-safe handle to the database.
#[derive(Clone)]
pub struct Storage {
    inner: Arc<Mutex<Database>>,
}

impl Storage {
    /// Wraps an open database.
    #[must_use]
    pub fn new(db: Database) -> Self {
        Self {
            inner: Arc::new(Mutex::new(db)),
        }
    }

    /// Opens (creating and migrating if needed) the default database.
    ///
    /// # Errors
    /// Fails when the data directory cannot be created or the database
    /// cannot be opened or migrated.
    pub fn open_default() -> Result<Self> {
        let path = paths::database_path()?;
        Ok(Self::new(Database::open(&path)?))
    }

    /// Runs `f` with exclusive access to the database. A poisoned lock (a
    /// panic in another writer) is recovered, since SQLite transactions keep
    /// the data itself consistent.
    pub fn with<T>(&self, f: impl FnOnce(&mut Database) -> T) -> T {
        let mut guard: MutexGuard<'_, Database> = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        f(&mut guard)
    }
}
