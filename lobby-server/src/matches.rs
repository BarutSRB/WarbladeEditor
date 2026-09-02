//! Self-reported match records and the talent-point credit that follows a
//! finished run. Nothing here is verified; the host's word is the record.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use tracing::info;

use crate::db::{now_unix, utc_day_start};
use crate::lobbies::LobbyState;
use crate::protocol::{
    self, field_bool, field_choice, field_i64_opt, field_string_opt, limits, ApiError, ApiResult, ErrorCode,
    BALANCES, DIFFICULTIES, MATCH_KINDS, MATCH_RESULTS, MODES,
};
use crate::session::{Presence, SessionId};
use crate::state::AppState;
use crate::talents;

/// The single crediting rule: floor(sqrt(score / 1000)) scaled by
/// difficulty, mode, and a daily ladder over the runs already credited today,
/// at least 1 point for any scoring run, +40 for completing the campaign,
/// capped per match.
pub fn credit_points(score: i64, difficulty: &str, mode: &str, credited_today: u32, campaign_completed: bool) -> i64 {
    let score = score.clamp(0, limits::MAX_SCORE);
    let bonus = if campaign_completed && mode != "time_trial" { 40 } else { 0 };
    if score == 0 {
        return bonus.min(limits::MAX_POINTS_PER_MATCH);
    }
    let base = ((score as f64) / 1000.0).sqrt().floor();
    let difficulty_multiplier = match difficulty {
        "easy" => 0.5,
        "hard" => 1.3,
        "ace" => 1.6,
        _ => 1.0,
    };
    let mode_multiplier = if mode == "time_trial" { 0.75 } else { 1.0 };
    const LADDER: [f64; 7] = [1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.25];
    let daily = LADDER[(credited_today as usize).min(LADDER.len() - 1)];
    let points = ((base * difficulty_multiplier * mode_multiplier * daily).floor() as i64).max(1) + bonus;
    points.min(limits::MAX_POINTS_PER_MATCH)
}

#[derive(Clone, Debug)]
pub struct MatchStart {
    pub kind: String,
    pub mode: String,
    pub difficulty: String,
    pub coop_balance: String,
    pub seed: Option<String>,
    pub start_level: Option<i64>,
    pub end_level: Option<i64>,
    pub content_hash: Option<String>,
    pub lobby_id: Option<String>,
    pub lobby_name: Option<String>,
}

fn parse_start(payload: &Value) -> Result<MatchStart, ApiError> {
    let start_level = field_i64_opt(payload, "start_level")?;
    let end_level = field_i64_opt(payload, "end_level")?;
    for level in [start_level, end_level].into_iter().flatten() {
        if !(1..=limits::MAX_LEVEL).contains(&level) {
            return Err(ApiError::schema("levels must be 1-3999"));
        }
    }
    Ok(MatchStart {
        kind: field_choice(payload, "kind", MATCH_KINDS)?,
        mode: field_choice(payload, "mode", MODES)?,
        difficulty: field_choice(payload, "difficulty", DIFFICULTIES)?,
        coop_balance: field_choice(payload, "coop_balance", BALANCES)?,
        seed: field_string_opt(payload, "seed", 32)?,
        start_level,
        end_level,
        content_hash: field_string_opt(payload, "content_hash", 64)?,
        lobby_id: None,
        lobby_name: None,
    })
}

#[derive(Clone, Debug)]
pub struct EndReport {
    pub result: String,
    pub score: i64,
    pub level_reached: i64,
    pub duration_ticks: i64,
    pub campaign_completed: bool,
    pub extra_json: Option<String>,
}

fn parse_end(payload: &Value) -> Result<EndReport, ApiError> {
    let extra_json = match payload.get("extra") {
        Some(Value::Object(object)) => {
            let text = Value::Object(object.clone()).to_string();
            if text.len() > 2048 {
                return Err(ApiError::schema("extra is larger than 2 KiB"));
            }
            Some(text)
        }
        _ => None,
    };
    Ok(EndReport {
        result: field_choice(payload, "result", MATCH_RESULTS)?,
        score: field_i64_opt(payload, "score")?.unwrap_or(0).clamp(0, limits::MAX_SCORE),
        level_reached: field_i64_opt(payload, "level_reached")?.unwrap_or(1).clamp(1, limits::MAX_LEVEL),
        duration_ticks: field_i64_opt(payload, "duration_ticks")?.unwrap_or(0).max(0),
        campaign_completed: field_bool(payload, "campaign_completed", false),
        extra_json,
    })
}

