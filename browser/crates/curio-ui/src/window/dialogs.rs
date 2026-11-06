//! Dialogs: editing spaces and groups, confirmations, history, downloads.

use curio_core::{SpaceGradient, SpaceId, display_host};
use curio_spaces::SPACE_ICONS;
use curio_storage::HistoryEntry;
use gpui_kit::Focusable as _;
use gpui_kit::component::WindowExt as _;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::component::{Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, AppContext as _, Context, Entity, FontWeight, InteractiveElement as _, IntoElement,
    ParentElement as _, Render, SharedString, StatefulInteractiveElement as _, Styled as _,
    Subscription, Window, div, px,
};

use super::BrowserWindow;
use crate::components::prelude::*;
use crate::theme::CurioTheme;
use crate::{Services, settings_view};

/// The space editor shown when creating or customizing a space.
struct SpaceEditor {
    name: Entity<InputState>,
    icon: String,
    gradient: SpaceGradient,
    _subscription: Subscription,
}

impl SpaceEditor {
    fn new(
        name: &str,
        icon: &str,
        gradient: SpaceGradient,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Space name")
                .default_value(name.to_owned())
        });
        let subscription = cx.subscribe(&input, |_, _, _: &InputEvent, cx| cx.notify());
        Self {
            name: input,
            icon: icon.to_owned(),
            gradient,
            _subscription: subscription,
        }
    }

    /// One row of theme tiles.
    fn theme_row(
        &self,
        gradients: [SpaceGradient; 10],
        theme: &CurioTheme,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let tiles = gradients.into_iter().map(|gradient| {
            let selected = self.gradient == gradient;
            // The ring sits outside the tile, so the selected one doesn't shrink.
            div()
                .id(SharedString::from(format!("theme-{}", gradient.label())))
                .flex_1()
                .min_w_0()
                .p(px(2.))
                .rounded(px(9.))
                .border_2()
                .border_color(if selected {
                    theme.accent
                } else {
                    gpui_kit::transparent_black()
                })
                .cursor_pointer()
                .when(!selected, |el| el.hover(|s| s.opacity(0.85)))
                .child(
                    div()
                        .relative()
                        .h(px(26.))
                        .rounded(px(6.))
                        .overflow_hidden()
                        .border_1()
                        .border_color(theme.surface_border)
                        .child(GradientBackdrop::new(gradient).swatch()),
                )
                .tooltip_text(gradient.label())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.gradient = gradient;
                    cx.notify();
                }))
        });
        h_flex().gap(px(2.)).children(tiles)
    }
}

impl Render for SpaceEditor {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let preview = CurioTheme::new(self.gradient);
        let icons = SPACE_ICONS.iter().map(|icon| {
            let selected = self.icon == *icon;
            let value = (*icon).to_owned();
            div()
                .id(SharedString::from(format!("icon-{icon}")))
                .size(px(32.))
                .rounded(px(8.))
                .flex()
                .items_center()
                .justify_center()
                .text_size(px(16.))
                .cursor_pointer()
                .when(selected, |el| {
                    el.bg(theme.accent_soft)
                        .border_1()
                        .border_color(theme.accent)
                })
                .when(!selected, |el| el.hover(|s| s.bg(theme.row_hover)))
                .child(SharedString::from(*icon))
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.icon.clone_from(&value);
                    cx.notify();
                }))
        });
        v_flex()
            .gap(px(14.))
            .child(
                h_flex()
                    .relative()
                    .overflow_hidden()
                    .gap(px(12.))
                    .p(px(12.))
                    .h(px(64.))
                    .rounded(px(12.))
                    .child(GradientBackdrop::new(self.gradient))
                    .child(
                        div()
                            .text_size(px(22.))
                            .child(SharedString::from(self.icon.clone())),
                    )
                    .child(
                        div()
                            .flex_1()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(preview.text)
                            .child(SharedString::from({
                                let name = self.name.read(cx).value().to_string();
                                if name.trim().is_empty() {
                                    "New Space".to_owned()
                                } else {
                                    name
                                }
                            })),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(preview.text_muted)
                            .child(self.gradient.label()),
                    ),
            )
            .child(Input::new(&self.name))
            .child(SectionLabel::new("Icon"))
            .child(h_flex().flex_wrap().gap(px(4.)).children(icons))
            .child(SectionLabel::new("Theme"))
            .child(
                v_flex()
                    .gap(px(4.))
                    .child(self.theme_row(SpaceGradient::LIGHT, &theme, cx))
                    .child(self.theme_row(SpaceGradient::DARK, &theme, cx)),
            )
    }
}

