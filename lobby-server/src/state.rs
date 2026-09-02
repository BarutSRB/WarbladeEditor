//! Shared process state handed to every handler.

use std::sync::{Mutex, MutexGuard};
use std::time::Instant;

use serde_json::json;

use crate::config::Config;
use crate::db::Db;
use crate::protocol::{self, limits};
use crate::session::Hub;
use crate::talents::TalentCatalog;

pub struct AppState {
    pub config: Config,
    pub hub: Mutex<Hub>,
    pub db: Db,
    pub talents: TalentCatalog,
    pub started_at: Instant,
}

impl AppState {
    pub fn new(config: Config, db: Db, talents: TalentCatalog) -> AppState {
        AppState { config, hub: Mutex::new(Hub::default()), db, talents, started_at: Instant::now() }
    }

    pub fn hub(&self) -> MutexGuard<'_, Hub> {
        self.hub.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Shutdown: every session hears why and gets a close frame so the
    /// listener can drain within the systemd stop timeout.
    pub fn close_all_sessions(&self) {
        let hub = self.hub();
        let notice = protocol::push("notice", json!({"kind": "shutdown", "message": "the lobby server is restarting"}));
        let ids: Vec<u64> = hub.sessions.keys().copied().collect();
        for sid in ids {
            hub.send(sid, notice.clone());
            hub.close(sid, limits::CLOSE_SHUTDOWN, "shutdown");
        }
    }
}
