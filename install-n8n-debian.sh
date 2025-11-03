#!/usr/bin/env bash
# Debian 13 (trixie) - One-click n8n + Traefik + Postgres stack
# Usage: sudo bash install-n8n.sh
set -euo pipefail

REQ_PKGS=(ca-certificates curl gnupg)
STACK_DIR="/opt/n8n"
ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

# --- root check ---
if [[ $EUID -ne 0 ]]; then
  echo "[ERR] Please run as root (sudo)."; exit 1
fi

echo "[INFO] Updating APT and installing prerequisites..."
apt-get update -y
apt-get install -y "${REQ_PKGS[@]}"

# --- Detect primary IP and rDNS ---
detect_default_ipv4() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true
}
detect_default_ipv6() {
  ip -6 route get 2001:4860:4860::8888 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true
}
reverse_dns() {
  local ip="$1"
  [[ -z "$ip" ]] && return 1
  # getent does reverse lookup for an IP; strip trailing dot
  local ptr
  ptr="$(getent hosts "$ip" | awk '{print $2}' | sed 's/\.$//' | head -n1)"
  # basic sanity: must contain a dot and only domain-safe chars
  if [[ -n "${ptr:-}" && "$ptr" == *.* && "$ptr" =~ ^[A-Za-z0-9.-]+$ ]]; then
    printf '%s' "$ptr"
    return 0
  fi
  return 1
}

PRIMARY_IP="$(detect_default_ipv4)"
if [[ -z "$PRIMARY_IP" ]]; then
  PRIMARY_IP="$(detect_default_ipv6 || true)"
fi

DEFAULT_DOMAIN="###IP-HOSTNAME###"
if [[ -n "$PRIMARY_IP" ]]; then
  if PTR="$(reverse_dns "$PRIMARY_IP")"; then
    DEFAULT_DOMAIN="$PTR"
    echo "[INFO] Detected primary IP: $PRIMARY_IP, rDNS: $DEFAULT_DOMAIN"
  else
    echo "[WARN] No valid rDNS found for $PRIMARY_IP; keeping placeholder."
  fi
else
  echo "[WARN] Could not detect primary IP; keeping placeholder."
fi

# --- Docker CE repo & install ---
if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Installing Docker CE..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo $ID)/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  CODENAME="$(. /etc/os-release; echo $VERSION_CODENAME)"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release; echo $ID) $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
else
  echo "[INFO] Docker already installed; ensuring service enabled..."
  systemctl enable --now docker
fi

# --- Prepare stack directory ---
mkdir -p "$STACK_DIR"
cd "$STACK_DIR"

# --- Create or update .env ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[INFO] Creating .env with generated secrets and domain: $DEFAULT_DOMAIN"
  N8N_KEY="$(openssl rand -hex 48)"
  PG_PASS="$(openssl rand -hex 24)"
  cat > "$ENV_FILE" <<EOF
# === Required ===
DOMAIN=$DEFAULT_DOMAIN
N8N_ENCRYPTION_KEY=$N8N_KEY
POSTGRES_PASSWORD=$PG_PASS

# === Optional ===
TZ=Europe/Nicosia
N8N_IMAGE=n8nio/n8n:latest
POSTGRES_IMAGE=postgres:16
TRAEFIK_IMAGE=traefik:latest
EOF
else
  echo "[INFO] .env already exists; updating DOMAIN if placeholder is present..."
  if grep -q '^DOMAIN=###IP-HOSTNAME###$' "$ENV_FILE"; then
    sed -i "s/^DOMAIN=###IP-HOSTNAME###$/DOMAIN=${DEFAULT_DOMAIN//\//\\/}/" "$ENV_FILE"
    echo "[INFO] Replaced placeholder with detected domain: $DEFAULT_DOMAIN"
  else
    echo "[INFO] Existing DOMAIN kept unchanged."
  fi
fi

# --- Write docker-compose.yml ---
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[INFO] Creating docker-compose.yml..."
  cat > "$COMPOSE_FILE" <<'YAML'
version: "3.9"

services:
  traefik:
    image: ${TRAEFIK_IMAGE}
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      # Entrypoints
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      # Redirect HTTP -> HTTPS
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      # Let's Encrypt (HTTP-01) without email (anonymous ACME account)
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
      - --api=false
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_letsencrypt:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped

  db:
    image: ${POSTGRES_IMAGE}
    environment:
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: n8n
      TZ: ${TZ}
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n -d n8n"]
      interval: 10s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  n8n:
    image: ${N8N_IMAGE}
    depends_on:
      db:
        condition: service_healthy
    environment:
      N8N_HOST: ${DOMAIN}
      N8N_PROTOCOL: https
      N8N_PORT: 5678
      WEBHOOK_URL: https://${DOMAIN}/
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: db
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: n8n
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_POSTGRESDB_DATABASE: n8n
      TZ: ${TZ}
      EXECUTIONS_DATA_SAVE_ON_SUCCESS: "none"
      EXECUTIONS_DATA_SAVE_ON_ERROR: "all"
    volumes:
      - n8n_data:/home/node/.n8n
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(`${DOMAIN}`)
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls.certresolver=le
      - traefik.http.middlewares.n8n-headers.headers.stsSeconds=31536000
      - traefik.http.middlewares.n8n-headers.headers.stsIncludeSubdomains=true
      - traefik.http.middlewares.n8n-headers.headers.stsPreload=true
      - traefik.http.middlewares.n8n-headers.headers.contentTypeNosniff=true
      - traefik.http.middlewares.n8n-headers.headers.browserXssFilter=true
      - traefik.http.middlewares.n8n-headers.headers.frameDeny=true
      - traefik.http.middlewares.n8n-body.buffering.maxRequestBodyBytes=104857600
      - traefik.http.routers.n8n.middlewares=n8n-headers,n8n-body
      - traefik.http.services.n8n.loadbalancer.server.port=5678
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower
    command: --cleanup --include-restarting --schedule "0 0 4 * * *"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

volumes:
  traefik_letsencrypt:
  n8n_data:
  pg_data:
YAML
else
  echo "[INFO] docker-compose.yml already exists; leaving as-is."
fi

# --- Optional: open firewall if ufw is installed ---
if command -v ufw >/dev/null 2>&1; then
  echo "[INFO] UFW detected; allowing 80 and 443..."
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi

# --- Start the stack ---
echo "[INFO] Pulling images and starting the stack..."
docker compose pull
docker compose up -d

echo
echo "=============================================================="
echo "[OK] n8n stack deployed."
echo
echo "  - DOMAIN set to: $(grep '^DOMAIN=' "$ENV_FILE" | cut -d= -f2-)"
echo "  - Create DNS A/AAAA record pointing to this VPS (if needed)."
echo "  - Ensure ports 80/443 are reachable."
echo "  - Access: https://$(grep '^DOMAIN=' "$ENV_FILE" | cut -d= -f2-)/  (Let's Encrypt auto)"
echo
echo "Update later with:   docker compose pull && docker compose up -d"
echo "Stack location:      $STACK_DIR"
echo "=============================================================="