impl BrowserWindow {
    /// Opens the space editor; `None` creates a new space.
    pub(crate) fn edit_space(
        &mut self,
        space: Option<SpaceId>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let (name, icon, gradient) = match space.and_then(|id| self.workspace.space(id)) {
            Some(space) => (space.name.clone(), space.icon.clone(), space.gradient),
            None => {
                let gradient = self
                    .workspace
                    .spaces()
                    .last()
                    .map_or(SpaceGradient::default(), |s| s.gradient.next());
                (
                    String::new(),
                    SPACE_ICONS[(self.workspace.spaces().len() + 3) % SPACE_ICONS.len()].to_owned(),
                    gradient,
                )
            }
        };
        let editor = cx.new(|cx| SpaceEditor::new(&name, &icon, gradient, window, cx));
        let focus = editor.read(cx).name.read(cx).focus_handle(cx);
        window.focus(&focus, cx);
        let this = cx.entity().downgrade();
        let title = if space.is_some() {
            "Edit Space"
        } else {
            "New Space"
        };
        window.open_dialog(cx, move |dialog, _, _| {
            let save_editor = editor.clone();
            let this = this.clone();
            dialog
                .title(title)
                .w(px(420.))
                .child(editor.clone())
                .footer(
                    dialog_footer()
                        .child(
                            Button::new("space-cancel")
                                .label("Cancel")
                                .on_click(|_, window, cx| window.close_dialog(cx)),
                        )
                        .child(
                            Button::new("space-save")
                                .primary()
                                .label(if space.is_some() {
                                    "Save"
                                } else {
                                    "Create Space"
                                })
                                .on_click(move |_, window, cx| {
                                    let editor = save_editor.read(cx);
                                    let name = editor.name.read(cx).value().trim().to_owned();
                                    let name = if name.is_empty() {
                                        "New Space".to_owned()
                                    } else {
                                        name
                                    };
                                    let (icon, gradient) = (editor.icon.clone(), editor.gradient);
                                    let _ = this.update(cx, |this, cx| {
                                        this.save_space(space, &name, &icon, gradient, window, cx);
                                    });
                                    window.close_dialog(cx);
                                }),
                        ),
                )
        });
    }

    fn save_space(
        &mut self,
        space: Option<SpaceId>,
        name: &str,
        icon: &str,
        gradient: SpaceGradient,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match space {
            Some(id) => {
                self.workspace.rename_space(id, name);
                self.workspace.set_space_icon(id, icon);
                self.workspace.set_space_gradient(id, gradient);
                self.apply_theme(window, cx);
            }
            None => {
                let id = self.workspace.create_space(name, icon, Some(gradient));
                self.switch_space(id, window, cx);
                self.open_command_bar(crate::command_bar::CommandMode::NewTab, window, cx);
            }
        }
        self.schedule_save(cx);
        cx.notify();
    }

    pub(crate) fn shift_space(&mut self, space: SpaceId, delta: isize, cx: &mut Context<Self>) {
        if let Some(index) = self.workspace.space_index(space) {
            let target = (index as isize + delta).max(0) as usize;
            self.workspace.move_space(space, target);
            self.schedule_save(cx);
            cx.notify();
        }
    }

    pub(crate) fn confirm_delete_space(
        &mut self,
        space: SpaceId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace.spaces().len() <= 1 {
            window.push_notification("Curio needs at least one space.", cx);
            return;
        }
        let Some(name) = self.workspace.space(space).map(|s| s.name.clone()) else {
            return;
        };
        let tab_count = self.workspace.space(space).map_or(0, |s| s.strip.len());
        let this = cx.entity().downgrade();
        window.open_alert_dialog(cx, move |alert, _, _| {
            let this = this.clone();
            alert
                .title(SharedString::from(format!("Delete “{name}”?")))
                .description(SharedString::from(format!(
                    "Its {tab_count} tabs, pinned tabs and folders will be closed. This can’t be undone."
                )))
                .confirm()
                .ok_text("Delete Space")
                .ok_variant(gpui_kit::component::button::ButtonVariant::Danger)
                .on_ok(move |_, window, cx| {
                    let _ = this.update(cx, |this, cx| this.delete_space(space, window, cx));
                    true
                })
        });
    }

