//! The Curio assistant panel.
//!
//! The panel owns the conversation UI and talks to AI providers through
//! `curio-ai`. It never reads pages itself: when the user sends a message it
//! asks the window for the content of exactly the tabs shown as context chips
//! ([`AiPanelEvent::NeedsContext`]), so the user always sees what is shared.

use std::collections::HashSet;

use curio_ai::{
    AiError, ChatRequest, PageContext, ProviderConfig, QuickAction, StopReason, StreamEvent,
    StreamHandle, WireMessage, build_system_prompt, start_stream,
};
use curio_core::chat::{
    ChatMessage, ContextRef, Conversation, ConversationScope, ConversationSummary, Role,
};
use curio_core::time::now_ms;
use curio_core::{ConversationId, SpaceId, TabId, display_host};
use gpui_kit::assets::IconName;
use gpui_kit::component::Disableable as _;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::clipboard::Clipboard;
use gpui_kit::component::input::{InputEvent, Textarea, TextareaState};
use gpui_kit::component::menu::{DropdownMenu as _, PopupMenuItem};
use gpui_kit::component::text::{TextView, TextViewState};
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, AppContext as _, ClipboardItem, Context, Entity, EventEmitter, FocusHandle,
    Focusable, FontWeight, InteractiveElement as _, IntoElement, ParentElement as _, Render,
    ScrollHandle, SharedString, StatefulInteractiveElement as _, Styled as _, Subscription, Task,
    Window, div, px,
};

use crate::components::{favicon, logo_mark};
use crate::theme::CurioTheme;
use crate::{Services, settings};

/// A tab that can be shared with the assistant.
#[derive(Debug, Clone, PartialEq)]
pub struct ContextTab {
    pub id: TabId,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
}

/// Requests from the panel to the window.
#[derive(Debug, Clone, PartialEq)]
pub enum AiPanelEvent {
    /// Extract these tabs and call [`AiPanel::provide_context`] with `request`.
    NeedsContext {
        request: u64,
        tabs: Vec<TabId>,
    },
    /// Open a link from an answer in a new tab.
    OpenUrl(String),
    OpenSettings,
    Close,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Status {
    Idle,
    Reading,
    Thinking,
    Writing,
}

struct MessageView {
    message: ChatMessage,
    /// Rendered markdown for the message.
    text: Option<Entity<TextViewState>>,
}

/// The assistant panel view.
pub struct AiPanel {
    focus_handle: FocusHandle,
    composer: Entity<TextareaState>,
    conversation: Conversation,
    messages: Vec<MessageView>,
    /// Tabs the user attached explicitly.
    attached: Vec<ContextTab>,
    /// Whether the current tab is attached (it follows tab switches).
    attach_current: bool,
    /// Share every tab of the current space.
    attach_space: bool,
    current_tab: Option<ContextTab>,
    space: Option<(SpaceId, String)>,
    space_tabs: Vec<ContextTab>,
    status: Status,
    pending_request: Option<u64>,
    next_request: u64,
    stream: Option<StreamHandle>,
    stream_task: Task<()>,
    scroll: ScrollHandle,
    history: Vec<ConversationSummary>,
    _subscriptions: Vec<Subscription>,
}

impl EventEmitter<AiPanelEvent> for AiPanel {}

impl Focusable for AiPanel {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl AiPanel {
    /// Creates the panel with an empty conversation.
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let composer = cx.new(|cx| {
            TextareaState::new(window, cx)
                .auto_grow(1, 8)
                .submit_on_enter(true)
                .placeholder("Ask about this page, your tabs, or anything…")
        });
        let subscription =
            cx.subscribe_in(
                &composer,
                window,
                |this, _, event, window, cx| match event {
                    InputEvent::Change => cx.notify(),
                    InputEvent::PressEnter { shift: false, .. } => this.submit(window, cx),
                    _ => {}
                },
            );
        let mut panel = Self {
            focus_handle: cx.focus_handle(),
            composer,
            conversation: Conversation::default(),
            messages: Vec::new(),
            attached: Vec::new(),
            attach_current: settings(cx).ai.auto_attach_current_tab,
            attach_space: false,
            current_tab: None,
            space: None,
            space_tabs: Vec::new(),
            status: Status::Idle,
            pending_request: None,
            next_request: 1,
            stream: None,
            stream_task: Task::ready(()),
            scroll: ScrollHandle::new(),
            history: Vec::new(),
            _subscriptions: vec![subscription],
        };
        panel.reload_history(cx);
        panel
    }

