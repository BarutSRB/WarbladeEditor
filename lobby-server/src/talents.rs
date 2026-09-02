//! The talent tree: content/talents.json is the rules source on both sides.
//! The server validates spends and respecs exactly like WBTalentCatalog in
//! the client, composes grants (MAX for ints, OR for bools), and owns the
//! points wallet.

use std::collections::{HashMap, HashSet};

use rusqlite::{params, Connection};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use crate::db::now_unix;
use crate::protocol::{field_string, ApiError, ApiResult, ErrorCode};
use crate::session::SessionId;
use crate::state::AppState;

pub struct TalentNode {
    pub id: String,
    pub cost: i64,
    pub requires: Vec<String>,
    pub kind: String,
    pub grants: Map<String, Value>,
    pub shop_effect: Option<String>,
}

pub struct TalentCatalog {
    pub version: i64,
    pub respec_cooldown_sec: i64,
    pub nodes: HashMap<String, TalentNode>,
    pub gated_effects: Vec<String>,
    pub sha256: String,
}

impl TalentCatalog {
    pub fn load(path: &str) -> anyhow::Result<TalentCatalog> {
        let text = std::fs::read_to_string(path).map_err(|e| anyhow::anyhow!("reading {path}: {e}"))?;
        Self::from_json(&text)
    }

    pub fn from_json(text: &str) -> anyhow::Result<TalentCatalog> {
        let document: Value = serde_json::from_str(text)?;
        if document.get("schema").and_then(Value::as_str) != Some("warblade.talents.v1") {
            anyhow::bail!("talents.json schema is not warblade.talents.v1");
        }
        let version = document.get("version").and_then(Value::as_i64).unwrap_or(0);
        let respec_cooldown_sec = document
            .get("respec")
            .and_then(|r| r.get("cooldown_sec"))
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let gated_effects: Vec<String> = document
            .get("shop_migration")
            .and_then(|m| m.get("talent_gated_effects"))
            .and_then(Value::as_array)
            .map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect())
            .unwrap_or_default();
        let grant_keys = document.get("grant_keys").cloned().unwrap_or(Value::Null);
        let known_keys: HashSet<String> = ["int", "bool"]
            .iter()
            .flat_map(|kind| {
                grant_keys
                    .get(kind)
                    .and_then(Value::as_array)
                    .map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect::<Vec<_>>())
                    .unwrap_or_default()
            })
            .collect();
        let mut nodes = HashMap::new();
        for branch in document.get("branches").and_then(Value::as_array).cloned().unwrap_or_default() {
            for node in branch.get("nodes").and_then(Value::as_array).cloned().unwrap_or_default() {
                let id = node.get("id").and_then(Value::as_str).unwrap_or("").to_string();
                if id.is_empty() {
                    anyhow::bail!("talent node without an id");
                }
                let kind = node.get("kind").and_then(Value::as_str).unwrap_or("grant").to_string();
                let grants = node.get("grants").and_then(Value::as_object).cloned().unwrap_or_default();
                for key in grants.keys() {
                    if !known_keys.is_empty() && !known_keys.contains(key) {
                        anyhow::bail!("talent {id} grants unknown key {key}");
                    }
                }
                let shop_effect = node.get("shop_effect").and_then(Value::as_str).map(str::to_string);
                if let Some(effect) = &shop_effect {
                    if !gated_effects.contains(effect) {
                        anyhow::bail!("talent {id} unlocks unknown shop effect {effect}");
                    }
                }
                let entry = TalentNode {
                    id: id.clone(),
                    cost: node.get("cost").and_then(Value::as_i64).unwrap_or(0),
                    requires: node
                        .get("requires")
                        .and_then(Value::as_array)
                        .map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect())
                        .unwrap_or_default(),
                    kind,
                    grants,
                    shop_effect,
                };
                if nodes.insert(id.clone(), entry).is_some() {
                    anyhow::bail!("duplicate talent id {id}");
                }
            }
        }
        if nodes.is_empty() {
            anyhow::bail!("talents.json has no nodes");
        }
        for node in nodes.values() {
            for requirement in &node.requires {
                if !nodes.contains_key(requirement) {
                    anyhow::bail!("talent {} requires unknown node {requirement}", node.id);
                }
            }
        }
        for id in nodes.keys() {
            let mut visited = HashSet::new();
            if has_cycle(&nodes, id, &mut visited) {
                anyhow::bail!("talent requirements cycle through {id}");
            }
        }
        let sha256 = hex::encode(Sha256::digest(text.as_bytes()));
        Ok(TalentCatalog { version, respec_cooldown_sec, nodes, gated_effects, sha256 })
    }

    /// Mirrors WBTalentCatalog.validate_spend: unknown -> owned -> prerequisite.
    pub fn validate_spend(&self, owned: &HashSet<String>, node_id: &str) -> Result<i64, ApiError> {
        let node = self
            .nodes
            .get(node_id)
            .ok_or_else(|| ApiError::new(ErrorCode::TalentUnknownNode, format!("unknown talent node: {node_id}")))?;
        if owned.contains(node_id) {
            return Err(ApiError::new(ErrorCode::TalentAlreadyOwned, format!("talent already owned: {node_id}")));
        }
        for requirement in &node.requires {
            if !owned.contains(requirement) {
                return Err(ApiError::new(
                    ErrorCode::TalentPrereqMissing,
                    format!("talent {node_id} requires {requirement}"),
                ));
            }
        }
        Ok(node.cost)
    }

    pub fn spent_total(&self, owned: &HashSet<String>) -> i64 {
        owned.iter().filter_map(|id| self.nodes.get(id)).map(|node| node.cost).sum()
    }

    /// {start_state, starting_rockets, shop_unlocks}: MAX across ints, OR
    /// across bools, rockets kept separately, unlocks sorted and unique.
    pub fn compose_grants(&self, owned: &HashSet<String>) -> Value {
        let mut start_state = Map::new();
        let mut starting_rockets: i64 = 0;
        let mut shop_unlocks: Vec<String> = Vec::new();
        let mut ordered: Vec<&String> = owned.iter().collect();
        ordered.sort();
        for id in ordered {
            let Some(node) = self.nodes.get(id) else { continue };
            if node.kind == "shop_unlock" {
                if let Some(effect) = &node.shop_effect {
                    if !shop_unlocks.contains(effect) {
                        shop_unlocks.push(effect.clone());
                    }
                }
                continue;
            }
            for (key, value) in &node.grants {
                if key == "starting_rockets" {
                    starting_rockets = starting_rockets.max(value.as_i64().unwrap_or(0));
                } else if let Value::Bool(flag) = value {
                    if *flag {
                        start_state.insert(key.clone(), Value::Bool(true));
                    }
                } else {
                    let current = start_state.get(key).and_then(Value::as_i64).unwrap_or(0);
                    start_state.insert(key.clone(), Value::from(current.max(value.as_i64().unwrap_or(0))));
                }
            }
        }
        shop_unlocks.sort();
        json!({
            "start_state": Value::Object(start_state),
            "starting_rockets": starting_rockets,
            "shop_unlocks": shop_unlocks,
        })
    }
}

