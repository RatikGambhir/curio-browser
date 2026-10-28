//! Curio's GPUI interface.
//!
//! Everything the user sees outside the web page itself is drawn here with
//! GPUI: the sidebar and tab strips, spaces, the command bar, the AI panel,
//! settings and dialogs. Web content is drawn by the engine in
//! `curio-browser` and placed into the layout as a native view.

pub mod actions;
pub mod ai_panel;
pub mod assets;
pub mod command_bar;
mod components;
pub mod settings_view;
pub mod theme;
pub mod window;

use curio_ai::SecretStore;
use curio_settings::Settings;
use curio_storage::Storage;
use gpui_kit::{App, AppContext as _, Global};

pub use window::BrowserWindow;

/// Application services shared by every view.
#[derive(Clone)]
pub struct Services {
    pub storage: Storage,
    pub secrets: SecretStore,
}

impl Global for Services {}

impl Services {
    /// The global services.
    #[must_use]
    pub fn get(cx: &App) -> &Self {
        cx.global::<Self>()
    }
}

/// The current settings, observable with `cx.observe_global::<SettingsStore>`.
pub struct SettingsStore(pub Settings);

impl Global for SettingsStore {}

/// The current settings.
#[must_use]
pub fn settings(cx: &App) -> &Settings {
    &cx.global::<SettingsStore>().0
}

/// Changes settings, notifies observers and saves them in the background.
pub fn update_settings(cx: &mut App, change: impl FnOnce(&mut Settings)) {
    let mut next = settings(cx).clone();
    change(&mut next);
    let next = next.sanitized();
    if &next == settings(cx) {
        return;
    }
    cx.set_global(SettingsStore(next.clone()));
    let storage = Services::get(cx).storage.clone();
    cx.background_spawn(async move {
        if let Err(error) = storage.with(|db| db.save_settings(&next)) {
            tracing::error!(%error, "could not save settings");
        }
    })
    .detach();
}

/// Installs globals, key bindings and the theme. Call after `gpui_kit::init`.
pub fn init(services: Services, settings: Settings, cx: &mut App) {
    actions::bind_keys(&settings.keybindings, cx);
    cx.set_global(services);
    cx.set_global(SettingsStore(settings));
}
