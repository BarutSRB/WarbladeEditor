#!/bin/sh
# Builds the lobby server for Linux x86_64 on this Mac and installs it on the
# droplet as a systemd service. Usage: make lobby-deploy (DROPLET defaults to
# root@68.183.194.133 in the Makefile; override with DROPLET=user@host).
#
# One-time on the Mac:     cargo install --locked cargo-zigbuild
#                          rustup target add x86_64-unknown-linux-musl --toolchain stable
#                          (the build runs on rustup's stable toolchain, not the PATH cargo)
# One-time on the droplet: sh deploy/ufw.sh (additive firewall rules only).
# The first deploy creates /etc/warblade-lobby/env from deploy/env.example with
# a random WB_ADMIN_TOKEN; read it with: ssh DROPLET cat /etc/warblade-lobby/env
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
droplet=${DROPLET:?set DROPLET=user@host}
target=x86_64-unknown-linux-musl
binary="$here/target/$target/release/warblade-lobby"

# The PATH cargo/rustc may be Homebrew's standalone Rust, which has no musl
# target; put rustup's stable toolchain first so cargo and rustc agree.
stable_bin=$(dirname "$(rustup which cargo --toolchain stable)")
PATH="$stable_bin:$PATH"
export PATH

if ! (cd "$here" && cargo zigbuild --help >/dev/null 2>&1); then
  echo "cargo-zigbuild is missing: run 'cargo install --locked cargo-zigbuild' (zig is installed via Homebrew)" >&2
  exit 1
fi
if ! rustup target list --installed --toolchain stable 2>/dev/null | grep -q "$target"; then
  echo "the $target target is missing: run 'rustup target add $target --toolchain stable'" >&2
  exit 1
fi

(cd "$here" && cargo zigbuild --release --target "$target")

ssh "$droplet" 'set -e
  id -u warblade >/dev/null 2>&1 || useradd --system --home /var/lib/warblade-lobby --shell /usr/sbin/nologin warblade
  mkdir -p /var/lib/warblade-lobby /etc/warblade-lobby /var/backups/warblade-lobby
  chown warblade:warblade /var/lib/warblade-lobby /var/backups/warblade-lobby'

scp "$binary" "$droplet:/usr/local/bin/warblade-lobby.new"
scp "$here/../content/talents.json" "$droplet:/etc/warblade-lobby/talents.json"
scp "$here/deploy/warblade-lobby.service" "$droplet:/etc/systemd/system/warblade-lobby.service"
scp "$here/deploy/backup.sh" "$droplet:/usr/local/bin/warblade-lobby-backup"
scp "$here/deploy/env.example" "$droplet:/etc/warblade-lobby/env.example"

ssh "$droplet" 'set -e
  if ! test -f /etc/warblade-lobby/env; then
    umask 077
    token=$(openssl rand -hex 24)
    sed "s|^WB_ADMIN_TOKEN=.*|WB_ADMIN_TOKEN=$token|" /etc/warblade-lobby/env.example > /etc/warblade-lobby/env.tmp
    grep -q "^WB_ADMIN_TOKEN=$token" /etc/warblade-lobby/env.tmp
    mv /etc/warblade-lobby/env.tmp /etc/warblade-lobby/env
    echo "created /etc/warblade-lobby/env with a new WB_ADMIN_TOKEN (read it with: ssh DROPLET cat /etc/warblade-lobby/env)" >&2
  fi
  chmod 600 /etc/warblade-lobby/env
  mv /usr/local/bin/warblade-lobby.new /usr/local/bin/warblade-lobby
  chmod 755 /usr/local/bin/warblade-lobby /usr/local/bin/warblade-lobby-backup
  systemctl daemon-reload
  systemctl enable --now warblade-lobby
  systemctl restart warblade-lobby
  sleep 1
  systemctl is-active warblade-lobby || { journalctl -u warblade-lobby -n 30 --no-pager; exit 1; }
  printf "%s\n" "0 4 * * * warblade /usr/local/bin/warblade-lobby-backup" > /etc/cron.d/warblade-lobby-backup
  chmod 644 /etc/cron.d/warblade-lobby-backup
  journalctl -u warblade-lobby -n 20 --no-pager'
