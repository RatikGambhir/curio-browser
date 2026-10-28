//! The synchronous SQLite database.

use std::collections::HashMap;
use std::path::Path;

use curio_core::chat::{
    ChatMessage, ContextRef, Conversation, ConversationScope, ConversationSummary, Role,
};
use curio_core::time::{Timestamp, now_ms};
use curio_core::{
    AccentColor, ConversationId, Favorite, FavoriteId, GroupId, SpaceId, Tab, TabGroup, TabId,
};
use curio_settings::Settings;
use curio_spaces::{Space, Workspace};
use curio_tabs::{Item, TabStrip};
use rusqlite::{Connection, OptionalExtension, params};

use crate::{Result, StorageError, migrations};

/// A history entry aggregated by URL.
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryEntry {
    pub url: String,
    pub title: String,
    pub visit_count: u32,
    pub last_visit: Timestamp,
}

/// A bookmark.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bookmark {
    pub url: String,
    pub title: String,
    pub created_at: Timestamp,
}

/// A remembered per-site permission decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionDecision {
    Allow,
    Deny,
}

impl PermissionDecision {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Deny => "deny",
        }
    }
}

/// A download record.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DownloadRecord {
    pub id: i64,
    pub url: String,
    pub path: Option<String>,
    /// `in_progress`, `completed` or `failed`.
    pub state: String,
    pub started_at: Timestamp,
    pub finished_at: Option<Timestamp>,
}

/// The Curio database.
pub struct Database {
    conn: Connection,
}

fn enum_str<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_default()
}

fn parse_enum<T: serde::de::DeserializeOwned + Default>(value: &str) -> T {
    serde_json::from_value(serde_json::Value::String(value.to_owned())).unwrap_or_default()
}

fn parse_id<T: std::str::FromStr>(value: &str) -> Result<T> {
    value
        .parse()
        .map_err(|_| StorageError::Corrupt(format!("invalid id {value:?}")))
}