    fn delete_space(&mut self, space: SpaceId, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(removed) = self.workspace.delete_space(space) {
            for tab in removed.strip.tabs() {
                self.release_tab(tab.id);
            }
            self.apply_theme(window, cx);
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    /// Asks before opening a link in another application.
    pub(crate) fn confirm_external_open(
        &mut self,
        url: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let url = url.to_owned();
        let scheme = url.split(':').next().unwrap_or_default().to_owned();
        window.open_alert_dialog(cx, move |alert, _, _| {
            let url = url.clone();
            alert
                .title(SharedString::from(format!(
                    "Open “{scheme}:” link in another app?"
                )))
                .description(SharedString::from(
                    url.chars().take(160).collect::<String>(),
                ))
                .confirm()
                .ok_text("Open")
                .on_ok(move |_, _, cx| {
                    cx.open_url(&url);
                    true
                })
        });
    }

    pub(crate) fn show_about(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let theme = *CurioTheme::get(cx);
        window.open_dialog(cx, move |dialog, _, _| {
            dialog.w(px(380.)).child(
                v_flex()
                    .items_center()
                    .gap(px(10.))
                    .py(px(8.))
                    .child(logo_mark(px(88.)))
                    .child(div().text_size(px(22.)).font_weight(FontWeight::BOLD).child("Curio"))
                    .child(
                        div()
                            .text_sm()
                            .text_color(theme.text_muted)
                            .child(SharedString::from(format!("Version {}", env!("CARGO_PKG_VERSION")))),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_center()
                            .text_color(theme.text_muted)
                            .child("A curious browser: spaces for every part of your life, and an assistant that reads along with you."),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme.text_faint)
                            .child(SharedString::from(format!(
                                "Built with Rust and GPUI · Pages rendered by {}",
                                curio_browser::ENGINE_NAME
                            ))),
                    ),
            )
        });
    }

    pub(crate) fn open_settings(
        &mut self,
        section: Option<settings_view::Section>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let view = cx.new(|cx| settings_view::SettingsView::new(section, window, cx));
        window.open_dialog(cx, move |dialog, _, _| {
            dialog
                .title("Settings")
                .w(px(760.))
                .child(div().w_full().h(px(520.)).child(view.clone()))
        });
    }

    pub(crate) fn show_history(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let storage = Services::get(cx).storage.clone();
        let entries: Vec<HistoryEntry> = storage
            .with(|db| db.recent_history(300))
            .unwrap_or_default();
        let this = cx.entity().downgrade();
        window.open_dialog(cx, move |dialog, _, _| {
            let rows: Vec<AnyElement> = entries
                .iter()
                .enumerate()
                .map(|(i, entry)| {
                    let url = entry.url.clone();
                    let this = this.clone();
                    let title = if entry.title.is_empty() {
                        display_host(&entry.url)
                    } else {
                        entry.title.clone()
                    };
                    ListItem::new(SharedString::from(format!("history-{i}")))
                        .h(px(40.))
                        .leading(Favicon::new(display_host(&entry.url)))
                        .title(title)
                        .subtitle(entry.url.clone())
                        .on_click(move |_, window, cx| {
                            let url = url.clone();
                            let _ = this.update(cx, |this, cx| {
                                this.open_url_in_new_tab(&url, None, true, window, cx);
                            });
                            window.close_dialog(cx);
                        })
                        .into_any_element()
                })
                .collect();
            let clear_this = this.clone();
            let empty = rows.is_empty();
            dialog
                .title("History")
                .w(px(640.))
                .child(
                    div()
                        .id("history-list")
                        .h(px(440.))
                        .overflow_y_scroll()
                        .when(empty, |el| {
                            el.child(EmptyState::new("No history yet.").compact())
                        })
                        .children(rows),
                )
                .footer(
                    h_flex().w_full().justify_between().child(
                        Button::new("clear-history")
                            .danger()
                            .small()
                            .label("Clear All History")
                            .on_click(move |_, window, cx| {
                                let _ = clear_this.update(cx, |_, cx| {
                                    let storage = Services::get(cx).storage.clone();
                                    if let Err(error) = storage.with(|db| db.clear_history()) {
                                        tracing::error!(%error, "could not clear history");
                                    }
                                });
                                window.close_dialog(cx);
                                window.push_notification("History cleared", cx);
                            }),
                    ),
                )
        });
    }

    pub(crate) fn show_downloads(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let storage = Services::get(cx).storage.clone();
        let records = storage.with(|db| db.downloads(100)).unwrap_or_default();
        let theme = *CurioTheme::get(cx);
        window.open_dialog(cx, move |dialog, _, _| {
            let rows: Vec<AnyElement> = records
                .iter()
                .enumerate()
                .map(|(i, record)| super::library::download_row(i, record, &theme))
                .collect();
            let empty = rows.is_empty();
            dialog.title("Downloads").w(px(520.)).child(
                div()
                    .id("downloads-list")
                    .max_h(px(420.))
                    .overflow_y_scroll()
                    .when(empty, |el| {
                        el.child(EmptyState::new("No downloads yet.").compact())
                    })
                    .children(rows),
            )
        });
    }
}
