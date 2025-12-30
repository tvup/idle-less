#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/tvup/idle-less/master/}"
INSTALL_DIR="${INSTALL_DIR:-.}"
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1"; exit 1; }; }

prompt() {
  local name="$1" text="$2" default="${3:-}" value=""
  if [ -t 0 ]; then
    read -r -p "$text${default:+ [$default]}: " value
  elif [ -r /dev/tty ]; then
    read -r -p "$text${default:+ [$default]}: " value < /dev/tty
  fi
  value="${value:-$default}"
  [ -n "$value" ] || { echo "❌ $name cannot be empty" >&2; exit 1; }
  printf '%s' "$value"
}

require_cmd curl
require_cmd docker
docker compose version >/dev/null 2>&1 || { echo "❌ Need docker compose (v2)"; exit 1; }

echo "== Install the gøgemøg =="
echo

HERO_HOSTNAME="${HERO_HOSTNAME:-$(prompt HERO_HOSTNAME "Enter HERO_HOSTNAME" "chat.christianogfars.online")}"
HERO_HOST_PORT="${HERO_HOST_PORT:-$(prompt HERO_HOST_PORT "Enter HERO_HOST_PORT (e.g. 3080)" "3080")}"
HERO_HOST_IP="${HERO_HOST_IP:-$(prompt HERO_HOST_IP "Enter HERO_HOST_IP" "192.168.1.22")}"
HERO_HOST_MAC="${HERO_HOST_MAC:-$(prompt HERO_HOST_MAC "Enter HERO_HOST_MAC (e.g. D8:9E:F3:12:D0:10)" "D8:9E:F3:12:D0:10")}"
BROADCAST_IP="${BROADCAST_IP:-$(prompt BROADCAST_IP "Enter BROADCAST_IP (e.g. 192.168.1.255)" "192.168.1.255")}"
LAN_INTERFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}' | tr -d '[:space:]')"

 if ! [[ "$HERO_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$HERO_HOST_PORT" -lt 1 ] || [ "$HERO_HOST_PORT" -gt 65535 ]; then
   echo "❌ HERO_HOST_PORT must be 1-65535" >&2
 fi

echo
echo "Installing into: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo
echo "Downloading docker-compose.yml ..."
curl -fsSL "$BASE_URL/docker-compose.yml" -o docker-compose.yml


# curl -fsSL "$BASE_URL/nginx/default.conf.template" -o nginx/default.conf.template
# curl -fsSL "$BASE_URL/entrypoint.sh" -o entrypoint.sh

echo
echo "Writing .env ..."


cat > .env <<EOF
HERO_HOSTNAME=$HERO_HOSTNAME
HERO_HOST_PORT=$HERO_HOST_PORT
HERO_HOST_IP=$HERO_HOST_IP
HERO_HOST_MAC=$HERO_HOST_MAC
BROADCAST_IP=$BROADCAST_IP
LAN_INTERFACE="${LAN_INTERFACE:-eth0}"
EOF

echo "✅ Saved HERO_HOSTNAME, HERO_HOST_PORT, HERO_HOST_IP, HERO_HOST_MAC, BROADCAST_IP, and LAN_INTERFACE in .env"
echo

echo "Starting containers..."
docker compose pull || true
docker compose up -d --build

echo
echo "✅ Done. Project dir: $INSTALL_DIR"
