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

prompt_optional() {
  local name="$1" text="$2" default="${3:-}" value=""
  if [ -t 0 ]; then
    read -r -p "$text${default:+ [$default]}: " value
  elif [ -r /dev/tty ]; then
    read -r -p "$text${default:+ [$default]}: " value < /dev/tty
  fi
  printf '%s' "${value:-$default}"
}

require_cmd curl
require_cmd docker
docker compose version >/dev/null 2>&1 || { echo "❌ Need docker compose (v2)"; exit 1; }

echo "== Install the gøgemøg =="
echo

# Array til at holde domæne konfigurationer
declare -a DOMAINS=()
declare -a CONFIGS=()

# Funktion til at setup et domæne
setup_domain() {
  local domain_name="$1"
  local is_primary="${2:-no}"

  echo
  if [ "$is_primary" = "yes" ]; then
    echo "=== Primary Domain Configuration ==="
  else
    echo "=== Additional Domain Configuration ==="
  fi

  local hostname port ip mac broadcast lan_interface enable_wf config_type
  local use_ssl ssl_cert ssl_key

  if [ "$is_primary" = "yes" ]; then
    hostname="${BACKEND_HOSTNAME:-$(prompt BACKEND_HOSTNAME "Enter hostname" "chat.christianogfars.online")}"
  else
    hostname=$(prompt HOSTNAME "Enter hostname" "")
  fi

  port=$(prompt PORT "Enter backend port" "3080")

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "❌ Port must be 1-65535" >&2
    return 1
  fi

  ip=$(prompt IP "Enter backend IP" "192.168.1.22")

  echo
  enable_wf=$(prompt_optional ENABLE_WAKEFORCE "Enable Wakeforce for this domain? (yes/no)" "yes")

  mac=""
  broadcast=""
  lan_interface=""

  if [ "$enable_wf" = "yes" ]; then
    mac=$(prompt MAC "Enter MAC address (e.g. D8:9E:F3:12:D0:10)" "D8:9E:F3:12:D0:10")
    broadcast=$(prompt BROADCAST "Enter broadcast IP (e.g. 192.168.1.255)" "192.168.1.255")
    lan_interface="$(ip route show default 2>/dev/null | awk '{print $5; exit}' | tr -d '[:space:]')"
    lan_interface="${lan_interface:-eth0}"
    config_type="default"
  else
    config_type="backend"
  fi

  echo
  use_ssl=$(prompt_optional USE_SSL "Enable SSL for this domain? (yes/no)" "yes")

  ssl_cert=""
  ssl_key=""

  if [ "$use_ssl" = "yes" ]; then
    ssl_cert=$(prompt SSL_CERT "Enter SSL certificate path" "/etc/ssl/certs/${hostname}.crt")
    ssl_key=$(prompt SSL_KEY "Enter SSL key path" "/etc/ssl/private/${hostname}.key")
  fi

  # Gem konfiguration
  local config_json="{\"hostname\":\"$hostname\",\"port\":\"$port\",\"ip\":\"$ip\",\"mac\":\"$mac\",\"broadcast\":\"$broadcast\",\"lan_interface\":\"$lan_interface\",\"enable_wakeforce\":\"$enable_wf\",\"config_type\":\"$config_type\",\"is_primary\":\"$is_primary\",\"use_ssl\":\"$use_ssl\",\"ssl_cert\":\"$ssl_cert\",\"ssl_key\":\"$ssl_key\"}"

  DOMAINS+=("$hostname")
  CONFIGS+=("$config_json")

  echo "✅ Domain $hostname configured"
}

# Setup primary domain
setup_domain "primary" "yes"

# Setup additional domains
while true; do
  echo
  add_more=$(prompt_optional ADD_MORE "Setup additional domain? (yes/no)" "no")

  if [ "$add_more" != "yes" ]; then
    break
  fi

  setup_domain "additional" "no"
done

echo
echo "Installing into: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/certs"
cd "$INSTALL_DIR"

