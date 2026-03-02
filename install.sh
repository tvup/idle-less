#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/tvup/idle-less/master/}"
INSTALL_DIR="${INSTALL_DIR:-.}"
ENABLE_WAKEFORCE=false
WAKEFORCE_ONLY=false

for arg in "$@"; do
  case $arg in
    --wakeforce) ENABLE_WAKEFORCE=true ;;
    --wakeforce-only) ENABLE_WAKEFORCE=true; WAKEFORCE_ONLY=true ;;
    --help|-h)
      echo "Usage: bash install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --wakeforce       Install reverse proxy + Wake-on-LAN gateway"
      echo "  --wakeforce-only  Install Wake-on-LAN gateway only (no reverse proxy)"
      echo "  --help, -h        Show this help message"
      echo ""
      echo "Examples:"
      echo "  bash install.sh                  # Reverse proxy only"
      echo "  bash install.sh --wakeforce      # Full setup with WoL"
      echo "  bash install.sh --wakeforce-only # WoL gateway standalone"
      echo ""
      echo "Documentation: https://github.com/tvup/idle-less"
      exit 0
      ;;
  esac
done

# ── Script loader (local checkout → source; curl|bash → download) ──
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)/scripts"
_DOWNLOAD_DIR=""

load_script() {
  local name="$1"
  if [ -f "$SCRIPTS_DIR/$name" ]; then
    source "$SCRIPTS_DIR/$name"
  else
    [ -z "$_DOWNLOAD_DIR" ] && { _DOWNLOAD_DIR=$(mktemp -d); trap 'rm -rf "$_DOWNLOAD_DIR"' EXIT; }
    curl -fsSL "${BASE_URL}scripts/${name}" -o "$_DOWNLOAD_DIR/${name}"
    source "$_DOWNLOAD_DIR/${name}"
  fi
}

load_script common.sh

if [ "$WAKEFORCE_ONLY" != true ]; then
  load_script install-reverse-proxy.sh
fi

if [ "$ENABLE_WAKEFORCE" = true ]; then
  load_script install-wakeforce.sh
fi

# ── Preflight ──
require_cmd curl
require_cmd docker
docker compose version >/dev/null 2>&1 || { echo "❌ Need docker compose (v2)"; exit 1; }

echo "╔══════════════════════════════════════╗"
echo "║        idle-less installer           ║"
echo "║  Reverse proxy + Wake-on-LAN        ║"
echo "╚══════════════════════════════════════╝"
echo

# ── Domain prompts ──
declare -a DOMAINS=()
declare -a CONFIGS=()

setup_domain() {
  local domain_name="$1"
  local is_primary="${2:-no}"

  echo
  if [ "$is_primary" = "yes" ]; then
    echo "=== Primary Domain Configuration ==="
  else
    echo "=== Additional Domain Configuration ==="
  fi

  local hostname port ip use_https use_ssl certs_host_path

  if [ "$is_primary" = "yes" ]; then
    hostname="${DOMAIN_1_HOSTNAME:-$(prompt HOSTNAME "Enter hostname" "app.example.com")}"
  else
    hostname=$(prompt HOSTNAME "Enter hostname" "")
  fi

  port=$(prompt PORT "Enter backend port" "3080")

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "❌ Port must be 1-65535" >&2
    return 1
  fi

  ip=$(prompt IP "Enter backend IP" "192.168.1.22")

  if ! validate_ip "$ip"; then
    echo "❌ Invalid IP address: $ip" >&2
    return 1
  fi

  if [ "$WAKEFORCE_ONLY" = true ]; then
    use_https="no"
    use_ssl="no"
    certs_host_path=""
  else
    echo
    use_https=$(prompt_optional USE_HTTPS "Does backend use HTTPS? (yes/no)" "no")

    echo
    use_ssl=$(prompt_optional USE_SSL "Enable SSL for this domain? (yes/no)" "yes")

    certs_host_path=""
    if [ "$use_ssl" = "yes" ]; then
      certs_host_path=$(prompt CERTS_HOST_PATH "Directory on host with cert files for ${hostname}" "/etc/letsencrypt/live/${hostname}")
    fi
  fi

  local config_json="{\"hostname\":\"$hostname\",\"port\":\"$port\",\"ip\":\"$ip\",\"use_https\":\"$use_https\",\"is_primary\":\"$is_primary\",\"use_ssl\":\"$use_ssl\",\"certs_host_path\":\"$certs_host_path\"}"

  DOMAINS+=("$hostname")
  CONFIGS+=("$config_json")

  echo "✅ Domain $hostname configured"
}

setup_domain "primary" "yes"

