//! Timestamps stored as Unix epoch milliseconds.

use std::time::{SystemTime, UNIX_EPOCH};

/// Milliseconds since the Unix epoch. Stored as `i64` to map directly onto
/// SQLite `INTEGER` columns.
pub type Timestamp = i64;

/// The current time in epoch milliseconds. Clocks before 1970 read as `0`.
#[must_use]
pub fn now_ms() -> Timestamp {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}
