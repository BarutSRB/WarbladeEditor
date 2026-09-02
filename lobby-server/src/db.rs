//! SQLite access: one connection behind a mutex (every query is sub-millisecond
//! at this scale), the schema, and the migration entry point.

use std::sync::{Mutex, MutexGuard};

use anyhow::Context;
use rusqlite::Connection;

use crate::protocol::ApiError;

pub struct Db {
    conn: Mutex<Connection>,
}

pub const SCHEMA_VERSION: i64 = 1;

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS accounts (
  id                  INTEGER PRIMARY KEY,
  nickname            TEXT    NOT NULL,
  nickname_lc         TEXT    NOT NULL UNIQUE,
  device_key_hash     BLOB    NOT NULL UNIQUE,
  created_at          INTEGER NOT NULL,
  last_login_at       INTEGER,
  last_ip             TEXT,
  disabled            INTEGER NOT NULL DEFAULT 0,
  talent_points       INTEGER NOT NULL DEFAULT 0 CHECK (talent_points >= 0),
  points_earned_total INTEGER NOT NULL DEFAULT 0,
  respec_count        INTEGER NOT NULL DEFAULT 0,
  last_respec_at      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS talent_nodes (
  account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  node_id     TEXT    NOT NULL,
  acquired_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, node_id)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS point_ledger (
  id         INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  delta      INTEGER NOT NULL,
  reason     TEXT    NOT NULL,
  ref_id     TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS point_ledger_account_time ON point_ledger(account_id, reason, created_at);

CREATE TABLE IF NOT EXISTS chat_messages (
  id         INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL,
  nickname   TEXT    NOT NULL,
  body       TEXT    NOT NULL,
  sent_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS chat_messages_account ON chat_messages(account_id);

CREATE TABLE IF NOT EXISTS matches (
  id                 INTEGER PRIMARY KEY,
  kind               TEXT    NOT NULL,
  lobby_id           TEXT,
  lobby_name         TEXT,
  host_account_id    INTEGER NOT NULL REFERENCES accounts(id),
  mode               TEXT    NOT NULL,
  difficulty         TEXT    NOT NULL,
  coop_balance       TEXT    NOT NULL,
  seed               TEXT,
  start_level        INTEGER,
  end_level          INTEGER,
  content_hash       TEXT,
  started_at         INTEGER NOT NULL,
  ended_at           INTEGER,
  result             TEXT,
  score              INTEGER,
  level_reached      INTEGER,
  duration_ticks     INTEGER,
  campaign_completed INTEGER NOT NULL DEFAULT 0,
  extra_json         TEXT
);
CREATE INDEX IF NOT EXISTS matches_started ON matches(started_at DESC);
CREATE INDEX IF NOT EXISTS matches_host ON matches(host_account_id, started_at DESC);
CREATE INDEX IF NOT EXISTS matches_open ON matches(ended_at) WHERE ended_at IS NULL;

CREATE TABLE IF NOT EXISTS match_players (
  match_id       INTEGER NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  seat           INTEGER NOT NULL,
  account_id     INTEGER REFERENCES accounts(id),
  nickname       TEXT    NOT NULL,
  points_awarded INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (match_id, seat)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS match_players_account ON match_players(account_id);

CREATE TABLE IF NOT EXISTS admin_events (
  id         INTEGER PRIMARY KEY,
  at         INTEGER NOT NULL,
  kind       TEXT    NOT NULL,
  account_id INTEGER,
  detail     TEXT    NOT NULL
);
"#;

impl Db {
    pub fn open(path: &str) -> anyhow::Result<Db> {
        let conn = Connection::open(path).with_context(|| format!("opening database {path}"))?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;",
        )
        .context("configuring database pragmas")?;
        Self::migrate(&conn)?;
        Ok(Db { conn: Mutex::new(conn) })
    }

    pub fn open_in_memory() -> anyhow::Result<Db> {
        let conn = Connection::open_in_memory().context("opening in-memory database")?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")?;
        Self::migrate(&conn)?;
        Ok(Db { conn: Mutex::new(conn) })
    }

    fn migrate(conn: &Connection) -> anyhow::Result<()> {
        conn.execute_batch(SCHEMA).context("applying schema")?;
        let version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
        if version < SCHEMA_VERSION {
            conn.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}"))?;
        }
        Ok(())
    }

    /// Runs a closure against the connection. Database failures are logged
    /// and surface as INTERNAL; the closure may also return its own ApiError.
    pub fn with<R>(&self, f: impl FnOnce(&mut Connection) -> Result<R, ApiError>) -> Result<R, ApiError> {
        let mut guard: MutexGuard<Connection> = self.conn.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(&mut guard)
    }

    /// Like `with`, but for maintenance jobs that report anyhow errors.
    pub fn maintenance<R>(&self, f: impl FnOnce(&mut Connection) -> rusqlite::Result<R>) -> anyhow::Result<R> {
        let mut guard: MutexGuard<Connection> = self.conn.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(&mut guard).context("database maintenance")
    }
}

pub fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Start of the current UTC day, for the daily credit ladder.
pub fn utc_day_start(now: i64) -> i64 {
    now - now.rem_euclid(86_400)
}
