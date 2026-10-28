//! User preferences.
//!
//! Settings are a plain serde struct stored as JSON by `curio-storage`. Every
//! field has a default (`#[serde(default)]`) so settings written by older or
//! newer versions of Curio always load. Secrets such as AI API keys are never
//! stored here; they live in the platform keychain.

use std::collections::BTreeMap;

use curio_core::SearchEngine;
use serde::{Deserialize, Serialize};

/// Light, dark, or following the operating system.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ThemeMode {
    #[default]
    System,
    Light,
    Dark,
}

/// Where tabs are shown.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TabLayout {
    /// Arc-style vertical sidebar.
    #[default]
    Vertical,
    /// A traditional tab strip above the page.
    Horizontal,
}

/// Which AI service Curio talks to.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, Default,
)]
#[serde(rename_all = "snake_case")]
pub enum AiProviderKind {
    #[default]
    Anthropic,
    OpenAi,
    /// Any server implementing OpenAI's chat completions API (Ollama,
    /// LM Studio, OpenRouter, vLLM, ...).
    OpenAiCompatible,
}

impl AiProviderKind {
    /// Every provider, for settings menus.
    pub const ALL: [Self; 3] = [Self::Anthropic, Self::OpenAi, Self::OpenAiCompatible];

    /// A display name.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Anthropic => "Anthropic",
            Self::OpenAi => "OpenAI",
            Self::OpenAiCompatible => "OpenAI-compatible",
        }
    }

    /// The model used when the user has not chosen one.
    #[must_use]
    pub const fn default_model(self) -> &'static str {
        match self {
            Self::Anthropic => "claude-opus-5-5",
            Self::OpenAi => "gpt-5",
            Self::OpenAiCompatible => "llama3.1",
        }
    }

    /// The API base URL used when the user has not set one.
    #[must_use]
    pub const fn default_base_url(self) -> &'static str {
        match self {
            Self::Anthropic => "https://api.anthropic.com",
            Self::OpenAi => "https://api.openai.com/v1",
            Self::OpenAiCompatible => "http://localhost:11434/v1",
        }
    }

    /// Whether the provider requires an API key. Local OpenAI-compatible
    /// servers usually do not.
    #[must_use]
    pub const fn requires_api_key(self) -> bool {
        !matches!(self, Self::OpenAiCompatible)
    }

    /// The keychain account name for this provider's API key.
    #[must_use]
    pub const fn keychain_account(self) -> &'static str {
        match self {
            Self::Anthropic => "anthropic-api-key",
            Self::OpenAi => "openai-api-key",
            Self::OpenAiCompatible => "openai-compatible-api-key",
        }
    }
}

/// Per-provider configuration (everything except the secret key).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct ProviderSettings {
    /// Model identifier; empty means the provider default.
    pub model: String,
    /// API base URL; empty means the provider default.
    pub base_url: String,
}

/// Appearance preferences.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AppearanceSettings {
    pub theme: ThemeMode,
    pub tab_layout: TabLayout,
    pub sidebar_visible: bool,
    pub sidebar_width: f32,
    pub ai_panel_width: f32,
    /// Tint the window chrome with the active space's color.
    pub tint_chrome_with_space: bool,
    /// Reduce animations for accessibility.
    pub reduce_motion: bool,
}

impl Default for AppearanceSettings {
    fn default() -> Self {
        Self {
            theme: ThemeMode::System,
            tab_layout: TabLayout::Vertical,
            sidebar_visible: true,
            sidebar_width: 260.0,
            ai_panel_width: 380.0,
            tint_chrome_with_space: true,
            reduce_motion: false,
        }
    }
}

/// Browsing behavior.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct BrowsingSettings {
    pub search_engine: SearchEngine,
    /// Restore spaces and tabs from the previous session on launch.
    pub restore_session: bool,
    /// Record visited pages in history.
    pub save_history: bool,
    /// Live webviews kept in memory before the least recently used
    /// background tabs are put to sleep.
    pub max_live_tabs: usize,
    /// Minutes of inactivity before a background tab is put to sleep.
    pub sleep_after_minutes: u32,
    /// Where downloads are saved; empty means the system Downloads folder.
    pub download_dir: String,
}

impl Default for BrowsingSettings {
    fn default() -> Self {
        Self {
            search_engine: SearchEngine::Google,
            restore_session: true,
            save_history: true,
            max_live_tabs: 12,
            sleep_after_minutes: 60,
            download_dir: String::new(),
        }
    }
}