pub fn db_insert_match(conn: &Connection, start: &MatchStart, host_account_id: i64, now: i64) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO matches (kind, lobby_id, lobby_name, host_account_id, mode, difficulty, coop_balance, seed, start_level, end_level, content_hash, started_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
        params![
            start.kind,
            start.lobby_id,
            start.lobby_name,
            host_account_id,
            start.mode,
            start.difficulty,
            start.coop_balance,
            start.seed,
            start.start_level,
            start.end_level,
            start.content_hash,
            now
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn db_insert_player(conn: &Connection, match_id: i64, seat: i64, account_id: Option<i64>, nickname: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO match_players (match_id, seat, account_id, nickname) VALUES (?1, ?2, ?3, ?4)",
        params![match_id, seat, account_id, nickname],
    )?;
    Ok(())
}

#[derive(Debug)]
pub struct CreditOutcome {
    pub already_recorded: bool,
    pub credits: Vec<(i64, i64)>,
}

/// Ends a match and credits every seated account in one transaction. A
/// repeat report is a no-op (already_recorded) so retries never double-credit.
pub fn db_end_match(
    conn: &mut Connection,
    match_id: i64,
    reporter: i64,
    report: &EndReport,
    now: i64,
) -> Result<CreditOutcome, ApiError> {
    let tx = conn.transaction()?;
    let row: Option<(i64, String, String, Option<i64>)> = tx
        .query_row(
            "SELECT host_account_id, mode, difficulty, ended_at FROM matches WHERE id = ?1",
            params![match_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    let Some((host, mode, difficulty, ended_at)) = row else {
        return Err(ApiError::new(ErrorCode::MatchNotFound, "no such match"));
    };
    if host != reporter {
        return Err(ApiError::new(ErrorCode::NotHostedMatch, "only the host reports a match"));
    }
    if ended_at.is_some() {
        return Ok(CreditOutcome { already_recorded: true, credits: Vec::new() });
    }
    tx.execute(
        "UPDATE matches SET ended_at = ?1, result = ?2, score = ?3, level_reached = ?4, duration_ticks = ?5, campaign_completed = ?6, extra_json = ?7 WHERE id = ?8",
        params![
            now,
            report.result,
            report.score,
            report.level_reached,
            report.duration_ticks,
            report.campaign_completed as i64,
            report.extra_json,
            match_id
        ],
    )?;
    let players: Vec<(i64, Option<i64>)> = {
        let mut statement = tx.prepare("SELECT seat, account_id FROM match_players WHERE match_id = ?1 ORDER BY seat")?;
        let rows = statement.query_map(params![match_id], |row| Ok((row.get(0)?, row.get(1)?)))?;
        rows.collect::<rusqlite::Result<Vec<_>>>()?
    };
    let day_start = utc_day_start(now);
    let mut credits = Vec::new();
    for (seat, account_id) in players {
        let Some(account_id) = account_id else { continue };
        let credited_today: i64 = tx.query_row(
            "SELECT COUNT(*) FROM point_ledger WHERE account_id = ?1 AND reason = 'match_end' AND created_at >= ?2",
            params![account_id, day_start],
            |row| row.get(0),
        )?;
        let points = credit_points(report.score, &difficulty, &mode, credited_today as u32, report.campaign_completed);
        talents::db_credit(&tx, account_id, points, "match_end", &match_id.to_string(), now)?;
        tx.execute(
            "UPDATE match_players SET points_awarded = ?1 WHERE match_id = ?2 AND seat = ?3",
            params![points, match_id, seat],
        )?;
        credits.push((account_id, points));
    }
    tx.commit()?;
    Ok(CreditOutcome { already_recorded: false, credits })
}

pub fn db_abandon(conn: &Connection, ids: &[i64]) -> rusqlite::Result<usize> {
    let now = now_unix();
    let mut changed = 0;
    for id in ids {
        changed += conn.execute(
            "UPDATE matches SET ended_at = ?1, result = 'abandoned' WHERE id = ?2 AND ended_at IS NULL",
            params![now, id],
        )?;
    }
    Ok(changed)
}

pub fn db_abandon_open_older_than(conn: &Connection, seconds: i64, now: i64) -> rusqlite::Result<usize> {
    conn.execute(
        "UPDATE matches SET ended_at = ?1, result = 'abandoned' WHERE ended_at IS NULL AND started_at <= ?2",
        params![now, now - seconds],
    )
}

// ----------------------------------------------------------------- handlers

pub fn handle_start(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let mut start = parse_start(payload)?;
    let now = now_unix();
    let (account, players) = {
        let mut hub = state.hub();
        let account = hub.require_account(sid)?;
        if !hub.require_session_mut(sid)?.bucket_match.try_take() {
            return Err(ApiError::new(ErrorCode::RateLimited, "match reports are rate limited"));
        }
        let mut players: Vec<(i64, Option<i64>, String)> = vec![(0, Some(account.id), account.nickname.clone())];
        if start.kind == "hosted" {
            let Some(lobby) = hub.lobby_hosted_by(sid) else {
                return Err(ApiError::new(ErrorCode::NotHostedMatch, "you are not hosting a lobby"));
            };
            let Some(joiner) = &lobby.joiner else {
                return Err(ApiError::new(ErrorCode::LobbyNotOpen, "the lobby has no second player yet"));
            };
            start.lobby_id = Some(lobby.id.clone());
            start.lobby_name = Some(lobby.name.clone());
            players.push((1, Some(joiner.account_id), joiner.nickname.clone()));
        } else if start.kind == "couch" {
            players.push((1, None, "GUEST".to_string()));
        }
        (account, players)
    };
    let match_id = state.db.with(|conn| {
        let match_id = db_insert_match(conn, &start, account.id, now)?;
        for (seat, account_id, nickname) in &players {
            db_insert_player(conn, match_id, *seat, *account_id, nickname)?;
        }
        Ok(match_id)
    })?;
    {
        let mut hub = state.hub();
        hub.stats.matches_started += 1;
        if let Some(lobby_id) = start.lobby_id.clone() {
            let joiner_session = if let Some(lobby) = hub.lobbies.get_mut(&lobby_id) {
                lobby.state = LobbyState::InMatch;
                lobby.match_id = Some(match_id);
                lobby.joiner.as_ref().map(|j| j.session)
            } else {
                None
            };
            if let Some(session) = hub.session_mut(sid) {
                session.presence = Presence::InMatch { lobby_id: Some(lobby_id.clone()), match_id };
            }
            if let Some(joiner) = joiner_session {
                if let Some(session) = hub.session_mut(joiner) {
                    session.presence = Presence::InMatch { lobby_id: Some(lobby_id.clone()), match_id };
                }
            }
            hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
        } else if let Some(session) = hub.session_mut(sid) {
            session.presence = Presence::InMatch { lobby_id: None, match_id };
        }
    }
    info!(session = sid, match_id, kind = %start.kind, mode = %start.mode, "match started");
    Ok(json!({"match_id": match_id}))
}

pub fn handle_end(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let report = parse_end(payload)?;
    let now = now_unix();
    let account = {
        let mut hub = state.hub();
        let account = hub.require_account(sid)?;
        if !hub.require_session_mut(sid)?.bucket_match.try_take() {
            return Err(ApiError::new(ErrorCode::RateLimited, "match reports are rate limited"));
        }
        account
    };
    let match_id = match field_i64_opt(payload, "match_id")? {
        Some(id) if id > 0 => id,
        _ => {
            let start = parse_start(payload)?;
            if start.kind == "hosted" {
                return Err(ApiError::new(ErrorCode::NotHostedMatch, "hosted matches must report match_start first"));
            }
            state.db.with(|conn| {
                let match_id = db_insert_match(conn, &start, account.id, now - report.duration_ticks.max(0) / 60)?;
                db_insert_player(conn, match_id, 0, Some(account.id), &account.nickname)?;
                if start.kind == "couch" {
                    db_insert_player(conn, match_id, 1, None, "GUEST")?;
                }
                Ok(match_id)
            })?
        }
    };
    let outcome = state.db.with(|conn| db_end_match(conn, match_id, account.id, &report, now))?;
    let reporter_points = outcome.credits.iter().find(|(id, _)| *id == account.id).map(|(_, points)| *points).unwrap_or(0);
    let reporter_state = state.db.with(|conn| talents::state_json(conn, &state.talents, account.id, &account.nickname))?;
    for (other, points) in outcome.credits.iter().filter(|(id, _)| *id != account.id) {
        let Some(other_sid) = state.hub().session_for_account(*other) else { continue };
        let nickname = state.hub().session(other_sid).and_then(|s| s.account.clone()).map(|a| a.nickname).unwrap_or_default();
        let other_state = state.db.with(|conn| talents::state_json(conn, &state.talents, *other, &nickname))?;
        state.hub().send(
            other_sid,
            protocol::push(
                "points_credited",
                json!({"match_id": match_id, "points": points, "reason": "match_end", "state": other_state}),
            ),
        );
    }
    {
        let mut hub = state.hub();
        if !outcome.already_recorded {
            hub.stats.matches_ended += 1;
        }
        let presence = hub.session(sid).map(|s| s.presence.clone()).unwrap_or(Presence::Idle);
        match presence {
            Presence::InMatch { lobby_id: Some(lobby_id), .. } => {
                let joiner_session = if let Some(lobby) = hub.lobbies.get_mut(&lobby_id) {
                    lobby.match_id = None;
                    lobby.state = if lobby.joiner.is_some() { LobbyState::Full } else { LobbyState::Open };
                    lobby.joiner.as_ref().map(|j| j.session)
                } else {
                    None
                };
                if let Some(session) = hub.session_mut(sid) {
                    session.presence = Presence::Hosting(lobby_id.clone());
                }
                if let Some(joiner) = joiner_session {
                    if let Some(session) = hub.session_mut(joiner) {
                        session.presence = Presence::Joined(lobby_id.clone());
                    }
                }
                hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
            }
            Presence::InMatch { lobby_id: None, .. } => {
                if let Some(session) = hub.session_mut(sid) {
                    session.presence = Presence::Idle;
                }
            }
            _ => {}
        }
    }
    info!(session = sid, match_id, points = reporter_points, already = outcome.already_recorded, "match ended");
    Ok(json!({
        "match_id": match_id,
        "points_awarded": reporter_points,
        "already_recorded": outcome.already_recorded,
        "state": reporter_state,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[test]
    fn credit_table() {
        assert_eq!(credit_points(0, "normal", "solo", 0, false), 0);
        assert_eq!(credit_points(0, "normal", "solo", 0, true), 40);
        assert_eq!(credit_points(1_000_000, "normal", "solo", 0, false), 31);
        assert_eq!(credit_points(1_000_000, "ace", "solo", 0, false), 49);
        assert_eq!(credit_points(1_000_000, "easy", "solo", 3, false), 7);
        assert_eq!(credit_points(1_000_000, "normal", "time_trial", 0, true), 23);
        assert_eq!(credit_points(50_000_000, "ace", "solo", 0, true), 250);
        assert_eq!(credit_points(500, "normal", "solo", 6, false), 1);
    }

    #[test]
    fn end_match_credits_once() {
        let db = Db::open_in_memory().unwrap();
        db.with(|conn| {
            let host = crate::accounts::db_create(conn, &[1u8; 32], "Host", 1, "127.0.0.1")?;
            let joiner = crate::accounts::db_create(conn, &[2u8; 32], "Joiner", 1, "127.0.0.1")?;
            let start = MatchStart {
                kind: "hosted".into(),
                mode: "coop".into(),
                difficulty: "normal".into(),
                coop_balance: "classic".into(),
                seed: Some("42".into()),
                start_level: Some(1),
                end_level: Some(3999),
                content_hash: None,
                lobby_id: Some("abc".into()),
                lobby_name: Some("SMOKE".into()),
            };
            let match_id = db_insert_match(conn, &start, host.id, 10)?;
            db_insert_player(conn, match_id, 0, Some(host.id), "Host")?;
            db_insert_player(conn, match_id, 1, Some(joiner.id), "Joiner")?;
            let report = EndReport {
                result: "game_over".into(),
                score: 250_000,
                level_reached: 12,
                duration_ticks: 3600,
                campaign_completed: false,
                extra_json: None,
            };
            let outcome = db_end_match(conn, match_id, host.id, &report, 20)?;
            assert!(!outcome.already_recorded);
            assert_eq!(outcome.credits.len(), 2);
            assert!(outcome.credits.iter().all(|(_, points)| *points == 15));
            let again = db_end_match(conn, match_id, host.id, &report, 21)?;
            assert!(again.already_recorded);
            assert!(again.credits.is_empty());
            let wrong = db_end_match(conn, match_id, joiner.id, &report, 22);
            assert_eq!(wrong.unwrap_err().code, ErrorCode::NotHostedMatch);
            let row = talents::db_load(conn, joiner.id)?;
            assert_eq!(row.points, 15);
            assert_eq!(db_abandon_open_older_than(conn, 0, 30)?, 0);
            let open = db_insert_match(conn, &start, host.id, 5)?;
            assert_eq!(db_abandon(conn, &[open])?, 1);
            Ok(())
        })
        .unwrap();
    }
}
