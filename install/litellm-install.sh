#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# Refactor: Docker Compose official stack (community contribution preserved)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

LITELLM_COMPOSE_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/docker-compose.yml"
LITELLM_PROM_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/prometheus.yml"
LITELLM_DIR="/opt/litellm"

setup_docker

msg_info "Fetching LiteLLM Docker Compose stack"
mkdir -p "$LITELLM_DIR"
cd "$LITELLM_DIR"
curl -fsSL "$LITELLM_COMPOSE_URL" -o docker-compose.yml
curl -fsSL "$LITELLM_PROM_URL" -o prometheus.yml
msg_ok "Fetched compose files"

msg_info "Generating secrets"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LITELLM_SALT_KEY="sk-$(openssl rand -hex 16)"
POSTGRES_PASSWORD="$(openssl rand -hex 16)"

cat <<EOF >"$LITELLM_DIR/.env"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
LITELLM_SALT_KEY="${LITELLM_SALT_KEY}"
EOF

# Replace example credentials from upstream compose with generated secrets
sed -i "s/dbpassword9090/${POSTGRES_PASSWORD}/g" "$LITELLM_DIR/docker-compose.yml"
msg_ok "Generated secrets"

msg_info "Starting LiteLLM stack (Patience)"
cd "$LITELLM_DIR"
$STD docker compose up -d

msg_info "Waiting for LiteLLM health check"
for i in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1; then
    msg_ok "LiteLLM is healthy"
    break
  fi
  if docker compose ps --format json 2>/dev/null | grep -q '"Health":"unhealthy"'; then
    msg_error "LiteLLM container is unhealthy — check: docker compose logs litellm"
    exit 150
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    msg_error "LiteLLM did not become healthy within 120s"
    docker compose logs litellm 2>/dev/null | tail -30
    exit 150
  fi
done

cat <<EOF >~/litellm.creds
LiteLLM Credentials
URL: http://${LOCAL_IP}:4000
Master Key: ${LITELLM_MASTER_KEY}
Salt Key: ${LITELLM_SALT_KEY}
Postgres Password: ${POSTGRES_PASSWORD}

Note: LITELLM_SALT_KEY cannot be changed after adding models to the proxy.
EOF
chmod 600 ~/litellm.creds
msg_ok "Saved credentials to ~/litellm.creds"

motd_ssh
customize
cleanup_lxc