/// AI assistant preferences.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AiSettings {
    pub provider: AiProviderKind,
    pub providers: BTreeMap<AiProviderKind, ProviderSettings>,
    /// Attach the current tab as context when starting a message. The
    /// attachment is always visible and removable before sending.
    pub auto_attach_current_tab: bool,
    /// Upper bound on page text sent per request, in characters.
    pub max_context_chars: usize,
    /// Language used by "Translate selection".
    pub translate_to: String,
}

impl Default for AiSettings {
    fn default() -> Self {
        Self {
            provider: AiProviderKind::Anthropic,
            providers: BTreeMap::new(),
            auto_attach_current_tab: true,
            max_context_chars: 60_000,
            translate_to: "English".to_owned(),
        }
    }
}

impl AiSettings {
    /// The effective model for `provider`.
    #[must_use]
    pub fn model(&self, provider: AiProviderKind) -> String {
        self.providers
            .get(&provider)
            .map(|p| p.model.trim())
            .filter(|m| !m.is_empty())
            .unwrap_or(provider.default_model())
            .to_owned()
    }

    /// The effective base URL for `provider`, without a trailing slash.
    #[must_use]
    pub fn base_url(&self, provider: AiProviderKind) -> String {
        self.providers
            .get(&provider)
            .map(|p| p.base_url.trim())
            .filter(|u| !u.is_empty())
            .unwrap_or(provider.default_base_url())
            .trim_end_matches('/')
            .to_owned()
    }
}

/// All user preferences.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct Settings {
    pub appearance: AppearanceSettings,
    pub browsing: BrowsingSettings,
    pub ai: AiSettings,
    /// User keybinding overrides: action name (e.g. `curio::NewTab`) to
    /// keystroke (e.g. `cmd-shift-n`). An empty keystroke unbinds.
    pub keybindings: BTreeMap<String, String>,
}

impl Settings {
    /// Parses settings JSON, falling back to defaults for anything missing
    /// or malformed.
    #[must_use]
    pub fn from_json(json: &str) -> Self {
        serde_json::from_str(json).unwrap_or_default()
    }

    /// Serializes settings to JSON.
    #[must_use]
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".to_owned())
    }

    /// Clamps values a user could have edited out of range.
    #[must_use]
    pub fn sanitized(mut self) -> Self {
        let a = &mut self.appearance;
        a.sidebar_width = a.sidebar_width.clamp(200.0, 420.0);
        a.ai_panel_width = a.ai_panel_width.clamp(300.0, 640.0);
        let b = &mut self.browsing;
        b.max_live_tabs = b.max_live_tabs.clamp(2, 64);
        b.sleep_after_minutes = b.sleep_after_minutes.clamp(5, 24 * 60);
        self.ai.max_context_chars = self.ai.max_context_chars.clamp(2_000, 400_000);
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_json_fills_defaults() {
        let settings = Settings::from_json(r#"{"appearance":{"tab_layout":"horizontal"}}"#);
        assert_eq!(settings.appearance.tab_layout, TabLayout::Horizontal);
        assert!(settings.appearance.sidebar_visible);
        assert_eq!(settings.browsing.search_engine, SearchEngine::Google);
    }

    #[test]
    fn malformed_json_gives_defaults() {
        assert_eq!(Settings::from_json("{not json"), Settings::default());
    }

    #[test]
    fn round_trip_preserves_values() {
        let mut settings = Settings::default();
        settings.browsing.search_engine = SearchEngine::Custom("https://s.test/?q=%s".into());
        settings.ai.provider = AiProviderKind::OpenAiCompatible;
        settings
            .keybindings
            .insert("curio::NewTab".into(), "cmd-shift-t".into());
        let back = Settings::from_json(&settings.to_json());
        assert_eq!(back, settings);
    }

    #[test]
    fn provider_overrides_fall_back_to_defaults() {
        let mut ai = AiSettings::default();
        assert_eq!(
            ai.base_url(AiProviderKind::OpenAi),
            "https://api.openai.com/v1"
        );
        ai.providers.insert(
            AiProviderKind::OpenAiCompatible,
            ProviderSettings {
                model: "qwen2.5".into(),
                base_url: "http://127.0.0.1:1234/v1/".into(),
            },
        );
        assert_eq!(ai.model(AiProviderKind::OpenAiCompatible), "qwen2.5");
        assert_eq!(
            ai.base_url(AiProviderKind::OpenAiCompatible),
            "http://127.0.0.1:1234/v1"
        );
    }

    #[test]
    fn sanitize_clamps_ranges() {
        let mut settings = Settings::default();
        settings.appearance.sidebar_width = 5.0;
        settings.browsing.max_live_tabs = 0;
        let settings = settings.sanitized();
        assert!((settings.appearance.sidebar_width - 200.0).abs() < f32::EPSILON);
        assert_eq!(settings.browsing.max_live_tabs, 2);
    }
}
