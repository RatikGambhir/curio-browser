//! API key storage.
//!
//! On macOS keys live in the login Keychain and on Windows in the Credential
//! Manager. Other platforms fall back to an owner-only (0600) file in Curio's
//! data directory. Keys are never written to the settings database or logs.
//!
//! For development, `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` /
//! `CURIO_OPENAI_COMPATIBLE_API_KEY` are used when no key is stored.

use std::path::PathBuf;

use curio_settings::AiProviderKind;

/// Errors from the secret store.
#[derive(Debug, thiserror::Error)]
pub enum SecretError {
    #[error("the system keychain rejected the request: {0}")]
    Keychain(String),
    #[error("could not write the key file")]
    Io(#[from] std::io::Error),
}

/// Reads and writes provider API keys.
#[derive(Debug, Clone)]
pub struct SecretStore {
    #[cfg_attr(any(target_os = "macos", target_os = "windows"), allow(dead_code))]
    fallback_dir: PathBuf,
}

const ENV_VARS: [(AiProviderKind, &str); 3] = [
    (AiProviderKind::Anthropic, "ANTHROPIC_API_KEY"),
    (AiProviderKind::OpenAi, "OPENAI_API_KEY"),
    (AiProviderKind::OpenAiCompatible, "CURIO_OPENAI_COMPATIBLE_API_KEY"),
];

impl SecretStore {
    /// Creates a store; `fallback_dir` is used only on platforms without a
    /// supported keychain.
    #[must_use]
    pub fn new(fallback_dir: PathBuf) -> Self {
        Self { fallback_dir }
    }

    /// The stored key for `kind`, or the matching environment variable.
    #[must_use]
    pub fn api_key(&self, kind: AiProviderKind) -> Option<String> {
        self.get(kind.keychain_account())
            .filter(|k| !k.trim().is_empty())
            .or_else(|| {
                ENV_VARS
                    .iter()
                    .find(|(k, _)| *k == kind)
                    .and_then(|(_, var)| std::env::var(var).ok())
                    .filter(|k| !k.trim().is_empty())
            })
    }

    /// Whether a key is stored (not counting environment variables).
    #[must_use]
    pub fn has_stored_key(&self, kind: AiProviderKind) -> bool {
        self.get(kind.keychain_account()).is_some_and(|k| !k.is_empty())
    }

    /// Stores a key; an empty value deletes it.
    ///
    /// # Errors
    /// Fails when the keychain or file system rejects the write.
    pub fn set_api_key(&self, kind: AiProviderKind, key: &str) -> Result<(), SecretError> {
        let key = key.trim();
        if key.is_empty() {
            self.delete(kind.keychain_account())
        } else {
            self.set(kind.keychain_account(), key)
        }
    }

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    fn entry(account: &str) -> Result<keyring::Entry, SecretError> {
        keyring::Entry::new(curio_core::BUNDLE_ID, account)
            .map_err(|e| SecretError::Keychain(e.to_string()))
    }

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    fn get(&self, account: &str) -> Option<String> {
        match Self::entry(account).and_then(|e| {
            e.get_password()
                .map_err(|e| SecretError::Keychain(e.to_string()))
        }) {
            Ok(value) => Some(value),
            Err(_) => None,
        }
    }

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    fn set(&self, account: &str, value: &str) -> Result<(), SecretError> {
        Self::entry(account)?
            .set_password(value)
            .map_err(|e| SecretError::Keychain(e.to_string()))
    }

    #[cfg(any(target_os = "macos", target_os = "windows"))]
    fn delete(&self, account: &str) -> Result<(), SecretError> {
        match Self::entry(account)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(SecretError::Keychain(e.to_string())),
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    fn path(&self, account: &str) -> PathBuf {
        self.fallback_dir.join("secrets").join(account)
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    fn get(&self, account: &str) -> Option<String> {
        std::fs::read_to_string(self.path(account))
            .ok()
            .map(|s| s.trim().to_owned())
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    fn set(&self, account: &str, value: &str) -> Result<(), SecretError> {
        use std::io::Write;
        let path = self.path(account);
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path)?;
        file.write_all(value.as_bytes())?;
        Ok(())
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    fn delete(&self, account: &str) -> Result<(), SecretError> {
        match std::fs::remove_file(self.path(account)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.into()),
        }
    }
}

#[cfg(all(test, not(any(target_os = "macos", target_os = "windows"))))]
mod tests {
    use super::*;

    #[test]
    fn file_fallback_stores_with_owner_only_permissions() {
        let dir = tempfile::tempdir().expect("tempdir");
        let store = SecretStore::new(dir.path().to_path_buf());
        store
            .set_api_key(AiProviderKind::OpenAiCompatible, " key-123 ")
            .expect("set");
        assert!(store.has_stored_key(AiProviderKind::OpenAiCompatible));
        assert_eq!(
            store.api_key(AiProviderKind::OpenAiCompatible).as_deref(),
            Some("key-123")
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(store.path("openai-compatible-api-key"))
                .expect("meta")
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        store
            .set_api_key(AiProviderKind::OpenAiCompatible, "")
            .expect("delete");
        assert!(!store.has_stored_key(AiProviderKind::OpenAiCompatible));
    }
}
