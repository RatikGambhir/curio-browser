//! AI conversation records shared by the AI subsystem and storage.

use serde::{Deserialize, Serialize};

use crate::ids::{ConversationId, MessageId, SpaceId, TabId};
use crate::time::{Timestamp, now_ms};

/// Who wrote a message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    User,
    Assistant,
}

impl Role {
    /// The storage and wire name.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Assistant => "assistant",
        }
    }
}

/// A web page that was shared with the assistant for one message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContextRef {
    pub title: String,
    pub url: String,
}

/// What browsing context a conversation is associated with, so the user can
/// always see what the assistant had access to.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum ConversationScope {
    /// No web page context.
    #[default]
    None,
    /// A single tab.
    Tab { tab: TabId },
    /// A hand-picked set of tabs.
    Tabs { tabs: Vec<TabId> },
    /// Every tab in a space.
    Space { space: SpaceId },
}

/// One chat message.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: MessageId,
    pub role: Role,
    pub content: String,
    /// Pages attached to this (user) message.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub context: Vec<ContextRef>,
    pub created_at: Timestamp,
    /// Set when generation failed; the content then holds partial output.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl ChatMessage {
    /// Creates a message stamped with the current time.
    #[must_use]
    pub fn new(role: Role, content: impl Into<String>) -> Self {
        Self {
            id: MessageId::new(),
            role,
            content: content.into(),
            context: Vec::new(),
            created_at: now_ms(),
            error: None,
        }
    }
}

/// A conversation with the assistant.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Conversation {
    pub id: ConversationId,
    pub title: String,
    pub scope: ConversationScope,
    pub messages: Vec<ChatMessage>,
    pub created_at: Timestamp,
    pub updated_at: Timestamp,
}

impl Default for Conversation {
    fn default() -> Self {
        let now = now_ms();
        Self {
            id: ConversationId::new(),
            title: "New Chat".to_owned(),
            scope: ConversationScope::None,
            messages: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }
}

impl Conversation {
    /// Derives a short title from the first user message.
    pub fn retitle_from_first_message(&mut self) {
        if let Some(first) = self.messages.iter().find(|m| m.role == Role::User) {
            let line = first.content.lines().next().unwrap_or_default().trim();
            let mut title: String = line.chars().take(48).collect();
            if line.chars().count() > 48 {
                title.push('…');
            }
            if !title.is_empty() {
                self.title = title;
            }
        }
    }
}

/// Summary row for conversation lists.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConversationSummary {
    pub id: ConversationId,
    pub title: String,
    pub updated_at: Timestamp,
    pub message_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retitle_uses_first_line_truncated() {
        let mut conv = Conversation::default();
        conv.messages.push(ChatMessage::new(
            Role::User,
            "Summarize the main arguments of this very long article about browsers\nplease",
        ));
        conv.retitle_from_first_message();
        assert!(conv.title.ends_with('…'));
        assert!(conv.title.chars().count() <= 49);
    }
}
