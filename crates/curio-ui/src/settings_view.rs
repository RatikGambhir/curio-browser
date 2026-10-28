//! The settings screen.

use curio_ai::providers::suggested_models;
use curio_ai::{ProviderConfig, verify_provider};
use curio_core::SearchEngine;
use curio_settings::{AiProviderKind, TabLayout, ThemeMode};
use gpui_kit::assets::IconName;
use gpui_kit::component::Disableable as _;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::component::menu::{DropdownMenu as _, PopupMenuItem};
use gpui_kit::component::radio::RadioGroup;
use gpui_kit::component::switch::Switch;
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, AppContext as _, Context, Entity, FontWeight, InteractiveElement as _,
    IntoElement, ParentElement as _, Render, SharedString, StatefulInteractiveElement as _,
    Styled as _, Subscription, Task, Window, div, px,
};

use crate::actions;
use crate::theme::CurioTheme;
use crate::{Services, settings, update_settings};

/// Settings sections.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Section {
    General,
    Appearance,
    Ai,
    Privacy,
    Shortcuts,
}

impl Section {
    const ALL: [Self; 5] = [
        Self::General,
        Self::Appearance,
        Self::Ai,
        Self::Privacy,
        Self::Shortcuts,
    ];

    fn label(self) -> &'static str {
        match self {
            Self::General => "General",
            Self::Appearance => "Appearance",
            Self::Ai => "AI Assistant",
            Self::Privacy => "Privacy",
            Self::Shortcuts => "Shortcuts",
        }
    }

    fn icon(self) -> IconName {
        match self {
            Self::General => IconName::Settings2,
            Self::Appearance => IconName::Palette,
            Self::Ai => IconName::Sparkles,
            Self::Privacy => IconName::Shield,
            Self::Shortcuts => IconName::Keyboard,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum TestState {
    Idle,
    Testing,
    Ok,
    Failed(String),
}

/// The settings view.
pub struct SettingsView {
    section: Section,
    custom_search: Entity<InputState>,
    download_dir: Entity<InputState>,
    model: Entity<InputState>,
    base_url: Entity<InputState>,
    api_key: Entity<InputState>,
    translate_to: Entity<InputState>,
    shortcut_inputs: Vec<(String, Entity<InputState>)>,
    test: TestState,
    _test_task: Task<()>,
    _subscriptions: Vec<Subscription>,
}

impl SettingsView {
    /// Creates the view, optionally opened at `section`.
    pub fn new(section: Option<Section>, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let s = settings(cx).clone();
        let provider = s.ai.provider;
        let custom = match &s.browsing.search_engine {
            SearchEngine::Custom(t) => t.clone(),
            _ => String::new(),
        };
        let input =
            |cx: &mut Context<Self>, window: &mut Window, placeholder: &str, value: String| {
                let placeholder = placeholder.to_owned();
                cx.new(|cx| {
                    InputState::new(window, cx)
                        .placeholder(placeholder)
                        .default_value(value)
                })
            };
        let custom_search = input(cx, window, "https://example.com/search?q=%s", custom);
        let download_dir = input(
            cx,
            window,
            &curio_storage::paths::default_download_dir().to_string_lossy(),
            s.browsing.download_dir.clone(),
        );
        let model = input(
            cx,
            window,
            provider.default_model(),
            s.ai.providers
                .get(&provider)
                .map(|p| p.model.clone())
                .unwrap_or_default(),
        );
        let base_url = input(
            cx,
            window,
            provider.default_base_url(),
            s.ai.providers
                .get(&provider)
                .map(|p| p.base_url.clone())
                .unwrap_or_default(),
        );
        let has_key = Services::get(cx).secrets.has_stored_key(provider);
        let api_key = cx.new(|cx| {
            InputState::new(window, cx)
                .masked(true)
                .placeholder(if has_key {
                    "•••••••• (stored in Keychain)"
                } else {
                    "Paste your API key"
                })
        });
        let translate_to = input(cx, window, "English", s.ai.translate_to.clone());

        let shortcut_inputs: Vec<(String, Entity<InputState>)> =
            actions::effective_bindings(&s.keybindings)
                .into_iter()
                .map(|(key, action)| (action.name().to_owned(), key))
                .fold(Vec::<(String, String)>::new(), |mut acc, (name, key)| {
                    if !acc.iter().any(|(n, _)| *n == name) {
                        acc.push((name, key));
                    }
                    acc
                })
                .into_iter()
                .map(|(name, key)| {
                    let entity = cx.new(|cx| InputState::new(window, cx).default_value(key));
                    (name, entity)
                })
                .collect();

        let mut subscriptions = Vec::new();
        let on_commit = |cx: &mut Context<Self>,
                         window: &mut Window,
                         entity: &Entity<InputState>,
                         apply: fn(&mut curio_settings::Settings, String)| {
            cx.subscribe_in(
                entity,
                window,
                move |_, state, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Blur | InputEvent::PressEnter { .. }) {
                        let value = state.read(cx).value().trim().to_owned();
                        update_settings(cx, |s| apply(s, value));
                    }
                },
            )
        };
        subscriptions.push(on_commit(cx, window, &custom_search, |s, v| {
            if !v.is_empty() {
                s.browsing.search_engine = SearchEngine::Custom(v);
            }
        }));
        subscriptions.push(on_commit(cx, window, &download_dir, |s, v| {
            s.browsing.download_dir = v
        }));
        subscriptions.push(on_commit(cx, window, &model, |s, v| {
            let provider = s.ai.provider;
            s.ai.providers.entry(provider).or_default().model = v;
        }));
        subscriptions.push(on_commit(cx, window, &base_url, |s, v| {
            let provider = s.ai.provider;
            s.ai.providers.entry(provider).or_default().base_url = v;
        }));
        subscriptions.push(on_commit(cx, window, &translate_to, |s, v| {
            if !v.is_empty() {
                s.ai.translate_to = v;
            }
        }));
        subscriptions.push(cx.subscribe_in(
            &api_key,
            window,
            |this, state, event: &InputEvent, window, cx| {
                if matches!(event, InputEvent::PressEnter { .. }) {
                    let key = state.read(cx).value().to_string();
                    this.save_api_key(&key, window, cx);
                }
            },
        ));
        for (name, entity) in &shortcut_inputs {
            let name = name.clone();
            subscriptions.push(cx.subscribe_in(
                entity,
                window,
                move |_, state, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Blur | InputEvent::PressEnter { .. }) {
                        let value = state.read(cx).value().trim().to_owned();
                        let default = actions::effective_bindings(&Default::default())
                            .into_iter()
                            .find(|(_, a)| a.name() == name)
                            .map(|(k, _)| k);
                        update_settings(cx, |s| {
                            if default.as_deref() == Some(value.as_str()) {
                                s.keybindings.remove(&name);
                            } else {
                                s.keybindings.insert(name.clone(), value.clone());
                            }
                        });
                    }
                },
            ));
        }

        Self {
            section: section.unwrap_or(Section::General),
            custom_search,
            download_dir,
            model,
            base_url,
            api_key,
            translate_to,
            shortcut_inputs,
            test: TestState::Idle,
            _test_task: Task::ready(()),
            _subscriptions: subscriptions,
        }
    }

    fn save_api_key(&mut self, key: &str, window: &mut Window, cx: &mut Context<Self>) {
        let provider = settings(cx).ai.provider;
        match Services::get(cx).secrets.set_api_key(provider, key) {
            Ok(()) => {
                self.api_key.update(cx, |state, cx| {
                    state.set_value(String::new(), window, cx);
                    state.set_placeholder(
                        if key.trim().is_empty() {
                            "Paste your API key"
                        } else {
                            "•••••••• (stored in Keychain)"
                        },
                        window,
                        cx,
                    );
                });
                self.test = TestState::Idle;
            }
            Err(error) => self.test = TestState::Failed(error.to_string()),
        }
        cx.notify();
    }

    fn switch_provider(
        &mut self,
        provider: AiProviderKind,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        update_settings(cx, |s| s.ai.provider = provider);
        let s = settings(cx).clone();
        let entry = s.ai.providers.get(&provider).cloned().unwrap_or_default();
        let has_key = Services::get(cx).secrets.has_stored_key(provider);
        self.model.update(cx, |state, cx| {
            state.set_value(entry.model, window, cx);
            state.set_placeholder(provider.default_model(), window, cx);
        });
        self.base_url.update(cx, |state, cx| {
            state.set_value(entry.base_url, window, cx);
            state.set_placeholder(provider.default_base_url(), window, cx);
        });
        self.api_key.update(cx, |state, cx| {
            state.set_value(String::new(), window, cx);
            state.set_placeholder(
                if has_key {
                    "•••••••• (stored in Keychain)"
                } else if provider.requires_api_key() {
                    "Paste your API key"
                } else {
                    "Optional"
                },
                window,
                cx,
            );
        });
        self.test = TestState::Idle;
        cx.notify();
    }

    fn test_connection(&mut self, cx: &mut Context<Self>) {
        let config = ProviderConfig::from_settings(&settings(cx).ai, &Services::get(cx).secrets);
        self.test = TestState::Testing;
        let task = cx.background_spawn(async move { verify_provider(&config) });
        self._test_task = cx.spawn(async move |this, cx| {
            let result = task.await;
            let _ = this.update(cx, |this, cx| {
                this.test = match result {
                    Ok(()) => TestState::Ok,
                    Err(error) => TestState::Failed(error.to_string()),
                };
                cx.notify();
            });
        });
        cx.notify();
    }

    fn row(
        label: &str,
        description: Option<&str>,
        control: impl IntoElement,
        cx: &App,
    ) -> AnyElement {
        let theme = CurioTheme::get(cx);
        h_flex()
            .w_full()
            .py(px(10.))
            .gap(px(16.))
            .border_b_1()
            .border_color(theme.divider)
            .child(
                v_flex()
                    .flex_1()
                    .min_w_0()
                    .gap(px(2.))
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(theme.text)
                            .child(SharedString::from(label.to_owned())),
                    )
                    .when_some(description, |el, d| {
                        el.child(
                            div()
                                .text_xs()
                                .text_color(theme.text_faint)
                                .child(SharedString::from(d.to_owned())),
                        )
                    }),
            )
            .child(div().flex_shrink_0().child(control))
            .into_any_element()
    }

    fn render_general(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let s = settings(cx).clone();
        let engine = s.browsing.search_engine.clone();
        let engine_label = SharedString::from(engine.label().to_owned());
        vec![
            Self::row(
                "Search engine",
                Some("Used for searches typed into the address bar."),
                Button::new("engine")
                    .small()
                    .label(engine_label)
                    .icon(IconName::ChevronDown)
                    .dropdown_menu(move |mut menu, _, _| {
                        for option in SearchEngine::BUILT_IN {
                            let checked = option == engine;
                            let value = option.clone();
                            menu = menu.item(
                                PopupMenuItem::new(option.label().to_owned())
                                    .checked(checked)
                                    .on_click(move |_, _, cx| {
                                        let value = value.clone();
                                        update_settings(cx, |s| s.browsing.search_engine = value);
                                    }),
                            );
                        }
                        menu
                    }),
                cx,
            ),
            Self::row(
                "Custom search URL",
                Some("Optional. Use %s where the query goes; press Return to use it."),
                div()
                    .w(px(300.))
                    .child(Input::new(&self.custom_search).small()),
                cx,
            ),
            Self::row(
                "Restore previous session",
                Some("Reopen your spaces and tabs when Curio starts."),
                Switch::new("restore")
                    .checked(s.browsing.restore_session)
                    .on_change(|v, _, cx| {
                        let v = *v;
                        update_settings(cx, |s| s.browsing.restore_session = v);
                    }),
                cx,
            ),
            Self::row(
                "Download folder",
                Some("Leave empty to use your Downloads folder."),
                div()
                    .w(px(300.))
                    .child(Input::new(&self.download_dir).small()),
                cx,
            ),
            Self::row(
                "Tabs kept in memory",
                Some(
                    "Background tabs beyond this limit are put to sleep and reload when you return.",
                ),
                h_flex()
                    .gap(px(6.))
                    .child(
                        Button::new("live-minus")
                            .xsmall()
                            .icon(IconName::Minus)
                            .on_click(|_, _, cx| {
                                update_settings(cx, |s| {
                                    s.browsing.max_live_tabs =
                                        s.browsing.max_live_tabs.saturating_sub(1)
                                });
                            }),
                    )
                    .child(
                        div()
                            .w(px(28.))
                            .text_center()
                            .text_sm()
                            .child(SharedString::from(s.browsing.max_live_tabs.to_string())),
                    )
                    .child(
                        Button::new("live-plus")
                            .xsmall()
                            .icon(IconName::Plus)
                            .on_click(|_, _, cx| {
                                update_settings(cx, |s| s.browsing.max_live_tabs += 1);
                            }),
                    ),
                cx,
            ),
        ]
    }

    fn render_appearance(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let s = settings(cx).clone();
        let theme_index = match s.appearance.theme {
            ThemeMode::System => 0,
            ThemeMode::Light => 1,
            ThemeMode::Dark => 2,
        };
        let layout_index = match s.appearance.tab_layout {
            TabLayout::Vertical => 0,
            TabLayout::Horizontal => 1,
        };
        vec![
            Self::row(
                "Theme",
                None,
                RadioGroup::horizontal("theme-mode")
                    .children(["System", "Light", "Dark"])
                    .selected_index(Some(theme_index))
                    .on_change(|i, _, cx| {
                        let mode = match i {
                            1 => ThemeMode::Light,
                            2 => ThemeMode::Dark,
                            _ => ThemeMode::System,
                        };
                        update_settings(cx, |s| s.appearance.theme = mode);
                    }),
                cx,
            ),
            Self::row(
                "Tab layout",
                Some(
                    "Vertical tabs live in the sidebar; horizontal tabs sit above the page. Your tabs stay as they are.",
                ),
                RadioGroup::horizontal("tab-layout")
                    .children(["Vertical", "Horizontal"])
                    .selected_index(Some(layout_index))
                    .on_change(|i, _, cx| {
                        let layout = if *i == 1 {
                            TabLayout::Horizontal
                        } else {
                            TabLayout::Vertical
                        };
                        update_settings(cx, |s| s.appearance.tab_layout = layout);
                    }),
                cx,
            ),
            Self::row(
                "Show sidebar",
                Some("Hide it to give the page more room; hover the left edge to peek."),
                Switch::new("sidebar")
                    .checked(s.appearance.sidebar_visible)
                    .on_change(|v, _, cx| {
                        let v = *v;
                        update_settings(cx, |s| s.appearance.sidebar_visible = v);
                    }),
                cx,
            ),
            Self::row(
                "Reduce motion",
                Some("Turn off space transitions and other animations."),
                Switch::new("motion")
                    .checked(s.appearance.reduce_motion)
                    .on_change(|v, _, cx| {
                        let v = *v;
                        update_settings(cx, |s| s.appearance.reduce_motion = v);
                    }),
                cx,
            ),
        ]
    }

    fn render_ai(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let theme = *CurioTheme::get(cx);
        let s = settings(cx).clone();
        let provider = s.ai.provider;
        let provider_index = AiProviderKind::ALL
            .iter()
            .position(|p| *p == provider)
            .unwrap_or(0);
        let models = suggested_models(provider);
        let model_entity = self.model.clone();
        let has_key = Services::get(cx).secrets.has_stored_key(provider)
            || ProviderConfig::from_settings(&s.ai, &Services::get(cx).secrets)
                .api_key
                .is_some();
        let test = self.test.clone();
        vec![
            Self::row(
                "Provider",
                None,
                RadioGroup::horizontal("provider")
                    .children(AiProviderKind::ALL.map(AiProviderKind::label))
                    .selected_index(Some(provider_index))
                    .on_change(cx.listener(|this, i: &usize, window, cx| {
                        let provider = AiProviderKind::ALL[*i];
                        this.switch_provider(provider, window, cx);
                    })),
                cx,
            ),
            Self::row(
                "Model",
                Some("Leave empty for the default, or pick a suggestion."),
                h_flex()
                    .gap(px(6.))
                    .child(div().w(px(240.)).child(Input::new(&self.model).small()))
                    .child(
                        Button::new("model-suggestions")
                            .small()
                            .icon(IconName::ChevronDown)
                            .dropdown_menu(move |mut menu, _, _| {
                                for model in models {
                                    let model_entity = model_entity.clone();
                                    let value = (*model).to_owned();
                                    menu = menu.item(PopupMenuItem::new(*model).on_click(
                                        move |_, window, cx| {
                                            let value = value.clone();
                                            model_entity.update(cx, |state, cx| {
                                                state.set_value(value.clone(), window, cx)
                                            });
                                            update_settings(cx, |s| {
                                                let p = s.ai.provider;
                                                s.ai.providers.entry(p).or_default().model = value;
                                            });
                                        },
                                    ));
                                }
                                menu
                            }),
                    ),
                cx,
            ),
            Self::row(
                "API base URL",
                Some(match provider {
                    AiProviderKind::OpenAiCompatible => {
                        "For example Ollama (http://localhost:11434/v1) or LM Studio."
                    }
                    _ => "Leave empty for the official endpoint.",
                }),
                div().w(px(300.)).child(Input::new(&self.base_url).small()),
                cx,
            ),
            Self::row(
                "API key",
                Some(
                    "Stored in your macOS Keychain, never in Curio’s database. Press Return or Save.",
                ),
                h_flex()
                    .gap(px(6.))
                    .child(
                        div()
                            .w(px(230.))
                            .child(Input::new(&self.api_key).small().mask_toggle()),
                    )
                    .child(
                        Button::new("save-key")
                            .small()
                            .primary()
                            .label("Save")
                            .on_click(cx.listener(|this, _, window, cx| {
                                let key = this.api_key.read(cx).value().to_string();
                                if !key.trim().is_empty() {
                                    this.save_api_key(&key, window, cx);
                                }
                            })),
                    )
                    .when(Services::get(cx).secrets.has_stored_key(provider), |el| {
                        el.child(
                            Button::new("remove-key")
                                .small()
                                .ghost()
                                .icon(IconName::Delete)
                                .tooltip("Remove key")
                                .on_click(cx.listener(|this, _, window, cx| {
                                    this.save_api_key("", window, cx)
                                })),
                        )
                    }),
                cx,
            ),
            Self::row(
                "Connection",
                None,
                h_flex()
                    .gap(px(8.))
                    .child(match &test {
                        TestState::Idle => div()
                            .text_xs()
                            .text_color(theme.text_faint)
                            .child(if has_key || !provider.requires_api_key() {
                                "Not tested"
                            } else {
                                "No key yet"
                            })
                            .into_any_element(),
                        TestState::Testing => div()
                            .text_xs()
                            .text_color(theme.text_faint)
                            .child("Testing…")
                            .into_any_element(),
                        TestState::Ok => h_flex()
                            .gap(px(4.))
                            .text_xs()
                            .text_color(theme.success)
                            .child(Icon::new(IconName::CircleCheck).xsmall())
                            .child("Connected")
                            .into_any_element(),
                        TestState::Failed(e) => div()
                            .max_w(px(260.))
                            .text_xs()
                            .text_color(theme.danger)
                            .child(SharedString::from(e.clone()))
                            .into_any_element(),
                    })
                    .child(
                        Button::new("test-ai")
                            .small()
                            .label("Test")
                            .disabled(test == TestState::Testing)
                            .on_click(cx.listener(|this, _, _, cx| this.test_connection(cx))),
                    ),
                cx,
            ),
            Self::row(
                "Attach the current tab automatically",
                Some(
                    "New messages include the page you’re viewing. It’s always shown above the message box and can be removed.",
                ),
                Switch::new("auto-attach")
                    .checked(s.ai.auto_attach_current_tab)
                    .on_change(|v, _, cx| {
                        let v = *v;
                        update_settings(cx, |s| s.ai.auto_attach_current_tab = v);
                    }),
                cx,
            ),
            Self::row(
                "Translate selections into",
                None,
                div()
                    .w(px(200.))
                    .child(Input::new(&self.translate_to).small()),
                cx,
            ),
        ]
    }

    fn render_privacy(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let s = settings(cx).clone();
        vec![
            Self::row(
                "Save browsing history",
                Some("History powers address bar suggestions. It never leaves this Mac."),
                Switch::new("history")
                    .checked(s.browsing.save_history)
                    .on_change(|v, _, cx| {
                        let v = *v;
                        update_settings(cx, |s| s.browsing.save_history = v);
                    }),
                cx,
            ),
            Self::row(
                "Clear history",
                None,
                Button::new("clear-history-settings")
                    .small()
                    .danger()
                    .label("Clear History")
                    .on_click(|_, window, cx| {
                        let storage = Services::get(cx).storage.clone();
                        let _ = storage.with(|db| db.clear_history());
                        gpui_kit::component::WindowExt::push_notification(
                            window,
                            "History cleared",
                            cx,
                        );
                    }),
                cx,
            ),
            Self::row(
                "Clear chat history",
                Some("Deletes saved conversations with the assistant."),
                Button::new("clear-chats")
                    .small()
                    .danger()
                    .label("Delete Chats")
                    .on_click(|_, window, cx| {
                        let storage = Services::get(cx).storage.clone();
                        let _ = storage.with(|db| -> curio_storage::Result<()> {
                            for c in db.list_conversations(10_000)? {
                                db.delete_conversation(c.id)?;
                            }
                            Ok(())
                        });
                        gpui_kit::component::WindowExt::push_notification(
                            window,
                            "Chats deleted",
                            cx,
                        );
                    }),
                cx,
            ),
            Self::row(
                "What Curio shares with AI providers",
                Some(
                    "Only the pages shown as chips above the message box, and only when you send a message. Passwords and form fields are never read.",
                ),
                div(),
                cx,
            ),
            Self::row(
                "Site permissions",
                Some(
                    "Camera, microphone and location requests are asked by WebKit per site. Links that open other apps always ask first.",
                ),
                div(),
                cx,
            ),
        ]
    }

    fn render_shortcuts(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let theme = *CurioTheme::get(cx);
        let mut rows = vec![
            div()
                .py(px(8.))
                .text_xs()
                .text_color(theme.text_faint)
                .child("Edit a shortcut and press Return. Use names like secondary-t (⌘T), shift-secondary-]. Leave empty to remove. Changes apply after restarting Curio.")
                .into_any_element(),
        ];
        for (name, entity) in &self.shortcut_inputs {
            let label = name.trim_start_matches("curio::");
            let mut pretty = String::with_capacity(label.len() + 8);
            for (i, ch) in label.chars().enumerate() {
                if i > 0 && ch.is_uppercase() {
                    pretty.push(' ');
                }
                pretty.push(ch);
            }
            rows.push(
                h_flex()
                    .py(px(4.))
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .text_sm()
                            .text_color(theme.text)
                            .child(SharedString::from(pretty)),
                    )
                    .child(div().w(px(200.)).child(Input::new(entity).xsmall()))
                    .into_any_element(),
            );
        }
        rows
    }
}

