#!/usr/bin/env bash
# Generates wakeforce services in docker-compose.yml.
# Expects: CONFIGS array populated, docker-compose.yml started.
# Requires: prompt(), config_get() from common.sh
# Supports: standalone mode (WAKEFORCE_ONLY=true) with direct port mapping.

# Prompt per domain for wakeforce settings, then for LICENSE_KEY.
# Updates CONFIGS array with wakeforce fields.
prompt_wakeforce_domains() {
  local updated_configs=()

  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    local D_HOSTNAME
    D_HOSTNAME=$(config_get "$config" "hostname")

    local enable_wf
    if [ "$WAKEFORCE_ONLY" = true ]; then
      enable_wf="yes"
    else
      echo
      enable_wf=$(prompt_optional ENABLE_WAKEFORCE "Enable Wakeforce for ${D_HOSTNAME}? (yes/no)" "yes")
    fi

    if [ "$enable_wf" = "yes" ]; then
      local mac broadcast lan_interface subnet gateway wf_ip
      mac=$(prompt MAC "Enter MAC address for ${D_HOSTNAME} (e.g. D8:9E:F3:12:D0:10)" "D8:9E:F3:12:D0:10")
      broadcast=$(prompt BROADCAST "Enter broadcast IP for ${D_HOSTNAME} (e.g. 192.168.1.255)" "192.168.1.255")

      # Detect default network interface and subnet
      lan_interface="$(ip route show default 2>/dev/null | awk '{print $5; exit}' | tr -d '[:space:]')"
      lan_interface="${lan_interface:-eth0}"

      # Detect subnet and gateway from interface
      local detected_subnet detected_gateway
      detected_subnet="$(ip -o -4 addr show "$lan_interface" 2>/dev/null | awk '{print $4}' | head -1)"
      detected_gateway="$(ip route show default 2>/dev/null | awk '{print $3; exit}' | tr -d '[:space:]')"

      # Convert CIDR to network address for subnet (e.g. 192.168.1.15/24 → 192.168.1.0/24)
      if [ -n "$detected_subnet" ]; then
        local ip_part cidr_part
        ip_part="${detected_subnet%/*}"
        cidr_part="${detected_subnet#*/}"
        # Simple /24 assumption for common home networks
        local network_prefix="${ip_part%.*}.0"
        detected_subnet="${network_prefix}/${cidr_part}"
      fi

      subnet=$(prompt_optional SUBNET "LAN subnet" "${detected_subnet:-192.168.1.0/24}")
      gateway=$(prompt_optional GATEWAY "LAN gateway" "${detected_gateway:-192.168.1.1}")

      # Static IP for the Wakeforce container on macvlan
      local default_wf_ip="${gateway%.*}.240"
      wf_ip=$(prompt WF_IP "Static IP for Wakeforce container on LAN (must be unused)" "$default_wf_ip")

      # Append wakeforce fields to config JSON
      updated_configs+=("${config%\}},\"enable_wakeforce\":\"yes\",\"config_type\":\"wakeforce\",\"mac\":\"$mac\",\"broadcast\":\"$broadcast\",\"lan_interface\":\"$lan_interface\",\"subnet\":\"$subnet\",\"gateway\":\"$gateway\",\"wf_ip\":\"$wf_ip\"}")
    else
      updated_configs+=("${config%\}},\"enable_wakeforce\":\"no\",\"config_type\":\"default\"}")
    fi
  done

  CONFIGS=("${updated_configs[@]}")

  # Prompt for LICENSE_KEY if at least one domain has wakeforce
  LICENSE_KEY=""
  local has_wf=false
  for config in "${CONFIGS[@]}"; do
    if [ "$(config_get "$config" "enable_wakeforce")" = "yes" ]; then
      has_wf=true
      break
    fi
  done

  if [ "$has_wf" = true ]; then
    echo
    while true; do
      LICENSE_KEY=$(prompt LICENSE_KEY "Enter Wakeforce license key")
      echo "  Validating license..."
      local result
      result=$(curl -sf -X POST https://validate.torbenit.dk/api/v1/validate \
        -H "Content-Type: application/json" \
        -d "{\"licenseKey\":\"$LICENSE_KEY\",\"product\":\"wakeforce\"}" 2>/dev/null) || true
      if echo "$result" | grep -q '"ok":true'; then
        echo "  ✅ License validated"
        break
      else
        local msg
        msg=$(echo "$result" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo "  ❌ ${msg:-License validation failed}. Try again."
      fi
    done
  fi
}

# Insert depends_on block into the reverse-proxy service.
write_wakeforce_depends_on() {
  local has_wf=false
  for config in "${CONFIGS[@]}"; do
    if [ "$(config_get "$config" "enable_wakeforce")" = "yes" ]; then
      has_wf=true
      break
    fi
  done

  if [ "$has_wf" != true ]; then
    return
  fi

  # Build multiline depends_on block
  local deps
  deps="    depends_on:"
  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    if [ "$(config_get "$config" "enable_wakeforce")" = "yes" ]; then
      local DOMAIN_NUM=$((i + 1))
      deps="${deps}
      - wakeforce_${DOMAIN_NUM}"
    fi
  done

  # Insert after the reverse-proxy restart line (only one exists at this point)
  awk -v block="$deps" '/^    restart: unless-stopped$/ { print; print block; next } 1' \
    docker-compose.yml > docker-compose.yml.tmp
  mv docker-compose.yml.tmp docker-compose.yml
}

# Append wakeforce service blocks to docker-compose.yml.
write_wakeforce_services() {
  echo "" >> docker-compose.yml

  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    if [ "$(config_get "$config" "enable_wakeforce")" != "yes" ]; then
      continue
    fi

    local DOMAIN_NUM=$((i + 1))
    local SERVICE_NAME="wakeforce_${DOMAIN_NUM}"
    local HOSTNAME_VAR="DOMAIN_${DOMAIN_NUM}_HOSTNAME"
    local IP_VAR="DOMAIN_${DOMAIN_NUM}_IP"
    local PORT_VAR="DOMAIN_${DOMAIN_NUM}_PORT"
    local MAC_VAR="DOMAIN_${DOMAIN_NUM}_MAC"
    local BROADCAST_VAR="DOMAIN_${DOMAIN_NUM}_BROADCAST"
    local NETWORK_NAME="lan_${DOMAIN_NUM}"

    cat >> docker-compose.yml <<EOF
  ${SERVICE_NAME}:
    image: tvup/wakeforce:latest
    container_name: ${SERVICE_NAME}
    environment:
      BACKEND_HOSTNAME: \${${HOSTNAME_VAR}}
      BACKEND_IP: \${${IP_VAR}}
      BACKEND_PORT: \${${PORT_VAR}}
      BACKEND_MAC: \${${MAC_VAR}}
      BROADCAST_IP: \${${BROADCAST_VAR}}
      LICENSE_KEY: \${LICENSE_KEY:-}
      LICENSE_CACHE_TTL_SECONDS: "86400"
    restart: unless-stopped
    volumes:
      - ${SERVICE_NAME}_license:/var/lib/wakeforce/license
EOF

    if [ "$WAKEFORCE_ONLY" = true ]; then
      local wf_host_port=$((8182 + i))
      cat >> docker-compose.yml <<EOF
    ports:
      - "${wf_host_port}:8182"
EOF
    else
      cat >> docker-compose.yml <<EOF
    expose:
      - "8182"
EOF
    fi

    local WF_IP_VAR="DOMAIN_${DOMAIN_NUM}_WF_IP"

    cat >> docker-compose.yml <<EOF
    networks:
      internal: {}
      ${NETWORK_NAME}:
        ipv4_address: \${${WF_IP_VAR}}
    cap_add:
      - NET_RAW

EOF
  done
}

# Append macvlan LAN networks for wakeforce services.
write_wakeforce_networks() {
  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    if [ "$(config_get "$config" "enable_wakeforce")" != "yes" ]; then
      continue
    fi

    local DOMAIN_NUM=$((i + 1))
    local NETWORK_NAME="lan_${DOMAIN_NUM}"
    local LAN_VAR="DOMAIN_${DOMAIN_NUM}_LAN"
    local SUBNET_VAR="DOMAIN_${DOMAIN_NUM}_SUBNET"
    local GATEWAY_VAR="DOMAIN_${DOMAIN_NUM}_GATEWAY"

    cat >> docker-compose.yml <<EOF
  ${NETWORK_NAME}:
    driver: macvlan
    driver_opts:
      parent: \${${LAN_VAR}:-eth0}
    ipam:
      config:
        - subnet: \${${SUBNET_VAR}:-192.168.1.0/24}
          gateway: \${${GATEWAY_VAR}:-192.168.1.1}

EOF
  done
}

# Append license volumes for wakeforce services.
write_wakeforce_volumes() {
  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    if [ "$(config_get "$config" "enable_wakeforce")" != "yes" ]; then
      continue
    fi

    local DOMAIN_NUM=$((i + 1))
    echo "  wakeforce_${DOMAIN_NUM}_license:" >> docker-compose.yml
  done
}
