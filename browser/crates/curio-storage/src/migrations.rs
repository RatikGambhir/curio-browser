//! Schema migrations, applied in order and tracked with `PRAGMA user_version`.

use rusqlite::Connection;

use crate::Result;

/// Each entry upgrades the schema from version `index` to `index + 1`.
const MIGRATIONS: &[&str] = &[
    // v1: initial schema.
    r"
    CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        json TEXT NOT NULL
    );
    CREATE TABLE kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    CREATE TABLE spaces (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        active_tab TEXT
    );
    CREATE TABLE tabs (
        id TEXT PRIMARY KEY,
        owner_kind TEXT NOT NULL CHECK (owner_kind IN ('space', 'favorite')),
        owner_id TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        favicon_url TEXT,
        home_url TEXT,
        scroll_y REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_active_at INTEGER NOT NULL
    );
    CREATE TABLE tab_groups (
        id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        name TEXT NOT NULL,
        color TEXT NOT NULL,
        collapsed INTEGER NOT NULL DEFAULT 0
    );
    -- Ordering of a space's sections and of each group's members.
    CREATE TABLE layout (
        space_id TEXT NOT NULL,
        section TEXT NOT NULL CHECK (section IN ('pinned', 'unpinned')),
        parent_group TEXT,
        position INTEGER NOT NULL,
        item_kind TEXT NOT NULL CHECK (item_kind IN ('tab', 'group')),
        item_id TEXT NOT NULL
    );
    CREATE INDEX layout_space ON layout(space_id);
    CREATE TABLE favorites (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL
    );
    CREATE TABLE history (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        visited_at INTEGER NOT NULL
    );
    CREATE INDEX history_url ON history(url);
    CREATE INDEX history_visited ON history(visited_at);
    CREATE TABLE bookmarks (
        url TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
    );
    CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        scope_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    );
    CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        context_json TEXT NOT NULL DEFAULT '[]',
        error TEXT,
        created_at INTEGER NOT NULL
    );
    CREATE INDEX messages_conversation ON messages(conversation_id, position);
    CREATE TABLE site_permissions (
        origin TEXT NOT NULL,
        permission TEXT NOT NULL,
        decision TEXT NOT NULL CHECK (decision IN ('allow', 'deny')),
        PRIMARY KEY (origin, permission)
    );
    CREATE TABLE downloads (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        path TEXT,
        state TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        finished_at INTEGER
    );
    ",
];

/// The schema version this build expects.
pub(crate) const LATEST: i64 = MIGRATIONS.len() as i64;

/// Applies pending migrations inside a transaction each.
pub(crate) fn migrate(conn: &mut Connection) -> Result<()> {
    let current: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current > LATEST {
        tracing::warn!(
            current,
            latest = LATEST,
            "database was written by a newer Curio; continuing read-compatible"
        );
        return Ok(());
    }
    for (index, sql) in MIGRATIONS
        .iter()
        .enumerate()
        .skip(usize::try_from(current).unwrap_or(0))
    {
        let version = index as i64 + 1;
        let tx = conn.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", version)?;
        tx.commit()?;
        tracing::info!(version, "applied database migration");
    }
    Ok(())
}
