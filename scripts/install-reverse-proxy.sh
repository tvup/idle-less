#!/usr/bin/env bash
# Generates the reverse-proxy service in docker-compose.yml.
# Expects: CONFIGS array populated, docker-compose.yml started with services: header.
# Requires: config_get() from common.sh

write_reverse_proxy_service() {
  cat >> docker-compose.yml <<'EOF'
  reverse-proxy:
    image: tvup/reverse-proxy:latest
    container_name: reverse-proxy
    ports:
      - "80:80"
      - "443:443"
    environment:
EOF

  for i in "${!CONFIGS[@]}"; do
    DOMAIN_NUM=$((i + 1))
    cat >> docker-compose.yml <<EOF
      DOMAIN_${DOMAIN_NUM}_HOSTNAME: \${DOMAIN_${DOMAIN_NUM}_HOSTNAME:-}
      DOMAIN_${DOMAIN_NUM}_IP: \${DOMAIN_${DOMAIN_NUM}_IP:-}
      DOMAIN_${DOMAIN_NUM}_PORT: \${DOMAIN_${DOMAIN_NUM}_PORT:-}
      DOMAIN_${DOMAIN_NUM}_USE_HTTPS: \${DOMAIN_${DOMAIN_NUM}_USE_HTTPS:-no}
      DOMAIN_${DOMAIN_NUM}_USE_SSL: \${DOMAIN_${DOMAIN_NUM}_USE_SSL:-no}
EOF
  done

  cat >> docker-compose.yml <<'EOF'
    volumes:
EOF

  for i in "${!CONFIGS[@]}"; do
    local config="${CONFIGS[$i]}"
    local USE_SSL DOMAIN_NUM D_HOSTNAME
    USE_SSL=$(config_get "$config" "use_ssl")
    DOMAIN_NUM=$((i + 1))

    if [ "$USE_SSL" = "yes" ]; then
      D_HOSTNAME=$(config_get "$config" "hostname")
      cat >> docker-compose.yml <<EOF
      - '\${DOMAIN_${DOMAIN_NUM}_CERTS_HOST_PATH}:/etc/certificate_provider/live/${D_HOSTNAME}:ro'
EOF
    fi
  done

  cat >> docker-compose.yml <<'EOF'
      - reverse-proxy-nginx-data:/etc/nginx/conf.d
    networks:
      - internal
    restart: unless-stopped
EOF
}