while true; do
  echo
  add_more=$(prompt_optional ADD_MORE "Setup additional domain? (yes/no)" "no")

  if [ "$add_more" != "yes" ]; then
    break
  fi

  setup_domain "additional" "no"
done

# ── Wakeforce domain prompts ──
LICENSE_KEY=""
if [ "$ENABLE_WAKEFORCE" = true ]; then
  prompt_wakeforce_domains
fi

# ── Certificate verification ──
echo
echo "Installing into: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ "$WAKEFORCE_ONLY" != true ]; then
  echo
  echo "Verifying certificate files..."
  NEEDS_SUDO=false
  for idx in "${!CONFIGS[@]}"; do
    config="${CONFIGS[$idx]}"
    USE_SSL=$(config_get "$config" "use_ssl")

    if [ "$USE_SSL" = "yes" ]; then
      D_HOSTNAME=$(config_get "$config" "hostname")
      D_CERTS_PATH=$(config_get "$config" "certs_host_path")

      echo "  ${D_HOSTNAME}:"
      for fname in fullchain.pem privkey.pem; do
        result=$(check_file "${D_CERTS_PATH}/${fname}")
        case $result in
          found)   echo "    ✅ ${fname}" ;;
          sudo)    echo "    🔒 ${fname} (requires sudo)"; NEEDS_SUDO=true ;;
          missing) echo "    ⚠️  ${fname} not found in ${D_CERTS_PATH}/" ;;
        esac
      done
    fi
  done

  if [ "$NEEDS_SUDO" = true ]; then
    echo
    echo "  Some cert files require elevated permissions."
    echo "  Docker runs as root, so the container can read them — no action needed."
  fi
fi

# ── Generate docker-compose.yml ──
echo
echo "Generating docker-compose.yml..."

cat > docker-compose.yml <<'EOF'
services:
EOF

if [ "$WAKEFORCE_ONLY" = true ]; then
  # Wakeforce standalone — no reverse-proxy
  write_wakeforce_services

  echo "" >> docker-compose.yml

  # Networks
  cat >> docker-compose.yml <<'EOF'
networks:
  internal:
    driver: bridge

EOF
  write_wakeforce_networks

  # Volumes
  cat >> docker-compose.yml <<'EOF'
volumes:
EOF
  write_wakeforce_volumes
else
  # Reverse-proxy (optionally with wakeforce)
  write_reverse_proxy_service

  if [ "$ENABLE_WAKEFORCE" = true ]; then
    write_wakeforce_depends_on
    write_wakeforce_services
  fi

  echo "" >> docker-compose.yml

  # Networks
  cat >> docker-compose.yml <<'EOF'
networks:
  internal:
    driver: bridge

EOF

  if [ "$ENABLE_WAKEFORCE" = true ]; then
    write_wakeforce_networks
  fi

  # Volumes
  cat >> docker-compose.yml <<'EOF'
volumes:
  reverse-proxy-nginx-data:
    driver: local
EOF

  if [ "$ENABLE_WAKEFORCE" = true ]; then
    write_wakeforce_volumes
  fi
fi

echo "✅ docker-compose.yml generated"

# ── Write .env ──
echo
echo "Writing .env ..."

cat > .env <<'EOF'
# Domain Configuration (DOMAIN_{i}_* pattern)
EOF

if [ -n "${LICENSE_KEY:-}" ]; then
  cat >> .env <<EOF
LICENSE_KEY=$LICENSE_KEY
EOF
fi

for i in "${!CONFIGS[@]}"; do
  config="${CONFIGS[$i]}"
  DOMAIN_NUM=$((i + 1))
  PREFIX="DOMAIN_${DOMAIN_NUM}"

  D_HOSTNAME=$(config_get "$config" "hostname")
  D_PORT=$(config_get "$config" "port")
  D_IP=$(config_get "$config" "ip")
  D_USE_HTTPS=$(config_get "$config" "use_https")
  D_USE_SSL=$(config_get "$config" "use_ssl")

  if [ $i -eq 0 ]; then
    echo "" >> .env
    echo "# Domain ${DOMAIN_NUM} (primary)" >> .env
  else
    echo "" >> .env
    echo "# Domain ${DOMAIN_NUM}" >> .env
  fi

  cat >> .env <<EOF
${PREFIX}_HOSTNAME=$D_HOSTNAME
${PREFIX}_PORT=$D_PORT
${PREFIX}_IP=$D_IP
EOF

  if [ "$WAKEFORCE_ONLY" != true ]; then
    cat >> .env <<EOF
${PREFIX}_USE_HTTPS=${D_USE_HTTPS:-no}
${PREFIX}_USE_SSL=$D_USE_SSL
EOF

    if [ "$D_USE_SSL" = "yes" ]; then
      D_CERTS_PATH=$(config_get "$config" "certs_host_path")
      cat >> .env <<EOF