echo
echo "Downloading SSL certificates if needed..."
# Download SSL certificates hvis de er URLs
for config in "${CONFIGS[@]}"; do
  CONFIG_CLEAN=$(echo "$config" | sed 's/[{}]//g' | sed 's/"//g')
  USE_SSL=$(echo "$CONFIG_CLEAN" | grep -o 'use_ssl:[^,]*' | cut -d: -f2)

  if [ "$USE_SSL" = "yes" ]; then
    SSL_CERT=$(echo "$CONFIG_CLEAN" | grep -o 'ssl_cert:[^,]*' | cut -d: -f2-)
    SSL_KEY=$(echo "$CONFIG_CLEAN" | grep -o 'ssl_key:[^,]*' | cut -d: -f2-)

    if [[ "$SSL_CERT" == http* ]]; then
      HOSTNAME=$(echo "$CONFIG_CLEAN" | grep -o 'hostname:[^,]*' | cut -d: -f2)
      curl -fsSL "$SSL_CERT" -o "certs/${HOSTNAME}.crt"
    fi

    if [[ "$SSL_KEY" == http* ]]; then
      HOSTNAME=$(echo "$CONFIG_CLEAN" | grep -o 'hostname:[^,]*' | cut -d: -f2)
      curl -fsSL "$SSL_KEY" -o "certs/${HOSTNAME}.key"
    fi
  fi
done

echo
echo "Generating docker-compose.yml..."

# Start docker-compose.yml
cat > docker-compose.yml <<'EOF'
services:
  reverse-proxy:
    image: tvup/reverse-proxy:latest
    container_name: reverse-proxy
    ports:
      - "80:80"
      - "443:443"
    environment:
      BACKEND_HOSTNAME: ${BACKEND_HOSTNAME}
      BACKEND_PORT: ${BACKEND_PORT}
      BACKEND_IP: ${BACKEND_IP}
      PRIMARY_CONFIG: ${PRIMARY_CONFIG}
      PRIMARY_USE_SSL: ${PRIMARY_USE_SSL:-no}
      PRIMARY_SSL_CERT: ${PRIMARY_SSL_CERT:-}
      PRIMARY_SSL_KEY: ${PRIMARY_SSL_KEY:-}
      BACKEND_MAC: ${BACKEND_MAC:-}
      EXTRA_DOMAINS: ${EXTRA_DOMAINS:-}
EOF

# Tilføj environment variables for alle additional domains
for i in "${!CONFIGS[@]}"; do
  if [ $i -eq 0 ]; then
    continue  # Skip primary
  fi

  cat >> docker-compose.yml <<EOF
      DOMAIN_${i}_HOSTNAME: \${DOMAIN_${i}_HOSTNAME:-}
      DOMAIN_${i}_IP: \${DOMAIN_${i}_IP:-}
      DOMAIN_${i}_PORT: \${DOMAIN_${i}_PORT:-}
      DOMAIN_${i}_CONFIG: \${DOMAIN_${i}_CONFIG:-}
      DOMAIN_${i}_USE_SSL: \${DOMAIN_${i}_USE_SSL:-no}
      DOMAIN_${i}_SSL_CERT: \${DOMAIN_${i}_SSL_CERT:-}
      DOMAIN_${i}_SSL_KEY: \${DOMAIN_${i}_SSL_KEY:-}
      DOMAIN_${i}_MAC: \${DOMAIN_${i}_MAC:-}
EOF
done

# Fortsæt reverse-proxy config
cat >> docker-compose.yml <<'EOF'
    volumes:
      - ./certs:/etc/ssl:ro
      - reverse-proxy-nginx-data:/etc/nginx/conf.d
    networks:
      - internal
    restart: unless-stopped
EOF

# Tilføj depends_on hvis der er wakeforce services
HAS_WAKEFORCE=false
for config in "${CONFIGS[@]}"; do
  CONFIG_CLEAN=$(echo "$config" | sed 's/[{}]//g' | sed 's/"//g')
  ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)
  if [ "$ENABLE_WF" = "yes" ]; then
    HAS_WAKEFORCE=true
    break
  fi
done

if [ "$HAS_WAKEFORCE" = true ]; then
  cat >> docker-compose.yml <<'EOF'
    depends_on:
EOF

  for i in "${!CONFIGS[@]}"; do
    CONFIG="${CONFIGS[$i]}"
    CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')
    ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)

    if [ "$ENABLE_WF" = "yes" ]; then
      if [ $i -eq 0 ]; then
        echo "      - wakeforce_primary" >> docker-compose.yml
      else
        echo "      - wakeforce_${i}" >> docker-compose.yml
      fi
    fi
  done
fi

echo "" >> docker-compose.yml

