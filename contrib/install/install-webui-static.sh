#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${WEBUI_DOMAIN:?WEBUI_DOMAIN is required}"
EMAIL="${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL is required}"
WEBROOT="${WEBUI_ROOT:-/var/www/miningcore-webui}"
API_UPSTREAM="${MININGCORE_API_UPSTREAM:-http://127.0.0.1:4000/api/}"
POOL_ID="${MININGCORE_POOL_ID:-mflex}"
STRATUM_PORT="${MININGCORE_POOL_PORT:-3333}"
export DOMAIN POOL_ID STRATUM_PORT
TEMPLATE="${WEBUI_TEMPLATE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/webui/index.html}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends nginx certbot ca-certificates curl

install -d -m 0755 "$WEBROOT" "$WEBROOT/assets"
if [[ -d "$(dirname "$TEMPLATE")/assets" ]]; then
  cp -a "$(dirname "$TEMPLATE")/assets/." "$WEBROOT/assets/"
fi
curl -fsSL "${MFLEX_LOGO_URL:-https://explorer.multiflexcoin.com/img/page-title-img.png}" -o "$WEBROOT/assets/mflex.png" || true

if [[ ! -f "$TEMPLATE" ]]; then
  echo "WebUI template not found: $TEMPLATE" >&2
  exit 1
fi
python3 - "$TEMPLATE" "$WEBROOT/index.html" <<'PY'
import os, sys
src, dst = sys.argv[1:3]
text = open(src, encoding='utf-8').read()
repl = {
    '__WEBUI_DOMAIN__': os.environ['DOMAIN'],
    '__POOL_ID__': os.environ.get('POOL_ID', 'mflex'),
    '__STRATUM_PORT__': os.environ.get('STRATUM_PORT', '3333'),
}
for k, v in repl.items():
    text = text.replace(k, v)
open(dst, 'w', encoding='utf-8').write(text)
PY

cat > /etc/nginx/sites-available/miningcore-webui <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $WEBROOT;
    index index.html;
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location /api/ {
        proxy_pass $API_UPSTREAM;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/miningcore-webui /etc/nginx/sites-enabled/miningcore-webui
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

if [[ "${WEBUI_ENABLE_HTTPS:-true}" == "true" ]]; then
  if [[ ! -e "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    certbot certonly --webroot -w "$WEBROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --no-eff-email
  fi
  cat > /etc/nginx/sites-available/miningcore-webui <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    root $WEBROOT;
    index index.html;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    location /api/ {
        proxy_pass $API_UPSTREAM;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX
  systemctl enable certbot.timer >/dev/null 2>&1 || true
fi

nginx -t
systemctl reload nginx
echo "WebUI ready: ${WEBUI_ENABLE_HTTPS:-true}://${DOMAIN}/"