    /// Focuses the message composer.
    pub fn focus_composer(&self, window: &mut Window, cx: &mut App) {
        let handle = self.composer.read(cx).focus_handle(cx);
        window.focus(&handle, cx);
    }

    /// Updates the browsing context offered as chips.
    pub fn set_browsing_context(
        &mut self,
        current: Option<ContextTab>,
        space: (SpaceId, String),
        space_tabs: Vec<ContextTab>,
        cx: &mut Context<Self>,
    ) {
        if self.space.as_ref().map(|s| s.0) != Some(space.0) {
            // A different space: explicit attachments no longer apply.
            self.attached.clear();
            self.attach_space = false;
        }
        let open: HashSet<TabId> = space_tabs.iter().map(|t| t.id).collect();
        self.attached
            .retain(|t| open.contains(&t.id) || Some(t.id) == current.as_ref().map(|c| c.id));
        for tab in &mut self.attached {
            if let Some(updated) = space_tabs.iter().find(|t| t.id == tab.id) {
                *tab = updated.clone();
            }
        }
        self.current_tab = current.filter(|t| t.url.starts_with("http"));
        self.space = Some(space);
        self.space_tabs = space_tabs
            .into_iter()
            .filter(|t| t.url.starts_with("http"))
            .collect();
        cx.notify();
    }

    fn context_tabs(&self) -> Vec<ContextTab> {
        if self.attach_space {
            return self.space_tabs.clone();
        }
        let mut tabs = Vec::new();
        if self.attach_current
            && let Some(current) = &self.current_tab
        {
            tabs.push(current.clone());
        }
        for tab in &self.attached {
            if !tabs.iter().any(|t| t.id == tab.id) {
                tabs.push(tab.clone());
            }
        }
        tabs
    }

    fn is_busy(&self) -> bool {
        self.status != Status::Idle
    }

    /// Starts a new, empty conversation.
    pub fn new_conversation(&mut self, cx: &mut Context<Self>) {
        self.stop(cx);
        self.conversation = Conversation::default();
        self.messages.clear();
        self.attached.clear();
        self.attach_space = false;
        self.attach_current = settings(cx).ai.auto_attach_current_tab;
        cx.notify();
    }

    /// Attaches a tab (used by "Ask Curio about this tab" menus).
    pub fn attach_tab(&mut self, tab: ContextTab, cx: &mut Context<Self>) {
        self.attach_space = false;
        if Some(tab.id) == self.current_tab.as_ref().map(|t| t.id) {
            self.attach_current = true;
        } else if !self.attached.iter().any(|t| t.id == tab.id) {
            self.attached.push(tab);
        }
        cx.notify();
    }

    /// Sends `text` as a user message (from quick actions or the command bar).
    pub fn ask(&mut self, text: &str, window: &mut Window, cx: &mut Context<Self>) {
        self.composer
            .update(cx, |state, cx| state.set_value(text.to_owned(), window, cx));
        self.submit(window, cx);
    }

    /// Runs a quick action on the current page.
    pub fn quick_action(
        &mut self,
        action: &QuickAction,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if matches!(action, QuickAction::CompareTabs) && self.context_tabs().len() < 2 {
            self.attach_space = true;
        } else if !matches!(action, QuickAction::CompareTabs) {
            self.attach_current = true;
        }
        self.ask(&action.prompt(), window, cx);
    }

    /// Asks about selected text, quoting it in the message.
    pub fn ask_about_selection(
        &mut self,
        action: &QuickAction,
        selection: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.attach_current = true;
        let quoted: String = selection
            .trim()
            .chars()
            .take(4_000)
            .collect::<String>()
            .lines()
            .map(|l| format!("> {l}"))
            .collect::<Vec<_>>()
            .join("\n");
        let text = format!("{}\n\n{quoted}", action.prompt());
        self.ask(&text, window, cx);
    }