${PREFIX}_CERTS_HOST_PATH=$D_CERTS_PATH
EOF
    fi
  fi

  if [ "$ENABLE_WAKEFORCE" = true ]; then
    D_ENABLE_WF=$(config_get "$config" "enable_wakeforce")
    if [ "${D_ENABLE_WF:-}" = "yes" ]; then
      D_CONFIG_TYPE=$(config_get "$config" "config_type")
      D_MAC=$(config_get "$config" "mac")
      D_BROADCAST=$(config_get "$config" "broadcast")
      D_LAN=$(config_get "$config" "lan_interface")
      D_SUBNET=$(config_get "$config" "subnet")
      D_GATEWAY=$(config_get "$config" "gateway")
      D_WF_IP=$(config_get "$config" "wf_ip")
      cat >> .env <<EOF
${PREFIX}_CONFIG=$D_CONFIG_TYPE
${PREFIX}_IDLE_SERVICE=wakeforce_${DOMAIN_NUM}:8182
${PREFIX}_MAC=$D_MAC
${PREFIX}_BROADCAST=$D_BROADCAST
${PREFIX}_LAN=$D_LAN
${PREFIX}_SUBNET=${D_SUBNET:-192.168.1.0/24}
${PREFIX}_GATEWAY=${D_GATEWAY:-192.168.1.1}
${PREFIX}_WF_IP=${D_WF_IP:-192.168.1.240}
EOF
    fi
  fi
done

echo "✅ Configuration saved to .env"
echo

# ── Summary ──
echo "=== Configuration Summary ==="
echo

for i in "${!CONFIGS[@]}"; do
  config="${CONFIGS[$i]}"
  DOMAIN_NUM=$((i + 1))

  D_HOSTNAME=$(config_get "$config" "hostname")
  D_PORT=$(config_get "$config" "port")
  D_IP=$(config_get "$config" "ip")
  D_USE_HTTPS=$(config_get "$config" "use_https")
  D_USE_SSL=$(config_get "$config" "use_ssl")

  if [ $i -eq 0 ]; then
    echo "Domain ${DOMAIN_NUM} (primary):"
  else
    echo "Domain ${DOMAIN_NUM}:"
  fi
  echo "  Hostname: $D_HOSTNAME"
  echo "  Backend: $D_IP:$D_PORT"

  if [ "$WAKEFORCE_ONLY" != true ]; then
    echo "  HTTPS: $D_USE_HTTPS"
    echo "  SSL: $D_USE_SSL"

    if [ "$D_USE_SSL" = "yes" ]; then
      D_CERTS_PATH=$(config_get "$config" "certs_host_path")
      echo "  Certs: $D_CERTS_PATH"
    fi
  fi

  if [ "$ENABLE_WAKEFORCE" = true ]; then
    D_ENABLE_WF=$(config_get "$config" "enable_wakeforce")
    if [ "${D_ENABLE_WF:-}" = "yes" ]; then
      D_MAC=$(config_get "$config" "mac")
      D_BROADCAST=$(config_get "$config" "broadcast")
      D_WF_IP=$(config_get "$config" "wf_ip")
      echo "  Wakeforce: Enabled"
      echo "  MAC: $D_MAC"
      echo "  Broadcast: $D_BROADCAST"
      echo "  WF IP: ${D_WF_IP:-auto}"
    fi
  fi
  echo
done

read -r -p "Continue with installation? (yes/no) [yes]: " CONFIRM < /dev/tty || CONFIRM="yes"
CONFIRM="${CONFIRM:-yes}"

if [ "$CONFIRM" != "yes" ]; then
  echo "Installation cancelled."
  exit 0
fi

echo
echo "Building containers..."
docker compose pull || true
docker compose build

echo
echo "✅ Done. Project dir: $INSTALL_DIR"
echo
echo "Your services are available at:"
for i in "${!CONFIGS[@]}"; do
  config="${CONFIGS[$i]}"
  D_HOSTNAME=$(config_get "$config" "hostname")

  if [ "$WAKEFORCE_ONLY" = true ]; then
    local_port=$((8182 + i))
    echo "  http://${D_HOSTNAME}:${local_port}"
  else
    USE_SSL=$(config_get "$config" "use_ssl")
    if [ "$USE_SSL" = "yes" ]; then
      echo "  https://$D_HOSTNAME"
    else
      echo "  http://$D_HOSTNAME"
    fi
  fi
done
echo
echo "To start:     docker compose up -d"
echo "To view logs: docker compose logs -f"
echo "To stop:      docker compose down"
echo
echo "Documentation: https://github.com/tvup/idle-less"
echo "Support:       info@torbenit.dk"