fn has_cycle(nodes: &HashMap<String, TalentNode>, id: &str, visited: &mut HashSet<String>) -> bool {
    if !visited.insert(id.to_string()) {
        return true;
    }
    if let Some(node) = nodes.get(id) {
        for requirement in &node.requires {
            if has_cycle(nodes, requirement, visited) {
                return true;
            }
        }
    }
    visited.remove(id);
    false
}

// ----------------------------------------------------------------- database

pub struct TalentRow {
    pub points: i64,
    pub owned: HashSet<String>,
    pub respec_count: i64,
    pub last_respec_at: i64,
    pub earned_total: i64,
}

pub fn db_load(conn: &Connection, account_id: i64) -> rusqlite::Result<TalentRow> {
    let (points, respec_count, last_respec_at, earned_total): (i64, i64, i64, i64) = conn.query_row(
        "SELECT talent_points, respec_count, last_respec_at, points_earned_total FROM accounts WHERE id = ?1",
        params![account_id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;
    let mut statement = conn.prepare("SELECT node_id FROM talent_nodes WHERE account_id = ?1")?;
    let owned = statement
        .query_map(params![account_id], |row| row.get::<_, String>(0))?
        .collect::<rusqlite::Result<HashSet<String>>>()?;
    Ok(TalentRow { points, owned, respec_count, last_respec_at, earned_total })
}

pub fn state_json(conn: &Connection, catalog: &TalentCatalog, account_id: i64, nickname: &str) -> Result<Value, ApiError> {
    let row = db_load(conn, account_id)?;
    let mut nodes = Map::new();
    let mut ordered: Vec<&String> = row.owned.iter().collect();
    ordered.sort();
    for id in ordered {
        nodes.insert(id.clone(), Value::from(1));
    }
    Ok(json!({
        "schema_version": 1,
        "nickname": nickname,
        "wallet": {"talent_points": row.points},
        "talents": {
            "nodes": Value::Object(nodes),
            "spent_total": catalog.spent_total(&row.owned),
            "respec_count": row.respec_count,
            "last_respec_unix": row.last_respec_at,
        },
        "grants": catalog.compose_grants(&row.owned),
        "talent_catalog_version": catalog.version,
        "points_earned_total": row.earned_total,
        "server_time_unix": now_unix(),
    }))
}

pub fn db_spend(conn: &mut Connection, account_id: i64, node_id: &str, cost: i64, now: i64) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    tx.execute(
        "UPDATE accounts SET talent_points = talent_points - ?1 WHERE id = ?2",
        params![cost, account_id],
    )?;
    tx.execute(
        "INSERT INTO talent_nodes (account_id, node_id, acquired_at) VALUES (?1, ?2, ?3)",
        params![account_id, node_id, now],
    )?;
    tx.execute(
        "INSERT INTO point_ledger (account_id, delta, reason, ref_id, created_at) VALUES (?1, ?2, 'spend', ?3, ?4)",
        params![account_id, -cost, node_id, now],
    )?;
    tx.commit()
}

pub fn db_respec(conn: &mut Connection, account_id: i64, refund: i64, now: i64) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    tx.execute("DELETE FROM talent_nodes WHERE account_id = ?1", params![account_id])?;
    tx.execute(
        "UPDATE accounts SET talent_points = talent_points + ?1, respec_count = respec_count + 1, last_respec_at = ?2 WHERE id = ?3",
        params![refund, now, account_id],
    )?;
    tx.execute(
        "INSERT INTO point_ledger (account_id, delta, reason, ref_id, created_at) VALUES (?1, ?2, 'respec', NULL, ?3)",
        params![account_id, refund, now],
    )?;
    tx.commit()
}

