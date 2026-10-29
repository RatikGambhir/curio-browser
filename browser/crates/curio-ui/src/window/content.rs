//! The page area: the web page card, the new tab page, find-in-page and the
//! selection actions.

use std::time::Duration;

use curio_ai::QuickAction;
use curio_core::display_host;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::Input;
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    Animation, AnimationExt as _, AnyElement, Context, FontWeight, InteractiveElement as _,
    IntoElement, ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _,
    Window, deferred, div, px, relative,
};

use super::BrowserWindow;
use crate::actions;
use crate::components::{favicon, logo_mark, shortcut_hint};
use crate::theme::{CurioTheme, metrics};

impl BrowserWindow {
    pub(crate) fn render_content(
        &mut self,
        card_top: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let active = self.workspace.active_tab().cloned();
        let entity = self.active_tab_entity().cloned();
        let state = entity.as_ref().map(|e| e.read(cx).state().clone());
        let webview = entity.as_ref().and_then(|e| e.read(cx).webview().cloned());
        let show_page = active.as_ref().is_some_and(|t| !t.is_new_tab_page()) && webview.is_some();

        let page: AnyElement = match (&active, webview) {
            (Some(tab), Some(webview)) if !tab.is_new_tab_page() => {
                div().size_full().child(webview).into_any_element()
            }
            _ => self.render_new_tab_page(window, cx),
        };

        let loading = show_page && state.as_ref().is_some_and(|s| s.loading);
        let stalled = show_page && state.as_ref().is_some_and(|s| s.stalled);
        let selection = state
            .as_ref()
            .and_then(|s| s.selection.clone())
            .filter(|s| show_page && s.text.chars().count() >= 2 && self.command_mode.is_none());

        let mut card = div()
            .id("page-card")
            .relative()
            .size_full()
            .rounded(metrics::CARD_RADIUS)
            .overflow_hidden()
            .bg(theme.card)
            .border_1()
            .border_color(theme.card_border)
            .shadow_md()
            .child(page);

        if loading {
            card = card.child(deferred(
                div()
                    .absolute()
                    .top_0()
                    .left_0()
                    .w_full()
                    .h(px(2.))
                    .overflow_hidden()
                    .child(
                        div()
                            .h_full()
                            .w(relative(0.35))
                            .bg(theme.accent)
                            .with_animation(
                                "page-loading",
                                Animation::new(Duration::from_millis(1100))
                                    .repeat()
                                    .with_easing(gpui_kit::ease_in_out),
                                |el, t| el.ml(relative(-0.35 + 1.35 * t)),
                            ),
                    ),
            ));
        }
        if stalled {
            card = card.child(deferred(
                h_flex()
                    .absolute()
                    .top(px(12.))
                    .left(px(12.))
                    .right(px(12.))
                    .p(px(10.))
                    .gap(px(10.))
                    .rounded(px(10.))
                    .bg(theme.surface_raised)
                    .border_1()
                    .border_color(theme.surface_border)
                    .shadow_lg()
                    .text_sm()
                    .child(
                        div()
                            .text_color(theme.warning)
                            .child(Icon::new(IconName::TriangleAlert).small()),
                    )
                    .child(div().flex_1().text_color(theme.text).child(
                        "This page didn’t finish loading. Check your connection or the address.",
                    ))
                    .child(
                        Button::new("stalled-retry")
                            .small()
                            .label("Try Again")
                            .on_click(|_, window, cx| {
                                window.dispatch_action(Box::new(actions::Reload), cx)
                            }),
                    ),
            ));
        }
        if self.find.open {
            card = card.child(deferred(self.render_find_bar(cx)));
        }
        if let Some(selection) = selection {
            card = card.child(deferred(self.render_selection_actions(&selection.text, cx)));
        }

        div()
            .flex_1()
            .min_h_0()
            .w_full()
            .pb(metrics::PANEL_GAP)
            .when(!self.ai_open, |el| el.pr(metrics::PANEL_GAP))
            .when(card_top, |el| el.pt(metrics::PANEL_GAP))
            .when(!self.left_column_visible(cx), |el| {
                el.pl(metrics::PANEL_GAP)
            })
            .child(card)
            .into_any_element()
    }

