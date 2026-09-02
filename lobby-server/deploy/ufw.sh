#!/bin/sh
# Run once on the droplet as root: opens the lobby WebSocket (TCP 7400) and
# the UDP rendezvous (7401). Additive only: the host is shared with other
# services, so this never touches the default policy or the enable state.
# The admin listener (7402) stays closed; reach it through an ssh tunnel
# (make lobby-admin).
set -eu
ufw allow 7400/tcp comment 'warblade lobby websocket'
ufw allow 7401/udp comment 'warblade rendezvous'
ufw status numbered