    /// Puts a quote of `text` in the composer for the user to ask about.
    pub fn prefill_quote(&mut self, text: &str, window: &mut Window, cx: &mut Context<Self>) {
        self.attach_current = true;
        let quoted: String = text
            .trim()
            .chars()
            .take(4_000)
            .collect::<String>()
            .lines()
            .map(|l| format!("> {l}"))
            .collect::<Vec<_>>()
            .join("\n");
        self.composer.update(cx, |state, cx| {
            state.set_value(format!("{quoted}\n\n"), window, cx)
        });
        self.focus_composer(window, cx);
        cx.notify();
    }

    fn submit(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let text = self.composer.read(cx).value().trim().to_owned();
        if text.is_empty() || self.is_busy() {
            return;
        }
        self.composer
            .update(cx, |state, cx| state.set_value(String::new(), window, cx));

        let tabs = self.context_tabs();
        let mut user = ChatMessage::new(Role::User, text);
        user.context = tabs
            .iter()
            .map(|t| ContextRef {
                title: t.title.clone(),
                url: t.url.clone(),
                favicon_url: t.favicon.clone(),
            })
            .collect();
        self.conversation.scope = match (self.attach_space, tabs.as_slice()) {
            (true, _) => self
                .space
                .as_ref()
                .map_or(ConversationScope::None, |(id, _)| {
                    ConversationScope::Space { space: *id }
                }),
            (false, []) => ConversationScope::None,
            (false, [one]) => ConversationScope::Tab { tab: one.id },
            (false, many) => ConversationScope::Tabs {
                tabs: many.iter().map(|t| t.id).collect(),
            },
        };
        self.push_message(user, cx);
        if self.conversation.messages.len() == 1 {
            self.conversation.retitle_from_first_message();
        }

        let request = self.next_request;
        self.next_request += 1;
        self.pending_request = Some(request);
        self.status = Status::Reading;
        self.scroll.scroll_to_bottom();
        cx.notify();
        if tabs.is_empty() {
            self.provide_context(request, Vec::new(), cx);
        } else {
            cx.emit(AiPanelEvent::NeedsContext {
                request,
                tabs: tabs.iter().map(|t| t.id).collect(),
            });
        }
    }

    fn push_message(&mut self, message: ChatMessage, cx: &mut Context<Self>) {
        let text = Some(cx.new(|cx| TextViewState::markdown(message.content.as_str(), cx)));
        self.conversation.messages.push(message.clone());
        self.messages.push(MessageView { message, text });
    }

    /// Continues a pending request once page content has been extracted.
    pub fn provide_context(
        &mut self,
        request: u64,
        pages: Vec<PageContext>,
        cx: &mut Context<Self>,
    ) {
        if self.pending_request != Some(request) {
            return;
        }
        let ai = settings(cx).ai.clone();
        let config = ProviderConfig::from_settings(&ai, &Services::get(cx).secrets);
        let system = build_system_prompt(&pages, ai.max_context_chars);
        let messages: Vec<WireMessage> = self
            .conversation
            .messages
            .iter()
            .filter(|m| m.error.is_none() || !m.content.is_empty())
            .map(|m| WireMessage {
                role: m.role,
                content: m.content.clone(),
            })
            .collect();

        let assistant = ChatMessage::new(Role::Assistant, "");
        self.push_message(assistant, cx);
        self.status = Status::Thinking;

        let handle = start_stream(config, ChatRequest { system, messages });
        let events = handle.events();
        self.stream = Some(handle);
        self.stream_task = cx.spawn(async move |this, cx| {
            while let Ok(event) = events.recv().await {
                let finished = matches!(event, StreamEvent::Done(_) | StreamEvent::Error(_));
                if this
                    .update(cx, |panel, cx| panel.on_stream_event(event, cx))
                    .is_err()
                {
                    break;
                }
                if finished {
                    break;
                }
            }
        });
        cx.notify();
    }

    fn on_stream_event(&mut self, event: StreamEvent, cx: &mut Context<Self>) {
        let Some(view) = self.messages.last_mut() else {
            return;
        };
        match event {
            StreamEvent::Thinking => {
                if self.status != Status::Writing {
                    self.status = Status::Thinking;
                }
            }
            StreamEvent::Text(chunk) => {
                self.status = Status::Writing;
                view.message.content.push_str(&chunk);
                if let Some(text) = &view.text {
                    text.update(cx, |state, cx| state.push_str(&chunk, cx));
                }
                self.scroll.scroll_to_bottom();
            }
            StreamEvent::Done(reason) => {
                let note = match reason {
                    StopReason::MaxTokens => Some("The answer was cut off at the length limit."),
                    StopReason::Refusal => Some("The model declined to answer this request."),
                    StopReason::EndTurn | StopReason::Other(_) => None,
                };
                if let Some(note) = note {
                    view.message.error = Some(note.to_owned());
                }
                self.finish(cx);
            }
            StreamEvent::Error(error) => {
                view.message.error = Some(error.to_string());
                if matches!(error, AiError::MissingApiKey(_)) && view.message.content.is_empty() {
                    view.message.content.clear();
                }
                self.finish(cx);
            }
        }
        cx.notify();
    }