    fn render_new_tab_page(&mut self, _: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let hour = {
            // Local hour is not available without a time zone database; use
            // a neutral greeting.
            None::<u32>
        };
        let greeting = match hour {
            Some(h) if h < 12 => "Good morning",
            Some(h) if h < 18 => "Good afternoon",
            Some(_) => "Good evening",
            None => "Where to next?",
        };
        let space_name = self.workspace.active_space().name.clone();
        let tiles: Vec<AnyElement> = self
            .workspace
            .favorites()
            .iter()
            .map(|f| {
                (
                    f.tab.url.clone(),
                    f.tab.display_title(),
                    f.tab.favicon_url.clone(),
                )
            })
            .chain(self.top_sites.iter().map(|s| {
                (
                    s.url.clone(),
                    if s.title.is_empty() {
                        display_host(&s.url)
                    } else {
                        s.title.clone()
                    },
                    None,
                )
            }))
            .take(8)
            .enumerate()
            .map(|(i, (url, title, icon))| {
                let host = display_host(&url);
                v_flex()
                    .id(SharedString::from(format!("ntp-tile-{i}")))
                    .w(px(96.))
                    .items_center()
                    .gap(px(8.))
                    .py(px(10.))
                    .rounded(px(12.))
                    .cursor_pointer()
                    .hover(|s| s.bg(theme.row_hover))
                    .child(
                        div()
                            .size(px(48.))
                            .rounded(px(14.))
                            .bg(theme.surface_raised)
                            .border_1()
                            .border_color(theme.surface_border)
                            .shadow_xs()
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(favicon(icon.as_deref(), &host, px(24.))),
                    )
                    .child(
                        div()
                            .w_full()
                            .px(px(4.))
                            .text_xs()
                            .text_center()
                            .truncate()
                            .text_color(theme.text_muted)
                            .child(SharedString::from(title)),
                    )
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.navigate_active(&url, window, cx)
                    }))
                    .into_any_element()
            })
            .collect();

        v_flex()
            .id("new-tab-page")
            .size_full()
            .items_center()
            .justify_center()
            .gap(px(22.))
            .px(px(32.))
            .bg(theme.card)
            .child(logo_mark(px(76.)))
            .child(
                v_flex()
                    .items_center()
                    .gap(px(4.))
                    .child(
                        div()
                            .text_size(px(26.))
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(theme.text)
                            .child(greeting),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_color(theme.text_faint)
                            .child(SharedString::from(format!("You’re in {space_name}"))),
                    ),
            )
            .child(
                h_flex()
                    .id("ntp-search")
                    .w_full()
                    .max_w(px(560.))
                    .h(px(50.))
                    .px(px(18.))
                    .gap(px(12.))
                    .rounded(px(14.))
                    .bg(theme.surface)
                    .border_1()
                    .border_color(theme.surface_border)
                    .shadow_sm()
                    .cursor_text()
                    .hover(|s| s.border_color(theme.accent))
                    .text_color(theme.text_faint)
                    .child(Icon::new(IconName::Search).small())
                    .child(
                        div()
                            .flex_1()
                            .text_size(px(15.))
                            .child("Search the web, enter an address, or ask Curio"),
                    )
                    .child(shortcut_hint("⌘T", cx))
                    .on_click(|_, window, cx| {
                        window.dispatch_action(Box::new(actions::EditUrl), cx)
                    }),
            )
            .when(!tiles.is_empty(), |el| {
                el.child(
                    h_flex()
                        .flex_wrap()
                        .justify_center()
                        .gap(px(6.))
                        .max_w(px(640.))
                        .children(tiles),
                )
            })
            .child(
                h_flex()
                    .gap(px(8.))
                    .child(
                        Button::new("ntp-ask")
                            .ghost()
                            .small()
                            .icon(IconName::Sparkles)
                            .label("Ask Curio")
                            .on_click(|_, window, cx| {
                                window.dispatch_action(Box::new(actions::ToggleAiPanel), cx)
                            }),
                    )
                    .child(
                        Button::new("ntp-history")
                            .ghost()
                            .small()
                            .icon(IconName::CalendarClock)
                            .label("History")
                            .on_click(|_, window, cx| {
                                window.dispatch_action(Box::new(actions::ShowHistory), cx)
                            }),
                    ),
            )
            .into_any_element()
    }

    fn render_find_bar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let result = self.find.result;
        let query_empty = self.find.input.read(cx).value().is_empty();
        let status = if query_empty {
            String::new()
        } else if result.matches == 0 {
            "No matches".to_owned()
        } else {
            format!("{} of {}", result.active, result.matches)
        };
        h_flex()
            .id("find-bar")
            .absolute()
            .top(px(10.))
            .right(px(14.))
            .w(px(360.))
            .h(px(42.))
            .px(px(10.))
            .gap(px(6.))
            .rounded(px(12.))
            .bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
            .shadow_lg()
            .child(
                div()
                    .text_color(theme.text_faint)
                    .child(Icon::new(IconName::Search).small()),
            )
            .child(
                div()
                    .flex_1()
                    .child(Input::new(&self.find.input).appearance(false).small()),
            )
            .child(
                div()
                    .text_xs()
                    .text_color(if result.matches == 0 && !query_empty {
                        theme.danger
                    } else {
                        theme.text_faint
                    })
                    .child(SharedString::from(status)),
            )
            .child(
                Button::new("find-prev")
                    .ghost()
                    .xsmall()
                    .icon(IconName::ChevronUp)
                    .on_click(cx.listener(|this, _, window, cx| this.run_find(false, window, cx))),
            )
            .child(
                Button::new("find-next")
                    .ghost()
                    .xsmall()
                    .icon(IconName::ChevronDown)
                    .on_click(cx.listener(|this, _, window, cx| this.run_find(true, window, cx))),
            )
            .child(
                Button::new("find-close")
                    .ghost()
                    .xsmall()
                    .icon(IconName::X)
                    .on_click(cx.listener(|this, _, window, cx| this.close_find(window, cx))),
            )
    }

    /// A floating bar of AI actions for the selected text.
    fn render_selection_actions(&self, text: &str, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let preview: String = text
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .chars()
            .take(42)
            .collect();
        let action = |id: &'static str,
                      icon: IconName,
                      label: &'static str,
                      quick: QuickAction,
                      cx: &mut Context<Self>| {
            h_flex()
                .id(id)
                .h(px(28.))
                .px(px(9.))
                .gap(px(6.))
                .rounded(px(8.))
                .text_xs()
                .font_weight(FontWeight::MEDIUM)
                .text_color(theme.text)
                .cursor_pointer()
                .hover(|s| s.bg(theme.accent_soft).text_color(theme.accent_text))
                .child(Icon::new(icon).xsmall())
                .child(label)
                .on_click(cx.listener(move |this, _, window, cx| {
                    this.ask_about_selection(quick.clone(), window, cx);
                }))
        };
        h_flex()
            .id("selection-actions")
            .absolute()
            .bottom(px(16.))
            .left_0()
            .right_0()
            .justify_center()
            .child(
                h_flex()
                    .p(px(4.))
                    .gap(px(2.))
                    .rounded(px(12.))
                    .bg(theme.surface_raised)
                    .border_1()
                    .border_color(theme.surface_border)
                    .shadow_xl()
                    .child(
                        h_flex()
                            .px(px(8.))
                            .gap(px(6.))
                            .max_w(px(200.))
                            .text_xs()
                            .text_color(theme.text_faint)
                            .child(
                                div()
                                    .text_color(theme.accent_text)
                                    .child(Icon::new(IconName::Sparkles).xsmall()),
                            )
                            .child(
                                div()
                                    .truncate()
                                    .child(SharedString::from(format!("“{preview}”"))),
                            ),
                    )
                    .child(div().w(px(1.)).h(px(18.)).bg(theme.divider))
                    .child(action(
                        "sel-explain",
                        IconName::Lightbulb,
                        "Explain",
                        QuickAction::ExplainSelection,
                        cx,
                    ))
                    .child(action(
                        "sel-summarize",
                        IconName::FileText,
                        "Summarize",
                        QuickAction::SummarizeSelection,
                        cx,
                    ))
                    .child(action(
                        "sel-translate",
                        IconName::Languages,
                        "Translate",
                        QuickAction::TranslateSelection {
                            language: String::new(),
                        },
                        cx,
                    ))
                    .child(
                        h_flex()
                            .id("sel-ask")
                            .h(px(28.))
                            .px(px(9.))
                            .gap(px(6.))
                            .rounded(px(8.))
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(theme.text)
                            .cursor_pointer()
                            .hover(|s| s.bg(theme.accent_soft).text_color(theme.accent_text))
                            .child(Icon::new(IconName::MessageSquare).xsmall())
                            .child("Ask…")
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.send_selection_to_chat(window, cx)
                            })),
                    ),
            )
    }
}