impl Database {
    /// Opens or creates the database at `path` and migrates it.
    ///
    /// # Errors
    /// Fails when SQLite cannot open the file or a migration fails.
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)?;
        Self::init(conn)
    }

    /// Opens a private in-memory database (for tests).
    ///
    /// # Errors
    /// Fails when a migration fails.
    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(mut conn: Connection) -> Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        migrations::migrate(&mut conn)?;
        Ok(Self { conn })
    }

    // ----- Key/value ----------------------------------------------------

    /// Reads a small value from the key/value table.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn kv_get(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM kv WHERE key = ?1", [key], |r| r.get(0))
            .optional()?)
    }

    /// Writes a small value to the key/value table.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn kv_set(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO kv (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    // ----- Settings -----------------------------------------------------

    /// Loads settings, or defaults when none were saved.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn load_settings(&self) -> Result<Settings> {
        let json: Option<String> = self
            .conn
            .query_row("SELECT json FROM settings WHERE id = 1", [], |r| r.get(0))
            .optional()?;
        Ok(json
            .map(|j| Settings::from_json(&j))
            .unwrap_or_default()
            .sanitized())
    }

    /// Saves settings.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn save_settings(&self, settings: &Settings) -> Result<()> {
        self.conn.execute(
            "INSERT INTO settings (id, json) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET json = excluded.json",
            [settings.to_json()],
        )?;
        Ok(())
    }

    // ----- Workspace ----------------------------------------------------

    /// Replaces the stored workspace (spaces, tabs, groups, layout and
    /// favorites) in a single transaction.
    ///
    /// # Errors
    /// Fails on SQLite errors; the previous snapshot is kept in that case.
    pub fn save_workspace(&mut self, workspace: &Workspace) -> Result<()> {
        let tx = self.conn.transaction()?;
        tx.execute_batch(
            "DELETE FROM spaces; DELETE FROM tabs; DELETE FROM tab_groups;
             DELETE FROM layout; DELETE FROM favorites;",
        )?;
        {
            let mut insert_space = tx.prepare(
                "INSERT INTO spaces (id, position, name, icon, color, active_tab)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            let mut insert_tab = tx.prepare(
                "INSERT INTO tabs (id, owner_kind, owner_id, url, title, favicon_url, home_url,
                                   scroll_y, created_at, last_active_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            )?;
            let mut insert_group = tx.prepare(
                "INSERT INTO tab_groups (id, space_id, name, color, collapsed)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
            )?;
            let mut insert_layout = tx.prepare(
                "INSERT INTO layout (space_id, section, parent_group, position, item_kind, item_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            let mut insert_favorite =
                tx.prepare("INSERT INTO favorites (id, position) VALUES (?1, ?2)")?;

            let mut write_tab = |tab: &Tab, kind: &str, owner: String| -> rusqlite::Result<()> {
                insert_tab.execute(params![
                    tab.id.to_string(),
                    kind,
                    owner,
                    tab.url,
                    tab.title,
                    tab.favicon_url,
                    tab.home_url,
                    tab.scroll_y,
                    tab.created_at,
                    tab.last_active_at,
                ])?;
                Ok(())
            };

            for (position, space) in workspace.spaces().iter().enumerate() {
                let space_id = space.id.to_string();
                insert_space.execute(params![
                    space_id,
                    position as i64,
                    space.name,
                    space.icon,
                    enum_str(&space.color),
                    space.active_tab.map(|t| t.to_string()),
                ])?;
                let (tabs, groups, pinned, unpinned) = space.strip.parts();
                for tab in tabs {
                    write_tab(tab, "space", space_id.clone())?;
                }
                for group in groups {
                    insert_group.execute(params![
                        group.id.to_string(),
                        space_id,
                        group.name,
                        enum_str(&group.color),
                        group.collapsed,
                    ])?;
                    for (position, tab) in group.tabs.iter().enumerate() {
                        insert_layout.execute(params![
                            space_id,
                            "pinned", // section of members is implied by the group
                            group.id.to_string(),
                            position as i64,
                            "tab",
                            tab.to_string(),
                        ])?;
                    }
                }
                for (section, items) in [("pinned", pinned), ("unpinned", unpinned)] {
                    for (position, item) in items.iter().enumerate() {
                        let (kind, id) = match item {
                            Item::Tab(id) => ("tab", id.to_string()),
                            Item::Group(id) => ("group", id.to_string()),
                        };
                        insert_layout.execute(params![
                            space_id,
                            section,
                            Option::<String>::None,
                            position as i64,
                            kind,
                            id,
                        ])?;
                    }
                }
            }
            for (position, favorite) in workspace.favorites().iter().enumerate() {
                insert_favorite.execute(params![favorite.id.to_string(), position as i64])?;
                write_tab(&favorite.tab, "favorite", favorite.id.to_string())?;
            }
        }
        tx.execute(
            "INSERT INTO kv (key, value) VALUES ('active_space', ?1)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [workspace.active_space_id().to_string()],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Loads the stored workspace, or `None` when nothing was saved yet.
    ///
    /// # Errors
    /// Fails on SQLite errors or unparseable identifiers.
    pub fn load_workspace(&self) -> Result<Option<Workspace>> {
        // Tabs by owner.
        let mut tabs_by_owner: HashMap<String, Vec<Tab>> = HashMap::new();
        {
            let mut stmt = self.conn.prepare(
                "SELECT id, owner_id, url, title, favicon_url, home_url, scroll_y,
                        created_at, last_active_at FROM tabs",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, Option<String>>(4)?,
                    r.get::<_, Option<String>>(5)?,
                    r.get::<_, f64>(6)?,
                    r.get::<_, i64>(7)?,
                    r.get::<_, i64>(8)?,
                ))
            })?;
            for row in rows {
                let (
                    id,
                    owner,
                    url,
                    title,
                    favicon_url,
                    home_url,
                    scroll_y,
                    created_at,
                    last_active_at,
                ) = row?;
                tabs_by_owner.entry(owner).or_default().push(Tab {
                    id: parse_id(&id)?,
                    url,
                    title,
                    favicon_url,
                    home_url,
                    scroll_y,
                    created_at,
                    last_active_at,
                });
            }
        }

        // Groups by space.
        let mut groups_by_space: HashMap<String, Vec<TabGroup>> = HashMap::new();
        {
            let mut stmt = self
                .conn
                .prepare("SELECT id, space_id, name, color, collapsed FROM tab_groups")?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, bool>(4)?,
                ))
            })?;
            for row in rows {
                let (id, space, name, color, collapsed) = row?;
                groups_by_space.entry(space).or_default().push(TabGroup {
                    id: parse_id(&id)?,
                    name,
                    color: parse_enum::<AccentColor>(&color),
                    collapsed,
                    tabs: Vec::new(),
                });
            }
        }

        // Layout rows, ordered.
        type LayoutRow = (String, String, Option<String>, String, String);
        let mut layout: Vec<LayoutRow> = Vec::new();
        {
            let mut stmt = self.conn.prepare(
                "SELECT space_id, section, parent_group, item_kind, item_id
                 FROM layout ORDER BY space_id, parent_group, position",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
            })?;
            for row in rows {
                layout.push(row?);
            }
        }

        let mut spaces = Vec::new();
        {
            let mut stmt = self.conn.prepare(
                "SELECT id, name, icon, color, active_tab FROM spaces ORDER BY position",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, Option<String>>(4)?,
                ))
            })?;
            for row in rows {
                let (id, name, icon, color, active_tab) = row?;
                let mut groups = groups_by_space.remove(&id).unwrap_or_default();
                let mut pinned = Vec::new();
                let mut unpinned = Vec::new();
                for (_, section, parent, kind, item) in layout.iter().filter(|l| l.0 == id) {
                    match parent {
                        Some(group_id) => {
                            let group_id: GroupId = parse_id(group_id)?;
                            if let Some(group) = groups.iter_mut().find(|g| g.id == group_id) {
                                group.tabs.push(parse_id(item)?);
                            }
                        }
                        None => {
                            let item = match kind.as_str() {
                                "group" => Item::Group(parse_id(item)?),
                                _ => Item::Tab(parse_id(item)?),
                            };
                            match section.as_str() {
                                "pinned" => pinned.push(item),
                                _ => unpinned.push(item),
                            }
                        }
                    }
                }
                let tabs = tabs_by_owner.remove(&id).unwrap_or_default();
                let strip = TabStrip::from_parts(tabs, groups, pinned, unpinned);
                let active_tab = active_tab.as_deref().map(parse_id::<TabId>).transpose()?;
                spaces.push(Space {
                    id: parse_id::<SpaceId>(&id)?,
                    name,
                    icon,
                    color: parse_enum::<AccentColor>(&color),
                    strip,
                    active_tab,
                });
            }
        }
        if spaces.is_empty() {
            return Ok(None);
        }

        let mut favorites = Vec::new();
        {
            let mut stmt = self
                .conn
                .prepare("SELECT id FROM favorites ORDER BY position")?;
            let ids: Vec<String> = stmt
                .query_map([], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?;
            for id in ids {
                if let Some(tab) = tabs_by_owner.remove(&id).and_then(|mut t| t.pop()) {
                    favorites.push(Favorite {
                        id: parse_id::<FavoriteId>(&id)?,
                        tab,
                    });
                }
            }
        }

        let mut workspace = Workspace::with_spaces(spaces, favorites);
        if let Some(active) = self.kv_get("active_space")?
            && let Ok(active) = active.parse::<SpaceId>()
        {
            workspace.restore_active_space(active);
        }
        Ok(Some(workspace))
    }

    // ----- History ------------------------------------------------------

    /// Records a visit.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn record_visit(&self, url: &str, title: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO history (url, title, visited_at) VALUES (?1, ?2, ?3)",
            params![url, title, now_ms()],
        )?;
        Ok(())
    }

    /// Updates the title of the latest visit to `url` (titles usually arrive
    /// after the navigation is recorded).
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn update_history_title(&self, url: &str, title: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE history SET title = ?2
             WHERE id = (SELECT id FROM history WHERE url = ?1 ORDER BY visited_at DESC LIMIT 1)",
            params![url, title],
        )?;
        Ok(())
    }

    /// Searches history by URL or title, ranking frequently and recently
    /// visited pages first.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn search_history(&self, query: &str, limit: usize) -> Result<Vec<HistoryEntry>> {
        let pattern = format!(
            "%{}%",
            query
                .trim()
                .replace('\\', "\\\\")
                .replace('%', "\\%")
                .replace('_', "\\_")
        );
        let mut stmt = self.conn.prepare(
            "SELECT url, (SELECT title FROM history h2 WHERE h2.url = h.url AND h2.title != ''
                          ORDER BY visited_at DESC LIMIT 1),
                    COUNT(*) AS visits, MAX(visited_at) AS last
             FROM history h
             WHERE url LIKE ?1 ESCAPE '\\' OR title LIKE ?1 ESCAPE '\\'
             GROUP BY url
             ORDER BY visits * 1.0 / (1 + (?3 - last) / 86400000.0) DESC
             LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![pattern, limit as i64, now_ms()], Self::history_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Most recent history, newest first, one row per visit.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn recent_history(&self, limit: usize) -> Result<Vec<HistoryEntry>> {
        let mut stmt = self.conn.prepare(
            "SELECT url, title, 1, visited_at FROM history ORDER BY visited_at DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], Self::history_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    fn history_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<HistoryEntry> {
        Ok(HistoryEntry {
            url: r.get(0)?,
            title: r.get::<_, Option<String>>(1)?.unwrap_or_default(),
            visit_count: u32::try_from(r.get::<_, i64>(2)?).unwrap_or(u32::MAX),
            last_visit: r.get(3)?,
        })
    }

    /// Deletes every visit to `url`.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn delete_history_url(&self, url: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM history WHERE url = ?1", [url])?;
        Ok(())
    }

    /// Deletes all history.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn clear_history(&self) -> Result<()> {
        self.conn.execute("DELETE FROM history", [])?;
        Ok(())
    }

    // ----- Bookmarks ----------------------------------------------------

    /// Adds or retitles a bookmark.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn add_bookmark(&self, url: &str, title: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO bookmarks (url, title, created_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(url) DO UPDATE SET title = excluded.title",
            params![url, title, now_ms()],
        )?;
        Ok(())
    }

    /// Removes a bookmark.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn remove_bookmark(&self, url: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM bookmarks WHERE url = ?1", [url])?;
        Ok(())
    }

    /// Whether `url` is bookmarked.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn is_bookmarked(&self, url: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row("SELECT 1 FROM bookmarks WHERE url = ?1", [url], |_| Ok(()))
            .optional()?
            .is_some())
    }

    /// Bookmarks matching `query` (all when blank), newest first.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn bookmarks(&self, query: &str, limit: usize) -> Result<Vec<Bookmark>> {
        let pattern = format!("%{}%", query.trim());
        let mut stmt = self.conn.prepare(
            "SELECT url, title, created_at FROM bookmarks
             WHERE url LIKE ?1 OR title LIKE ?1 ORDER BY created_at DESC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![pattern, limit as i64], |r| {
            Ok(Bookmark {
                url: r.get(0)?,
                title: r.get(1)?,
                created_at: r.get(2)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    // ----- Conversations ------------------------------------------------

    /// Inserts or replaces a conversation and its messages.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn save_conversation(&mut self, conversation: &Conversation) -> Result<()> {
        let tx = self.conn.transaction()?;
        let id = conversation.id.to_string();
        tx.execute(
            "INSERT INTO conversations (id, title, scope_json, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(id) DO UPDATE SET title = excluded.title,
                 scope_json = excluded.scope_json, updated_at = excluded.updated_at",
            params![
                id,
                conversation.title,
                serde_json::to_string(&conversation.scope).unwrap_or_else(|_| "{}".into()),
                conversation.created_at,
                conversation.updated_at,
            ],
        )?;
        tx.execute("DELETE FROM messages WHERE conversation_id = ?1", [&id])?;
        {
            let mut insert = tx.prepare(
                "INSERT INTO messages (id, conversation_id, position, role, content,
                                       context_json, error, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )?;
            for (position, message) in conversation.messages.iter().enumerate() {
                insert.execute(params![
                    message.id.to_string(),
                    id,
                    position as i64,
                    message.role.as_str(),
                    message.content,
                    serde_json::to_string(&message.context).unwrap_or_else(|_| "[]".into()),
                    message.error,
                    message.created_at,
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Conversation summaries, most recently updated first.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn list_conversations(&self, limit: usize) -> Result<Vec<ConversationSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT c.id, c.title, c.updated_at,
                    (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
             FROM conversations c ORDER BY c.updated_at DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, i64>(3)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, title, updated_at, count) = row?;
            out.push(ConversationSummary {
                id: parse_id(&id)?,
                title,
                updated_at,
                message_count: usize::try_from(count).unwrap_or(0),
            });
        }
        Ok(out)
    }

    /// Loads a conversation with its messages.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn load_conversation(&self, id: ConversationId) -> Result<Option<Conversation>> {
        let key = id.to_string();
        let header = self
            .conn
            .query_row(
                "SELECT title, scope_json, created_at, updated_at FROM conversations WHERE id = ?1",
                [&key],
                |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, i64>(2)?,
                        r.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional()?;
        let Some((title, scope_json, created_at, updated_at)) = header else {
            return Ok(None);
        };
        let mut stmt = self.conn.prepare(
            "SELECT id, role, content, context_json, error, created_at FROM messages
             WHERE conversation_id = ?1 ORDER BY position",
        )?;
        let rows = stmt.query_map([&key], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<String>>(4)?,
                r.get::<_, i64>(5)?,
            ))
        })?;
        let mut messages = Vec::new();
        for row in rows {
            let (mid, role, content, context_json, error, created_at) = row?;
            messages.push(ChatMessage {
                id: parse_id(&mid)?,
                role: if role == "assistant" {
                    Role::Assistant
                } else {
                    Role::User
                },
                content,
                context: serde_json::from_str::<Vec<ContextRef>>(&context_json).unwrap_or_default(),
                created_at,
                error,
            });
        }
        Ok(Some(Conversation {
            id,
            title,
            scope: serde_json::from_str::<ConversationScope>(&scope_json).unwrap_or_default(),
            messages,
            created_at,
            updated_at,
        }))
    }

    /// Deletes a conversation and its messages.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn delete_conversation(&self, id: ConversationId) -> Result<()> {
        self.conn
            .execute("DELETE FROM conversations WHERE id = ?1", [id.to_string()])?;
        Ok(())
    }

    // ----- Site permissions ---------------------------------------------

    /// The remembered decision for `origin` and `permission`, if any.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn permission(&self, origin: &str, permission: &str) -> Result<Option<PermissionDecision>> {
        let value: Option<String> = self
            .conn
            .query_row(
                "SELECT decision FROM site_permissions WHERE origin = ?1 AND permission = ?2",
                params![origin, permission],
                |r| r.get(0),
            )
            .optional()?;
        Ok(value.map(|v| {
            if v == "allow" {
                PermissionDecision::Allow
            } else {
                PermissionDecision::Deny
            }
        }))
    }

    /// Remembers a decision.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn set_permission(
        &self,
        origin: &str,
        permission: &str,
        decision: PermissionDecision,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO site_permissions (origin, permission, decision) VALUES (?1, ?2, ?3)
             ON CONFLICT(origin, permission) DO UPDATE SET decision = excluded.decision",
            params![origin, permission, decision.as_str()],
        )?;
        Ok(())
    }

    /// All remembered decisions as `(origin, permission, decision)`.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn permissions(&self) -> Result<Vec<(String, String, PermissionDecision)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT origin, permission, decision FROM site_permissions ORDER BY origin")?;
        let rows = stmt.query_map([], |r| {
            let decision: String = r.get(2)?;
            Ok((
                r.get(0)?,
                r.get(1)?,
                if decision == "allow" {
                    PermissionDecision::Allow
                } else {
                    PermissionDecision::Deny
                },
            ))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Forgets a decision.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn clear_permission(&self, origin: &str, permission: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM site_permissions WHERE origin = ?1 AND permission = ?2",
            params![origin, permission],
        )?;
        Ok(())
    }

    // ----- Downloads ----------------------------------------------------

    /// Records a started download and returns its id.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn start_download(&self, url: &str, path: Option<&str>) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO downloads (url, path, state, started_at) VALUES (?1, ?2, 'in_progress', ?3)",
            params![url, path, now_ms()],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Marks the latest in-progress download of `url` as finished.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn finish_download(&self, url: &str, path: Option<&str>, success: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE downloads SET state = ?3, finished_at = ?4, path = COALESCE(?2, path)
             WHERE id = (SELECT id FROM downloads WHERE url = ?1 AND state = 'in_progress'
                         ORDER BY started_at DESC LIMIT 1)",
            params![
                url,
                path,
                if success { "completed" } else { "failed" },
                now_ms()
            ],
        )?;
        Ok(())
    }

    /// Recent downloads, newest first.
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn downloads(&self, limit: usize) -> Result<Vec<DownloadRecord>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, url, path, state, started_at, finished_at FROM downloads
             ORDER BY started_at DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], |r| {
            Ok(DownloadRecord {
                id: r.get(0)?,
                url: r.get(1)?,
                path: r.get(2)?,
                state: r.get(3)?,
                started_at: r.get(4)?,
                finished_at: r.get(5)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Removes finished downloads from the list (files are kept).
    ///
    /// # Errors
    /// Fails on SQLite errors.
    pub fn clear_finished_downloads(&self) -> Result<()> {
        self.conn
            .execute("DELETE FROM downloads WHERE state != 'in_progress'", [])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use curio_core::chat::Role;
    use curio_tabs::{Placement, Section};

    fn sample_workspace() -> Workspace {
        let mut ws = Workspace::first_run();
        let a = ws.spaces()[0].id;
        let b = ws.spaces()[1].id;
        let t1 = ws
            .open_tab(
                a,
                Tab::new("https://one.test"),
                Placement::SectionEnd(Section::Unpinned),
                true,
            )
            .expect("space");
        let t2 = ws
            .open_tab(
                a,
                Tab::new("https://two.test"),
                Placement::SectionEnd(Section::Unpinned),
                false,
            )
            .expect("space");
        let t3 = ws
            .open_tab(
                a,
                Tab::new("https://three.test"),
                Placement::SectionEnd(Section::Unpinned),
                false,
            )
            .expect("space");
        ws.open_tab(
            b,
            Tab::new("https://work.test"),
            Placement::SectionEnd(Section::Unpinned),
            true,
        );
        let space = ws.space_mut(a).expect("space");
        space.strip.pin(t1);
        let group = space
            .strip
            .create_group("Reading", AccentColor::Coral, &[t2, t3]);
        space.strip.set_group_collapsed(group, true);
        ws.add_favorite("https://fav.test", "Fav", None);
        ws.switch_space(b);
        ws
    }

    #[test]
    fn workspace_round_trips_through_sqlite() {
        let mut db = Database::open_in_memory().expect("db");
        assert!(db.load_workspace().expect("load").is_none());
        let ws = sample_workspace();
        db.save_workspace(&ws).expect("save");
        let loaded = db.load_workspace().expect("load").expect("saved");
        assert_eq!(loaded.spaces(), ws.spaces());
        assert_eq!(loaded.favorites(), ws.favorites());
        assert_eq!(loaded.active_space_id(), ws.active_space_id());
    }

    #[test]
    fn saving_twice_replaces_previous_snapshot() {
        let mut db = Database::open_in_memory().expect("db");
        let mut ws = sample_workspace();
        db.save_workspace(&ws).expect("save");
        let a = ws.spaces()[0].id;
        let first = ws.space(a).expect("space").strip.ordered_tab_ids()[0];
        ws.close_tab(first);
        db.save_workspace(&ws).expect("save");
        let loaded = db.load_workspace().expect("load").expect("saved");
        assert!(loaded.tab(first).is_none());
        assert_eq!(loaded.spaces(), ws.spaces());
    }

    #[test]
    fn settings_round_trip() {
        let db = Database::open_in_memory().expect("db");
        let mut settings = db.load_settings().expect("load");
        settings.appearance.tab_layout = curio_settings::TabLayout::Horizontal;
        db.save_settings(&settings).expect("save");
        assert_eq!(db.load_settings().expect("load"), settings);
    }

    #[test]
    fn history_is_searchable_and_aggregated() {
        let db = Database::open_in_memory().expect("db");
        db.record_visit("https://gpui.rs/", "").expect("visit");
        db.update_history_title("https://gpui.rs/", "GPUI")
            .expect("title");
        db.record_visit("https://gpui.rs/", "GPUI").expect("visit");
        db.record_visit("https://zed.dev/", "Zed").expect("visit");
        let results = db.search_history("gpui", 10).expect("search");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].visit_count, 2);
        assert_eq!(results[0].title, "GPUI");
        // LIKE wildcards in queries are literal.
        assert!(db.search_history("%", 10).expect("search").is_empty());
        db.clear_history().expect("clear");
        assert!(db.recent_history(10).expect("recent").is_empty());
    }

    #[test]
    fn bookmarks_crud() {
        let db = Database::open_in_memory().expect("db");
        db.add_bookmark("https://a.test", "A").expect("add");
        assert!(db.is_bookmarked("https://a.test").expect("query"));
        assert_eq!(db.bookmarks("", 10).expect("list").len(), 1);
        db.remove_bookmark("https://a.test").expect("remove");
        assert!(!db.is_bookmarked("https://a.test").expect("query"));
    }

    #[test]
    fn conversations_round_trip() {
        let mut db = Database::open_in_memory().expect("db");
        let mut conv = Conversation::default();
        let mut user = ChatMessage::new(Role::User, "Summarize this page");
        user.context.push(ContextRef {
            title: "GPUI".into(),
            url: "https://gpui.rs".into(),
        });
        conv.messages.push(user);
        conv.messages
            .push(ChatMessage::new(Role::Assistant, "It is a UI framework."));
        conv.scope = ConversationScope::Tabs {
            tabs: vec![TabId::new()],
        };
        conv.retitle_from_first_message();
        db.save_conversation(&conv).expect("save");
        let loaded = db
            .load_conversation(conv.id)
            .expect("load")
            .expect("exists");
        assert_eq!(loaded, conv);
        let list = db.list_conversations(10).expect("list");
        assert_eq!(list[0].message_count, 2);
        db.delete_conversation(conv.id).expect("delete");
        assert!(db.load_conversation(conv.id).expect("load").is_none());
    }

    #[test]
    fn permissions_and_downloads() {
        let db = Database::open_in_memory().expect("db");
        db.set_permission("https://meet.test", "camera", PermissionDecision::Allow)
            .expect("set");
        assert_eq!(
            db.permission("https://meet.test", "camera").expect("get"),
            Some(PermissionDecision::Allow)
        );
        db.clear_permission("https://meet.test", "camera")
            .expect("clear");
        assert!(
            db.permission("https://meet.test", "camera")
                .expect("get")
                .is_none()
        );

        db.start_download("https://a.test/f.zip", Some("/tmp/f.zip"))
            .expect("start");
        db.finish_download("https://a.test/f.zip", None, true)
            .expect("finish");
        let downloads = db.downloads(10).expect("list");
        assert_eq!(downloads[0].state, "completed");
        assert_eq!(downloads[0].path.as_deref(), Some("/tmp/f.zip"));
    }

    #[test]
    fn database_file_persists_across_reopen() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("curio.db");
        let ws = sample_workspace();
        {
            let mut db = Database::open(&path).expect("open");
            db.save_workspace(&ws).expect("save");
        }
        let db = Database::open(&path).expect("reopen");
        let loaded = db.load_workspace().expect("load").expect("saved");
        assert_eq!(loaded.spaces(), ws.spaces());
    }
}