impl Render for SettingsView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let nav = Section::ALL.map(|section| {
            let selected = section == self.section;
            h_flex()
                .id(SharedString::from(format!("settings-{}", section.label())))
                .h(px(32.))
                .px(px(10.))
                .gap(px(8.))
                .rounded(px(8.))
                .text_sm()
                .cursor_pointer()
                .when(selected, |el| {
                    el.bg(theme.accent_soft).text_color(theme.accent_text)
                })
                .when(!selected, |el| {
                    el.text_color(theme.text_muted)
                        .hover(|s| s.bg(theme.row_hover))
                })
                .child(Icon::new(section.icon()).small())
                .child(section.label())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.section = section;
                    cx.notify();
                }))
        });
        let rows = match self.section {
            Section::General => self.render_general(cx),
            Section::Appearance => self.render_appearance(cx),
            Section::Ai => self.render_ai(cx),
            Section::Privacy => self.render_privacy(cx),
            Section::Shortcuts => self.render_shortcuts(cx),
        };
        h_flex()
            .size_full()
            .items_start()
            .gap(px(16.))
            .child(v_flex().w(px(170.)).gap(px(2.)).children(nav))
            .child(
                div()
                    .id("settings-content")
                    .flex_1()
                    .h_full()
                    .overflow_y_scroll()
                    .pr(px(6.))
                    .child(
                        div()
                            .pb(px(6.))
                            .text_lg()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(theme.text)
                            .child(self.section.label()),
                    )
                    .children(rows),
            )
    }
}