# Generer wakeforce services dynamisk
for i in "${!CONFIGS[@]}"; do
  CONFIG="${CONFIGS[$i]}"
  CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

  ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)

  if [ "$ENABLE_WF" = "yes" ]; then
    if [ $i -eq 0 ]; then
      SERVICE_NAME="wakeforce_primary"
      IP_VAR="BACKEND_IP"
      PORT_VAR="BACKEND_PORT"
      MAC_VAR="BACKEND_MAC"
      BROADCAST_VAR="BROADCAST_IP"
      LAN_VAR="LAN_INTERFACE"
      NETWORK_NAME="lan_primary"
    else
      SERVICE_NAME="wakeforce_${i}"
      IP_VAR="DOMAIN_${i}_IP"
      PORT_VAR="DOMAIN_${i}_PORT"
      MAC_VAR="DOMAIN_${i}_MAC"
      BROADCAST_VAR="DOMAIN_${i}_BROADCAST"
      LAN_VAR="DOMAIN_${i}_LAN"
      NETWORK_NAME="lan_${i}"
    fi

    cat >> docker-compose.yml <<EOF
  ${SERVICE_NAME}:
    image: tvup/wakeforce:latest
    container_name: ${SERVICE_NAME}
    environment:
      BACKEND_IP: \${${IP_VAR}}
      BACKEND_PORT: \${${PORT_VAR}}
      BACKEND_MAC: \${${MAC_VAR}}
      BROADCAST_IP: \${${BROADCAST_VAR}}
      LICENSE_KEY: \${LICENSE_KEY:-}
      LICENSE_CACHE_TTL_SECONDS: "86400"
    restart: unless-stopped
    volumes:
      - ${SERVICE_NAME}_license:/var/lib/wakeforce/license
    expose:
      - "8182"
    networks:
      internal: {}
      ${NETWORK_NAME}: {}
    cap_add:
      - NET_RAW

EOF
  fi
done

# Generer networks
cat >> docker-compose.yml <<'EOF'
networks:
  internal:
    driver: bridge

EOF

# Generer LAN networks for hver wakeforce
for i in "${!CONFIGS[@]}"; do
  CONFIG="${CONFIGS[$i]}"
  CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

  ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)

  if [ "$ENABLE_WF" = "yes" ]; then
    if [ $i -eq 0 ]; then
      NETWORK_NAME="lan_primary"
      LAN_VAR="LAN_INTERFACE"
    else
      NETWORK_NAME="lan_${i}"
      LAN_VAR="DOMAIN_${i}_LAN"
    fi

    cat >> docker-compose.yml <<EOF
  ${NETWORK_NAME}:
    driver: macvlan
    driver_opts:
      parent: \${${LAN_VAR}:-eth0}
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1

EOF
  fi
done

# Generer volumes
cat >> docker-compose.yml <<'EOF'
volumes:
  reverse-proxy-nginx-data:
    driver: local
EOF

# Generer license volumes for hver wakeforce
for i in "${!CONFIGS[@]}"; do
  CONFIG="${CONFIGS[$i]}"
  CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

  ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)

  if [ "$ENABLE_WF" = "yes" ]; then
    if [ $i -eq 0 ]; then
      echo "  wakeforce_primary_license:" >> docker-compose.yml
    else
      echo "  wakeforce_${i}_license:" >> docker-compose.yml
    fi
  fi
done

echo "✅ docker-compose.yml generated"

echo
echo "Writing .env ..."

# Parse first (primary) domain config
PRIMARY_CONFIG=$(echo "${CONFIGS[0]}" | sed 's/[{}]//g' | sed 's/"//g')
PRIMARY_HOSTNAME=$(echo "$PRIMARY_CONFIG" | grep -o 'hostname:[^,]*' | cut -d: -f2)
PRIMARY_PORT=$(echo "$PRIMARY_CONFIG" | grep -o 'port:[^,]*' | cut -d: -f2)
PRIMARY_IP=$(echo "$PRIMARY_CONFIG" | grep -o 'ip:[^,]*' | cut -d: -f2)
PRIMARY_MAC=$(echo "$PRIMARY_CONFIG" | grep -o 'mac:[^,]*' | cut -d: -f2)
PRIMARY_BROADCAST=$(echo "$PRIMARY_CONFIG" | grep -o 'broadcast:[^,]*' | cut -d: -f2)
PRIMARY_LAN=$(echo "$PRIMARY_CONFIG" | grep -o 'lan_interface:[^,]*' | cut -d: -f2)
PRIMARY_ENABLE_WF=$(echo "$PRIMARY_CONFIG" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)
PRIMARY_CONFIG_TYPE=$(echo "$PRIMARY_CONFIG" | grep -o 'config_type:[^,]*' | cut -d: -f2)
PRIMARY_USE_SSL=$(echo "$PRIMARY_CONFIG" | grep -o 'use_ssl:[^,]*' | cut -d: -f2)
PRIMARY_SSL_CERT=$(echo "$PRIMARY_CONFIG" | grep -o 'ssl_cert:[^,]*' | cut -d: -f2-)
PRIMARY_SSL_KEY=$(echo "$PRIMARY_CONFIG" | grep -o 'ssl_key:[^,]*' | cut -d: -f2-)