    fn finish(&mut self, cx: &mut Context<Self>) {
        self.status = Status::Idle;
        self.pending_request = None;
        self.stream = None;
        // Keep the conversation record in sync with the views.
        self.conversation.messages = self.messages.iter().map(|m| m.message.clone()).collect();
        self.conversation.updated_at = now_ms();
        self.save(cx);
    }

    /// Stops the current generation, keeping partial output.
    pub fn stop(&mut self, cx: &mut Context<Self>) {
        if let Some(stream) = self.stream.take() {
            stream.cancel();
        }
        if self.is_busy() {
            if let Some(last) = self.messages.last_mut()
                && last.message.role == Role::Assistant
                && last.message.content.is_empty()
            {
                last.message.error = Some("Stopped.".to_owned());
            }
            self.finish(cx);
        }
        self.stream_task = Task::ready(());
        cx.notify();
    }

    fn retry(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.is_busy() {
            return;
        }
        // Drop the failed answer and resend the last user message.
        while self
            .messages
            .last()
            .is_some_and(|m| m.message.role == Role::Assistant)
        {
            self.messages.pop();
        }
        let Some(last_user) = self.messages.pop() else {
            return;
        };
        self.conversation.messages = self.messages.iter().map(|m| m.message.clone()).collect();
        self.composer.update(cx, |state, cx| {
            state.set_value(last_user.message.content, window, cx)
        });
        self.submit(window, cx);
    }

    fn save(&self, cx: &mut Context<Self>) {
        if self.conversation.messages.is_empty() {
            return;
        }
        let conversation = self.conversation.clone();
        let storage = Services::get(cx).storage.clone();
        let task =
            cx.background_spawn(
                async move { storage.with(|db| db.save_conversation(&conversation)) },
            );
        cx.spawn(async move |this, cx| {
            if let Err(error) = task.await {
                tracing::error!(%error, "could not save conversation");
            }
            let _ = this.update(cx, |this, cx| this.reload_history(cx));
        })
        .detach();
    }