pub fn db_credit(conn: &Connection, account_id: i64, delta: i64, reason: &str, ref_id: &str, now: i64) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE accounts SET talent_points = MAX(0, talent_points + ?1), points_earned_total = points_earned_total + MAX(0, ?1) WHERE id = ?2",
        params![delta, account_id],
    )?;
    conn.execute(
        "INSERT INTO point_ledger (account_id, delta, reason, ref_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![account_id, delta, reason, ref_id, now],
    )?;
    Ok(())
}

// ----------------------------------------------------------------- handlers

pub fn handle_state(state: &AppState, sid: SessionId) -> ApiResult {
    let account = state.hub().require_account(sid)?;
    let talents = state.db.with(|conn| state_json(conn, &state.talents, account.id, &account.nickname))?;
    Ok(json!({"state": talents}))
}

pub fn handle_spend(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let node_id = field_string(payload, "node_id", 64)?;
    let account = {
        let mut hub = state.hub();
        let account = hub.require_account(sid)?;
        if !hub.require_session_mut(sid)?.bucket_talent.try_take() {
            return Err(ApiError::new(ErrorCode::RateLimited, "slow down"));
        }
        account
    };
    let now = now_unix();
    let talents = state.db.with(|conn| {
        let row = db_load(conn, account.id)?;
        let cost = state.talents.validate_spend(&row.owned, &node_id)?;
        if row.points < cost {
            return Err(ApiError::new(ErrorCode::InsufficientPoints, "not enough talent points"));
        }
        db_spend(conn, account.id, &node_id, cost, now)?;
        state_json(conn, &state.talents, account.id, &account.nickname)
    })?;
    Ok(json!({"state": talents}))
}

