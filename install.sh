#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/tvup/wakeforce/master/}"
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

HERO_HOST="${HERO_HOST:-$(prompt HERO_HOST "Enter HERO_HOST (e.g. hero or hero.internal or an IP)" "192.168.1.22")}"
HERO_PORT="${HERO_PORT:-$(prompt HERO_PORT "Enter HERO_PORT (e.g. 3080)" "3080")}"
HERO_MAC="${HERO_MAC:-$(prompt HERO_MAC "Enter HERO_MAC (e.g. D8:9E:F3:12:D0:10)" "D8:9E:F3:12:D0:10")}"
HERO_BROADCAST="${HERO_BROADCAST:-$(prompt HERO_BROADCAST "Enter HERO_BROADCAST (e.g. 192.168.1.255)" "192.168.1.255")}"

if ! [[ "$HERO_PORT" =~ ^[0-9]+$ ]] || [ "$HERO_PORT" -lt 1 ] || [ "$HERO_PORT" -gt 65535 ]; then
  echo "❌ HERO_PORT must be 1-65535" >&2
  exit 1
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
LAN_IFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}' | tr -d '[:space:]')"

cat > .env <<EOF
HERO_HOST=$HERO_HOST
HERO_PORT=$HERO_PORT
HERO_MAC=$HERO_MAC
HERO_BROADCAST=$HERO_BROADCAST
LAN_IFACE="${LAN_IFACE:-eth0}"
STAND_IN_PORT=80
HEALTH_PATH="/health"
EOF

echo "✅ Saved HERO_HOST, HERO_PORT, HERO_MAC, HERO_BROADCAST, and LAN_IFACE in .env"
echo

echo "Starting containers..."
docker compose pull || true
docker compose up -d --build

echo
echo "✅ Done. Project dir: $INSTALL_DIR"
