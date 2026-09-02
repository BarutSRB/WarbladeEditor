//! UDP rendezvous: a host's game server (and a joiner's probe) sends a nonce
//! datagram from the very socket it will play on; the server records the
//! public endpoint it saw, echoes it back, and tells the session that
//! registered the nonce over WebSocket. Unregistered nonces get no reply, so
//! the socket cannot be used as a reflector.
//!
//! Wire format (big-endian, fixed size):
//!   request 22 B: "WBRZ" | version u8 | kind u8 | nonce[16]
//!   echo    28 B: "WBRZ" | version u8 | kind u8 | nonce[16] | ipv4[4] | port u16
//! The Godot mirror is src/shared/rendezvous_codec.gd.

use std::collections::HashMap;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::Arc;
use std::time::Instant;

use serde_json::json;
use tokio::net::UdpSocket;
use tracing::{debug, warn};

use crate::protocol::{self, Endpoint};
use crate::session::{RendezvousEntry, SessionId};
use crate::state::AppState;

pub const MAGIC: &[u8; 4] = b"WBRZ";
pub const VERSION: u8 = 1;
pub const KIND_PING: u8 = 1;
pub const KIND_ECHO: u8 = 2;
pub const KIND_PUNCH: u8 = 3;
pub const REQUEST_LEN: usize = 22;
pub const ECHO_LEN: usize = 28;
const REPLIES_PER_IP_PER_SEC: u32 = 20;

#[derive(Debug, PartialEq, Eq)]
pub enum Datagram {
    Ping([u8; 16]),
    Punch([u8; 16]),
}

pub fn decode(bytes: &[u8]) -> Option<Datagram> {
    if bytes.len() != REQUEST_LEN || &bytes[..4] != MAGIC || bytes[4] != VERSION {
        return None;
    }
    let mut nonce = [0u8; 16];
    nonce.copy_from_slice(&bytes[6..22]);
    match bytes[5] {
        KIND_PING => Some(Datagram::Ping(nonce)),
        KIND_PUNCH => Some(Datagram::Punch(nonce)),
        _ => None,
    }
}

pub fn encode_ping(nonce: &[u8; 16]) -> [u8; REQUEST_LEN] {
    let mut out = [0u8; REQUEST_LEN];
    out[..4].copy_from_slice(MAGIC);
    out[4] = VERSION;
    out[5] = KIND_PING;
    out[6..22].copy_from_slice(nonce);
    out
}

pub fn encode_echo(nonce: &[u8; 16], observed: SocketAddrV4) -> [u8; ECHO_LEN] {
    let mut out = [0u8; ECHO_LEN];
    out[..4].copy_from_slice(MAGIC);
    out[4] = VERSION;
    out[5] = KIND_ECHO;
    out[6..22].copy_from_slice(nonce);
    out[22..26].copy_from_slice(&observed.ip().octets());
    out[26..28].copy_from_slice(&observed.port().to_be_bytes());
    out
}

/// Records an observation for a registered nonce. Returns the session to
/// notify when the endpoint is new or changed.
fn observe(state: &AppState, nonce: [u8; 16], observed: SocketAddrV4, now: Instant) -> Option<(SessionId, Endpoint)> {
    let mut hub = state.hub();
    hub.stats.udp_received += 1;
    let Some(sid) = hub.sessions.values().find(|session| session.nonce == Some(nonce)).map(|session| session.id) else {
        hub.stats.udp_dropped += 1;
        return None;
    };
    let endpoint = Endpoint { ip: *observed.ip(), port: observed.port() };
    let changed = match hub.rendezvous.get_mut(&nonce) {
        Some(entry) => {
            let changed = entry.public != endpoint || entry.session != sid;
            entry.public = endpoint;
            entry.session = sid;
            entry.last_seen = now;
            changed
        }
        None => {
            hub.rendezvous.insert(
                nonce,
                RendezvousEntry { session: sid, public: endpoint, first_seen: now, last_seen: now },
            );
            true
        }
    };
    hub.stats.udp_echoed += 1;
    if changed {
        for lobby in hub.lobbies.values_mut() {
            if lobby.host == sid {
                lobby.host_public = Some(endpoint);
            }
        }
        Some((sid, endpoint))
    } else {
        None
    }
}

pub async fn run(state: Arc<AppState>, socket: UdpSocket) {
    let mut buffer = [0u8; 64];
    let mut per_ip: HashMap<Ipv4Addr, (u32, Instant)> = HashMap::new();
    loop {
        let (len, source) = match socket.recv_from(&mut buffer).await {
            Ok(received) => received,
            Err(error) => {
                warn!("rendezvous recv failed: {error}");
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                continue;
            }
        };
        let SocketAddr::V4(source) = source else {
            state.hub().stats.udp_dropped += 1;
            continue;
        };
        let Some(Datagram::Ping(nonce)) = decode(&buffer[..len]) else {
            state.hub().stats.udp_dropped += 1;
            continue;
        };
        let now = Instant::now();
        let bucket = per_ip.entry(*source.ip()).or_insert((0, now));
        if now.duration_since(bucket.1).as_secs() >= 1 {
            *bucket = (0, now);
        }
        bucket.0 += 1;
        if bucket.0 > REPLIES_PER_IP_PER_SEC {
            continue;
        }
        if per_ip.len() > 4096 {
            per_ip.retain(|_, (_, started)| now.duration_since(*started).as_secs() < 2);
        }
        let notify = observe(&state, nonce, source, now);
        if notify.is_none() && !state.hub().rendezvous.contains_key(&nonce) {
            // Unregistered nonce: no echo, no reflector.
            continue;
        }
        let echo = encode_echo(&nonce, source);
        if let Err(error) = socket.send_to(&echo, SocketAddr::V4(source)).await {
            debug!("rendezvous echo to {source} failed: {error}");
        }
        if let Some((sid, endpoint)) = notify {
            let hub = state.hub();
            hub.send(
                sid,
                protocol::push(
                    "rendezvous_observed",
                    json!({"nonce": hex::encode(nonce), "public": endpoint.to_json(), "observed_at": crate::db::now_unix()}),
                ),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn datagram_round_trip() {
        let nonce = [7u8; 16];
        let ping = encode_ping(&nonce);
        assert_eq!(decode(&ping), Some(Datagram::Ping(nonce)));
        let mut punch = ping;
        punch[5] = KIND_PUNCH;
        assert_eq!(decode(&punch), Some(Datagram::Punch(nonce)));
        let echo = encode_echo(&nonce, SocketAddrV4::new(Ipv4Addr::new(203, 0, 113, 9), 42000));
        assert_eq!(echo.len(), ECHO_LEN);
        assert_eq!(&echo[..4], MAGIC);
        assert_eq!(echo[5], KIND_ECHO);
        assert_eq!(&echo[22..26], &[203, 0, 113, 9]);
        assert_eq!(u16::from_be_bytes([echo[26], echo[27]]), 42000);
        assert_eq!(decode(&ping[..21]), None);
        let mut wrong_magic = ping;
        wrong_magic[0] = b'X';
        assert_eq!(decode(&wrong_magic), None);
        let mut wrong_version = ping;
        wrong_version[4] = 9;
        assert_eq!(decode(&wrong_version), None);
        let mut unknown_kind = ping;
        unknown_kind[5] = 9;
        assert_eq!(decode(&unknown_kind), None);
    }
}