pub fn handle_respec(state: &AppState, sid: SessionId) -> ApiResult {
    let account = {
        let mut hub = state.hub();
        let account = hub.require_account(sid)?;
        if !hub.require_session_mut(sid)?.bucket_talent.try_take() {
            return Err(ApiError::new(ErrorCode::RateLimited, "slow down"));
        }
        account
    };
    let now = now_unix();
    let talents = state.db.with(|conn| {
        let row = db_load(conn, account.id)?;
        if row.owned.is_empty() {
            return state_json(conn, &state.talents, account.id, &account.nickname);
        }
        let remaining = row.last_respec_at + state.talents.respec_cooldown_sec - now;
        if row.last_respec_at > 0 && remaining > 0 {
            return Err(ApiError::new(ErrorCode::RespecCooldown, "respec is on cooldown")
                .with("retry_after_sec", Value::from(remaining)));
        }
        let refund = state.talents.spent_total(&row.owned);
        db_respec(conn, account.id, refund, now)?;
        state_json(conn, &state.talents, account.id, &account.nickname)
    })?;
    Ok(json!({"state": talents}))
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::db::Db;

    pub fn catalog() -> TalentCatalog {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../content/talents.json");
        TalentCatalog::load(path).expect("talents.json loads")
    }

    fn owned(ids: &[&str]) -> HashSet<String> {
        ids.iter().map(|id| id.to_string()).collect()
    }

    #[test]
    fn catalog_rules() {
        let catalog = catalog();
        assert!(catalog.nodes.len() >= 20);
        assert!(catalog.gated_effects.contains(&"enable_autofire".to_string()));
        assert_eq!(catalog.validate_spend(&owned(&[]), "gunnery_capacity_1").unwrap(), 10);
        assert_eq!(
            catalog.validate_spend(&owned(&[]), "no_such_node").unwrap_err().code,
            ErrorCode::TalentUnknownNode
        );
        assert_eq!(
            catalog.validate_spend(&owned(&[]), "gunnery_capacity_2").unwrap_err().code,
            ErrorCode::TalentPrereqMissing
        );
        assert!(catalog.validate_spend(&owned(&["gunnery_capacity_1"]), "gunnery_capacity_2").is_ok());
        assert_eq!(
            catalog.validate_spend(&owned(&["gunnery_capacity_1"]), "gunnery_capacity_1").unwrap_err().code,
            ErrorCode::TalentAlreadyOwned
        );
    }

    #[test]
    fn grant_composition() {
        let catalog = catalog();
        let set = owned(&[
            "gunnery_capacity_1",
            "gunnery_capacity_2",
            "gunnery_bullet_speed",
            "gunnery_autofire_license",
            "ordnance_rocket_license",
            "ordnance_rockets_1",
            "ordnance_rockets_2",
            "vanished_node",
        ]);
        let grants = catalog.compose_grants(&set);
        assert_eq!(grants["start_state"]["bullet_capacity"], 12);
        assert_eq!(grants["start_state"]["bullet_speed_up"], true);
        assert_eq!(grants["starting_rockets"], 20);
        assert_eq!(grants["shop_unlocks"], json!(["enable_autofire", "rocket_pack"]));
        assert_eq!(catalog.spent_total(&set), 10 + 20 + 25 + 30 + 15 + 20 + 35);
        assert!(catalog.compose_grants(&owned(&[]))["start_state"].as_object().unwrap().is_empty());
    }

    #[test]
    fn spend_and_respec_persist() {
        let catalog = catalog();
        let db = Db::open_in_memory().unwrap();
        db.with(|conn| {
            let account = crate::accounts::db_create(conn, &[7u8; 32], "Pilot", 1, "127.0.0.1")?;
            db_credit(conn, account.id, 35, "admin", "", 1)?;
            let row = db_load(conn, account.id)?;
            assert_eq!(row.points, 35);
            let cost = catalog.validate_spend(&row.owned, "gunnery_capacity_1")?;
            db_spend(conn, account.id, "gunnery_capacity_1", cost, 2)?;
            let row = db_load(conn, account.id)?;
            assert_eq!(row.points, 25);
            assert!(row.owned.contains("gunnery_capacity_1"));
            let state = state_json(conn, &catalog, account.id, "Pilot")?;
            assert_eq!(state["wallet"]["talent_points"], 25);
            assert_eq!(state["talents"]["nodes"]["gunnery_capacity_1"], 1);
            assert_eq!(state["grants"]["start_state"]["bullet_capacity"], 8);
            db_respec(conn, account.id, catalog.spent_total(&row.owned), 3)?;
            let row = db_load(conn, account.id)?;
            assert_eq!(row.points, 35);
            assert!(row.owned.is_empty());
            assert_eq!(row.respec_count, 1);
            assert_eq!(row.last_respec_at, 3);
            Ok(())
        })
        .unwrap();
    }
}
