#!/usr/bin/env bash
#
# Black Ops Gunfight — VPS deploy helper.
# Pulls the latest release, places the mod files, and restarts the
# Plutonium T5 server (systemd). Run this ON THE VPS.
#
# ── CONFIGURE THESE THREE FOR YOUR BOX ─────────────────────────────────────────
#   SERVICE_NAME  systemd unit that runs the server
#                 (find it: systemctl list-units --type=service | grep -i pluto)
#   MOD_DIR       directory the server loads mod.ff from
#   SCRIPTS_DIR   raw GSC overlay the server reads (maps/mp/gametypes/*.gsc)
# ──────────────────────────────────────────────────────────────────────────────
SERVICE_NAME="plutonium-t5.service"
MOD_DIR="/opt/plutonium/storage/t5/mods/gunfight"
SCRIPTS_DIR="/opt/plutonium/storage/t5/scripts"

# Which git branch to deploy from.
BRANCH="release"

set -euo pipefail

# Resolve repo root (this script lives in <repo>/scripts/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Pre-flight checks --------------------------------------------------------
[ -d "$MOD_DIR" ]     || die "MOD_DIR does not exist: $MOD_DIR (edit the top of this script)"
[ -d "$SCRIPTS_DIR" ] || die "SCRIPTS_DIR does not exist: $SCRIPTS_DIR (edit the top of this script)"
command -v systemctl >/dev/null || die "systemctl not found — is this the systemd VPS?"

# --- 1. Pull latest -----------------------------------------------------------
log "Fetching latest '$BRANCH'…"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

DEPLOYED_REV="$(git rev-parse --short HEAD)"

# --- 2. Place files -----------------------------------------------------------
log "Copying mod.ff → $MOD_DIR"
install -m 0644 mod.ff "$MOD_DIR/mod.ff"

log "Copying GSC scripts → $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR/maps/mp/gametypes"
cp -f maps/mp/gametypes/*.gsc "$SCRIPTS_DIR/maps/mp/gametypes/"

# --- 3. Restart server --------------------------------------------------------
log "Restarting $SERVICE_NAME…"
sudo systemctl restart "$SERVICE_NAME"

sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
  log "Server is up. Deployed revision: $DEPLOYED_REV"
else
  die "Service is not active after restart — check: sudo journalctl -u $SERVICE_NAME -n 100"
fi