# Skriv primary domain til .env
cat > .env <<EOF
# Primary Domain Configuration
BACKEND_HOSTNAME=$PRIMARY_HOSTNAME
BACKEND_PORT=$PRIMARY_PORT
BACKEND_IP=$PRIMARY_IP
PRIMARY_CONFIG=$PRIMARY_CONFIG_TYPE
PRIMARY_USE_SSL=$PRIMARY_USE_SSL
EOF

if [ "$PRIMARY_USE_SSL" = "yes" ]; then
  cat >> .env <<EOF
PRIMARY_SSL_CERT=$PRIMARY_SSL_CERT
PRIMARY_SSL_KEY=$PRIMARY_SSL_KEY
EOF
fi

if [ "$PRIMARY_ENABLE_WF" = "yes" ]; then
  cat >> .env <<EOF
BACKEND_MAC=$PRIMARY_MAC
BROADCAST_IP=$PRIMARY_BROADCAST
LAN_INTERFACE=$PRIMARY_LAN
EOF
fi

# Håndter additional domains
if [ ${#CONFIGS[@]} -gt 1 ]; then
  echo "" >> .env
  echo "# Additional Domains" >> .env

  EXTRA_DOMAINS_STR=""

  for i in "${!CONFIGS[@]}"; do
    if [ $i -eq 0 ]; then
      continue  # Skip primary
    fi

    CONFIG="${CONFIGS[$i]}"
    CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

    HOSTNAME=$(echo "$CONFIG_CLEAN" | grep -o 'hostname:[^,]*' | cut -d: -f2)
    PORT=$(echo "$CONFIG_CLEAN" | grep -o 'port:[^,]*' | cut -d: -f2)
    IP=$(echo "$CONFIG_CLEAN" | grep -o 'ip:[^,]*' | cut -d: -f2)
    MAC=$(echo "$CONFIG_CLEAN" | grep -o 'mac:[^,]*' | cut -d: -f2)
    BROADCAST=$(echo "$CONFIG_CLEAN" | grep -o 'broadcast:[^,]*' | cut -d: -f2)
    LAN=$(echo "$CONFIG_CLEAN" | grep -o 'lan_interface:[^,]*' | cut -d: -f2)
    ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)
    CONFIG_TYPE=$(echo "$CONFIG_CLEAN" | grep -o 'config_type:[^,]*' | cut -d: -f2)
    USE_SSL=$(echo "$CONFIG_CLEAN" | grep -o 'use_ssl:[^,]*' | cut -d: -f2)
    SSL_CERT=$(echo "$CONFIG_CLEAN" | grep -o 'ssl_cert:[^,]*' | cut -d: -f2-)
    SSL_KEY=$(echo "$CONFIG_CLEAN" | grep -o 'ssl_key:[^,]*' | cut -d: -f2-)

    # Byg domain config string
    if [ -n "$EXTRA_DOMAINS_STR" ]; then
      EXTRA_DOMAINS_STR="${EXTRA_DOMAINS_STR},"
    fi
    EXTRA_DOMAINS_STR="${EXTRA_DOMAINS_STR}${HOSTNAME}:${CONFIG_TYPE}"

    # Skriv individuelle env vars for dette domæne
    DOMAIN_PREFIX="DOMAIN_${i}"
    cat >> .env <<EOF
${DOMAIN_PREFIX}_HOSTNAME=$HOSTNAME
${DOMAIN_PREFIX}_PORT=$PORT
${DOMAIN_PREFIX}_IP=$IP
${DOMAIN_PREFIX}_CONFIG=$CONFIG_TYPE
${DOMAIN_PREFIX}_USE_SSL=$USE_SSL
EOF

    if [ "$USE_SSL" = "yes" ]; then
      cat >> .env <<EOF
${DOMAIN_PREFIX}_SSL_CERT=$SSL_CERT
${DOMAIN_PREFIX}_SSL_KEY=$SSL_KEY
EOF
    fi

    if [ "$ENABLE_WF" = "yes" ]; then
      cat >> .env <<EOF
${DOMAIN_PREFIX}_MAC=$MAC
${DOMAIN_PREFIX}_BROADCAST=$BROADCAST
${DOMAIN_PREFIX}_LAN=$LAN
EOF
    fi
  done

  echo "EXTRA_DOMAINS=$EXTRA_DOMAINS_STR" >> .env
fi

echo "✅ Configuration saved to .env"
echo

# Vis opsummering
echo "=== Configuration Summary ==="
echo
echo "Primary Domain:"
echo "  Hostname: $PRIMARY_HOSTNAME"
echo "  Backend: $PRIMARY_IP:$PRIMARY_PORT"
echo "  Config: $PRIMARY_CONFIG_TYPE"
echo "  SSL: $PRIMARY_USE_SSL"
if [ "$PRIMARY_USE_SSL" = "yes" ]; then
  echo "  Certificate: $PRIMARY_SSL_CERT"
  echo "  Key: $PRIMARY_SSL_KEY"
fi
if [ "$PRIMARY_ENABLE_WF" = "yes" ]; then
  echo "  Wakeforce: Enabled"
  echo "  MAC: $PRIMARY_MAC"
  echo "  Broadcast: $PRIMARY_BROADCAST"
fi

if [ ${#CONFIGS[@]} -gt 1 ]; then
  echo
  echo "Additional Domains:"
  for i in "${!CONFIGS[@]}"; do
    if [ $i -eq 0 ]; then
      continue
    fi

    CONFIG="${CONFIGS[$i]}"
    CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

    HOSTNAME=$(echo "$CONFIG_CLEAN" | grep -o 'hostname:[^,]*' | cut -d: -f2)
    PORT=$(echo "$CONFIG_CLEAN" | grep -o 'port:[^,]*' | cut -d: -f2)
    IP=$(echo "$CONFIG_CLEAN" | grep -o 'ip:[^,]*' | cut -d: -f2)
    ENABLE_WF=$(echo "$CONFIG_CLEAN" | grep -o 'enable_wakeforce:[^,]*' | cut -d: -f2)
    CONFIG_TYPE=$(echo "$CONFIG_CLEAN" | grep -o 'config_type:[^,]*' | cut -d: -f2)
    USE_SSL=$(echo "$CONFIG_CLEAN" | grep -o 'use_ssl:[^,]*' | cut -d: -f2)

    echo "  [$i] $HOSTNAME"
    echo "      Backend: $IP:$PORT"
    echo "      Config: $CONFIG_TYPE"
    echo "      SSL: $USE_SSL"
    if [ "$ENABLE_WF" = "yes" ]; then
      echo "      Wakeforce: Enabled"
    fi
  done
fi

echo

read -r -p "Continue with installation? (yes/no) [yes]: " CONFIRM < /dev/tty || CONFIRM="yes"
CONFIRM="${CONFIRM:-yes}"

if [ "$CONFIRM" != "yes" ]; then
  echo "Installation cancelled."
  exit 0
fi

echo
echo "Starting containers..."
docker compose pull || true
docker compose up -d --build

echo
echo "✅ Done. Project dir: $INSTALL_DIR"
echo
echo "Your services are available at:"
for i in "${!CONFIGS[@]}"; do
  CONFIG="${CONFIGS[$i]}"
  CONFIG_CLEAN=$(echo "$CONFIG" | sed 's/[{}]//g' | sed 's/"//g')

  HOSTNAME=$(echo "$CONFIG_CLEAN" | grep -o 'hostname:[^,]*' | cut -d: -f2)
  USE_SSL=$(echo "$CONFIG_CLEAN" | grep -o 'use_ssl:[^,]*' | cut -d: -f2)

  if [ "$USE_SSL" = "yes" ]; then
    echo "  https://$HOSTNAME"
  else
    echo "  http://$HOSTNAME"
  fi
done
echo
echo "To view logs: docker compose logs -f"
echo "To stop: docker compose down"