    fn reload_history(&mut self, cx: &mut Context<Self>) {
        let storage = Services::get(cx).storage.clone();
        let task = cx.background_spawn(async move { storage.with(|db| db.list_conversations(30)) });
        cx.spawn(async move |this, cx| {
            if let Ok(history) = task.await {
                let _ = this.update(cx, |this, cx| {
                    this.history = history;
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn open_conversation(&mut self, id: ConversationId, cx: &mut Context<Self>) {
        self.stop(cx);
        let storage = Services::get(cx).storage.clone();
        let task = cx.background_spawn(async move { storage.with(|db| db.load_conversation(id)) });
        cx.spawn(async move |this, cx| {
            if let Ok(Some(conversation)) = task.await {
                let _ = this.update(cx, |this, cx| {
                    this.messages.clear();
                    this.conversation = Conversation {
                        messages: Vec::new(),
                        ..conversation.clone()
                    };
                    for message in conversation.messages {
                        this.push_message(message, cx);
                    }
                    this.scroll.scroll_to_bottom();
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn delete_conversation(&mut self, id: ConversationId, cx: &mut Context<Self>) {
        let storage = Services::get(cx).storage.clone();
        if self.conversation.id == id {
            self.new_conversation(cx);
        }
        let task =
            cx.background_spawn(async move { storage.with(|db| db.delete_conversation(id)) });
        cx.spawn(async move |this, cx| {
            let _ = task.await;
            let _ = this.update(cx, |this, cx| this.reload_history(cx));
        })
        .detach();
    }

    // ----- Rendering ------------------------------------------------------

    fn render_header(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let history = self.history.clone();
        let entity = cx.entity().downgrade();
        let title = if self.messages.is_empty() {
            SharedString::from("Curio Assistant")
        } else {
            SharedString::from(self.conversation.title.clone())
        };
        h_flex()
            .h(px(46.))
            .px(px(12.))
            .gap(px(8.))
            .border_b_1()
            .border_color(theme.divider)
            .child(logo_mark(px(20.)))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .text_sm()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme.text)
                    .child(title),
            )
            .child(
                Button::new("ai-history")
                    .ghost()
                    .small()
                    .icon(IconName::CalendarClock)
                    .tooltip("Chat history")
                    .dropdown_menu(move |mut menu, _, _| {
                        if history.is_empty() {
                            return menu.label("No previous chats");
                        }
                        for summary in &history {
                            let id = summary.id;
                            let open = entity.clone();
                            menu = menu.item(
                                PopupMenuItem::new(SharedString::from(summary.title.clone()))
                                    .icon(IconName::MessageSquare)
                                    .on_click(move |_, _, cx| {
                                        let _ = open.update(cx, |panel, cx| {
                                            panel.open_conversation(id, cx)
                                        });
                                    }),
                            );
                        }
                        let clear = entity.clone();
                        let ids: Vec<ConversationId> = history.iter().map(|h| h.id).collect();
                        menu.separator().item(
                            PopupMenuItem::new("Delete All Chats")
                                .icon(IconName::Delete)
                                .on_click(move |_, _, cx| {
                                    let _ = clear.update(cx, |panel, cx| {
                                        for id in &ids {
                                            panel.delete_conversation(*id, cx);
                                        }
                                    });
                                }),
                        )
                    }),
            )
            .child(
                Button::new("ai-new")
                    .ghost()
                    .small()
                    .icon(IconName::SquarePen)
                    .tooltip("New chat")
                    .on_click(cx.listener(|this, _, _, cx| this.new_conversation(cx))),
            )
            .child(
                Button::new("ai-close")
                    .ghost()
                    .small()
                    .icon(IconName::PanelRightClose)
                    .tooltip("Close assistant")
                    .on_click(cx.listener(|_, _, _, cx| cx.emit(AiPanelEvent::Close))),
            )
    }

    fn render_empty(&self, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let has_page = self.current_tab.is_some();
        let has_tabs = self.space_tabs.len() >= 2;
        let config_ready =
            ProviderConfig::from_settings(&settings(cx).ai, &Services::get(cx).secrets).is_ready();
        let suggestion = |id: &'static str,
                          icon: IconName,
                          label: &'static str,
                          action: QuickAction,
                          cx: &mut Context<Self>| {
            h_flex()
                .id(id)
                .gap(px(8.))
                .px(px(12.))
                .h(px(34.))
                .rounded(px(9.))
                .border_1()
                .border_color(theme.surface_border)
                .bg(theme.surface_raised)
                .text_sm()
                .text_color(theme.text)
                .cursor_pointer()
                .hover(|s| s.bg(theme.accent_soft).border_color(theme.accent_soft))
                .child(
                    div()
                        .text_color(theme.accent_text)
                        .child(Icon::new(icon).small()),
                )
                .child(label)
                .on_click(
                    cx.listener(move |this, _, window, cx| this.quick_action(&action, window, cx)),
                )
        };
        v_flex()
            .flex_1()
            .items_center()
            .justify_center()
            .gap(px(14.))
            .px(px(24.))
            .child(logo_mark(px(52.)))
            .child(
                div()
                    .text_lg()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme.text)
                    .child("What are you curious about?"),
            )
            .child(
                div()
                    .text_sm()
                    .text_center()
                    .text_color(theme.text_muted)
                    .child("Ask about this page, compare your open tabs, or explore anything. Pages are shared only when shown below the message box."),
            )
            .when(!config_ready, |el| {
                el.child(
                    v_flex()
                        .gap(px(8.))
                        .items_center()
                        .p(px(12.))
                        .rounded(px(10.))
                        .bg(theme.accent_soft)
                        .child(
                            div()
                                .text_sm()
                                .text_color(theme.text)
                                .child("Connect an AI provider to start chatting."),
                        )
                        .child(
                            Button::new("ai-setup")
                                .primary()
                                .small()
                                .label("Set Up AI…")
                                .on_click(cx.listener(|_, _, _, cx| cx.emit(AiPanelEvent::OpenSettings))),
                        ),
                )
            })
            .child(
                v_flex()
                    .gap(px(8.))
                    .w_full()
                    .max_w(px(320.))
                    .when(has_page, |el| {
                        el.child(suggestion("qa-sum", IconName::FileText, "Summarize this page", QuickAction::SummarizePage, cx))
                            .child(suggestion("qa-key", IconName::List, "What are the key points?", QuickAction::KeyPoints, cx))
                    })
                    .when(has_tabs, |el| {
                        el.child(suggestion("qa-cmp", IconName::Columns2, "Compare my open tabs", QuickAction::CompareTabs, cx))
                    }),
            )
            .into_any_element()
    }

    fn render_message(
        &self,
        index: usize,
        view: &MessageView,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let message = &view.message;
        match message.role {
            Role::User => v_flex()
                .w_full()
                .items_end()
                .gap(px(6.))
                .child(
                    div()
                        .max_w(gpui_kit::relative(0.88))
                        .px(px(12.))
                        .py(px(8.))
                        .rounded(px(14.))
                        .rounded_br(px(4.))
                        .bg(theme.user_bubble)
                        .text_color(theme.user_bubble_text)
                        .text_sm()
                        .when_some(view.text.clone(), |el, text| {
                            el.child(TextView::new(&text).selectable(true))
                        }),
                )
                .when(!message.context.is_empty(), |el| {
                    el.child(
                        h_flex()
                            .flex_wrap()
                            .justify_end()
                            .gap(px(4.))
                            .children(message.context.iter().take(6).map(|c| {
                                h_flex()
                                    .gap(px(4.))
                                    .px(px(6.))
                                    .h(px(20.))
                                    .rounded(px(6.))
                                    .bg(theme.row_hover)
                                    .text_xs()
                                    .text_color(theme.text_faint)
                                    .child(favicon(
                                        c.favicon_url.as_deref(),
                                        &display_host(&c.url),
                                        px(12.),
                                    ))
                                    .child(
                                        div()
                                            .max_w(px(140.))
                                            .truncate()
                                            .child(SharedString::from(c.title.clone())),
                                    )
                            }))
                            .when(message.context.len() > 6, |el| {
                                el.child(div().text_xs().text_color(theme.text_faint).child(
                                    SharedString::from(format!("+{}", message.context.len() - 6)),
                                ))
                            }),
                    )
                })
                .into_any_element(),
            Role::Assistant => {
                let is_last = index + 1 == self.messages.len();
                let streaming = is_last && self.is_busy();
                let content = message.content.clone();
                let link_target = cx.entity().downgrade();
                v_flex()
                    .w_full()
                    .gap(px(6.))
                    .when(streaming && content.is_empty(), |el| {
                        el.child(
                            h_flex()
                                .gap(px(8.))
                                .text_sm()
                                .text_color(theme.text_muted)
                                .child(
                                    gpui_kit::component::spinner::Spinner::new()
                                        .small()
                                        .color(theme.accent),
                                )
                                .child(match self.status {
                                    Status::Reading => "Reading your tabs…",
                                    Status::Thinking => "Thinking…",
                                    _ => "Writing…",
                                }),
                        )
                    })
                    .when_some(view.text.clone(), |el, text| {
                        el.child(
                            div().text_sm().text_color(theme.text).child(
                                TextView::new(&text)
                                    .selectable(true)
                                    .stream_fade(true)
                                    .code_block_actions(|block, _, _| {
                                        Clipboard::new(SharedString::from(format!(
                                            "copy-{:p}",
                                            block
                                        )))
                                        .value(block.code().to_string())
                                    })
                                    .on_link_click(move |url, _, _, cx| {
                                        let url = url.to_string();
                                        let _ = link_target.update(cx, |_, cx| {
                                            cx.emit(AiPanelEvent::OpenUrl(url))
                                        });
                                    }),
                            ),
                        )
                    })
                    .when_some(message.error.clone(), |el, error| {
                        el.child(
                            h_flex()
                                .gap(px(8.))
                                .p(px(8.))
                                .rounded(px(8.))
                                .bg(gpui_kit::Hsla {
                                    a: 0.10,
                                    ..theme.danger
                                })
                                .text_xs()
                                .text_color(theme.danger)
                                .child(Icon::new(IconName::TriangleAlert).xsmall())
                                .child(div().flex_1().child(SharedString::from(error)))
                                .when(is_last && !self.is_busy(), |el| {
                                    el.child(
                                        Button::new(SharedString::from(format!("retry-{index}")))
                                            .ghost()
                                            .xsmall()
                                            .label("Retry")
                                            .on_click(cx.listener(|this, _, window, cx| {
                                                this.retry(window, cx)
                                            })),
                                    )
                                }),
                        )
                    })
                    .when(!streaming && !content.is_empty(), |el| {
                        el.child(
                            h_flex().gap(px(2.)).child(
                                Button::new(SharedString::from(format!("copy-msg-{index}")))
                                    .ghost()
                                    .xsmall()
                                    .icon(IconName::Copy)
                                    .tooltip("Copy answer")
                                    .on_click(move |_, _, cx| {
                                        cx.write_to_clipboard(ClipboardItem::new_string(
                                            content.clone(),
                                        ));
                                    }),
                            ),
                        )
                    })
                    .into_any_element()
            }
        }
    }

    fn render_context_bar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let tabs = self.context_tabs();
        let chip = |id: SharedString, icon: AnyElement, label: SharedString, active: bool| {
            h_flex()
                .id(id)
                .gap(px(5.))
                .pl(px(6.))
                .pr(px(4.))
                .h(px(24.))
                .rounded(px(7.))
                .border_1()
                .border_color(if active {
                    theme.accent_soft
                } else {
                    theme.surface_border
                })
                .bg(if active {
                    theme.accent_soft
                } else {
                    theme.surface_raised
                })
                .text_xs()
                .text_color(if active {
                    theme.accent_text
                } else {
                    theme.text_muted
                })
                .child(icon)
                .child(div().max_w(px(150.)).truncate().child(label))
        };
        let mut row = h_flex().flex_wrap().gap(px(5.)).w_full();
        if self.attach_space {
            let name = self
                .space
                .as_ref()
                .map_or("this space".to_owned(), |s| s.1.clone());
            row = row.child(
                chip(
                    "ctx-space".into(),
                    Icon::new(IconName::LayoutDashboard)
                        .xsmall()
                        .into_any_element(),
                    SharedString::from(format!("All {} tabs in {name}", self.space_tabs.len())),
                    true,
                )
                .child(
                    div()
                        .id("ctx-space-x")
                        .cursor_pointer()
                        .child(Icon::new(IconName::X).xsmall())
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.attach_space = false;
                            cx.notify();
                        })),
                ),
            );
        } else {
            for tab in &tabs {
                let id = tab.id;
                let is_current = Some(id) == self.current_tab.as_ref().map(|t| t.id);
                row = row.child(
                    chip(
                        SharedString::from(format!("ctx-{id}")),
                        favicon(tab.favicon.as_deref(), &tab.title, px(12.)),
                        SharedString::from(if tab.title.is_empty() {
                            display_host(&tab.url)
                        } else {
                            tab.title.clone()
                        }),
                        true,
                    )
                    .tooltip({
                        let url = SharedString::from(tab.url.clone());
                        move |window, cx| {
                            gpui_kit::component::tooltip::Tooltip::new(url.clone())
                                .build(window, cx)
                        }
                    })
                    .child(
                        div()
                            .id(SharedString::from(format!("ctx-x-{id}")))
                            .cursor_pointer()
                            .child(Icon::new(IconName::X).xsmall())
                            .on_click(cx.listener(move |this, _, _, cx| {
                                if is_current {
                                    this.attach_current = false;
                                }
                                this.attached.retain(|t| t.id != id);
                                cx.notify();
                            })),
                    ),
                );
            }
            if !self.attach_current
                && let Some(current) = &self.current_tab
            {
                let label = SharedString::from(format!("Add {}", display_host(&current.url)));
                row = row.child(
                    chip(
                        "ctx-add-current".into(),
                        Icon::new(IconName::Plus).xsmall().into_any_element(),
                        label,
                        false,
                    )
                    .cursor_pointer()
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.attach_current = true;
                        cx.notify();
                    })),
                );
            }
        }
        // Tab picker.
        let entity = cx.entity().downgrade();
        let space_tabs = self.space_tabs.clone();
        let selected: HashSet<TabId> = tabs.iter().map(|t| t.id).collect();
        row.child(
            Button::new("ctx-picker")
                .ghost()
                .xsmall()
                .icon(IconName::Paperclip)
                .label("Tabs")
                .dropdown_menu(move |mut menu, _, _| {
                    let all = entity.clone();
                    menu = menu.item(
                        PopupMenuItem::new("All tabs in this space")
                            .icon(IconName::LayoutDashboard)
                            .on_click(move |_, _, cx| {
                                let _ = all.update(cx, |panel, cx| {
                                    panel.attach_space = true;
                                    cx.notify();
                                });
                            }),
                    );
                    let none = entity.clone();
                    menu = menu.item(
                        PopupMenuItem::new("No page context")
                            .icon(IconName::CircleX)
                            .on_click(move |_, _, cx| {
                                let _ = none.update(cx, |panel, cx| {
                                    panel.attach_space = false;
                                    panel.attach_current = false;
                                    panel.attached.clear();
                                    cx.notify();
                                });
                            }),
                    );
                    menu = menu.separator();
                    for tab in &space_tabs {
                        let tab = tab.clone();
                        let checked = selected.contains(&tab.id);
                        let toggle = entity.clone();
                        menu = menu.item(
                            PopupMenuItem::new(SharedString::from(if tab.title.is_empty() {
                                display_host(&tab.url)
                            } else {
                                tab.title.chars().take(48).collect()
                            }))
                            .checked(checked)
                            .on_click(move |_, _, cx| {
                                let tab = tab.clone();
                                let _ = toggle.update(cx, |panel, cx| {
                                    panel.attach_space = false;
                                    let is_current =
                                        Some(tab.id) == panel.current_tab.as_ref().map(|t| t.id);
                                    if checked {
                                        if is_current {
                                            panel.attach_current = false;
                                        }
                                        panel.attached.retain(|t| t.id != tab.id);
                                    } else if is_current {
                                        panel.attach_current = true;
                                    } else {
                                        panel.attached.push(tab);
                                    }
                                    cx.notify();
                                });
                            }),
                        );
                    }
                    menu.max_h(px(360.)).scrollable(true)
                }),
        )
    }

    fn render_composer(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let busy = self.is_busy();
        let ai = settings(cx).ai.clone();
        let model = ai.model(ai.provider);
        let empty = self.composer.read(cx).value().trim().is_empty();
        v_flex()
            .m(px(10.))
            .mt(px(4.))
            .p(px(8.))
            .gap(px(6.))
            .rounded(px(14.))
            .bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
            .shadow_sm()
            .child(self.render_context_bar(cx))
            .child(div().child(Textarea::new(&self.composer).appearance(false)))
            .child(
                h_flex()
                    .gap(px(6.))
                    .child(
                        div()
                            .flex_1()
                            .text_xs()
                            .text_color(theme.text_faint)
                            .truncate()
                            .child(SharedString::from(format!(
                                "{} · {model}",
                                ai.provider.label()
                            ))),
                    )
                    .child(if busy {
                        Button::new("ai-stop")
                            .small()
                            .icon(IconName::Square)
                            .tooltip("Stop")
                            .on_click(cx.listener(|this, _, _, cx| this.stop(cx)))
                    } else {
                        Button::new("ai-send")
                            .primary()
                            .small()
                            .icon(IconName::ArrowUp)
                            .tooltip("Send (⏎)")
                            .disabled(empty)
                            .on_click(cx.listener(|this, _, window, cx| this.submit(window, cx)))
                    }),
            )
    }
}

impl Render for AiPanel {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let body: AnyElement = if self.messages.is_empty() {
            self.render_empty(cx)
        } else {
            let rows: Vec<AnyElement> = self
                .messages
                .iter()
                .enumerate()
                .map(|(i, m)| self.render_message(i, m, cx))
                .collect();
            div()
                .id("ai-messages")
                .flex_1()
                .overflow_y_scroll()
                .track_scroll(&self.scroll)
                .child(v_flex().gap(px(16.)).p(px(14.)).children(rows))
                .into_any_element()
        };
        v_flex()
            .id("ai-panel")
            .track_focus(&self.focus_handle)
            .size_full()
            .bg(theme.surface)
            .child(self.render_header(cx))
            .child(body)
            .child(self.render_composer(cx))
    }
}
