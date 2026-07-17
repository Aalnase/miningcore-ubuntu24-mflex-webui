#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${WEBUI_DOMAIN:?WEBUI_DOMAIN is required}"
EMAIL="${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL is required}"
WEBROOT="${WEBUI_ROOT:-/var/www/miningcore-webui}"
API_UPSTREAM="${MININGCORE_API_UPSTREAM:-http://127.0.0.1:4000/api/}"
POOL_ID="${MININGCORE_POOL_ID:-mflex}"
STRATUM_PORT="${MININGCORE_POOL_PORT:-3333}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends nginx certbot ca-certificates curl
install -d -m 0755 "$WEBROOT" "$WEBROOT/assets"
curl -fsSL "${MFLEX_LOGO_URL:-https://explorer.multiflexcoin.com/img/page-title-img.png}" -o "$WEBROOT/assets/mflex.png" || true

cat > "$WEBROOT/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${DOMAIN} | MFLEX SOLO Pool</title><meta name="description" content="MFLEX SOLO mining pool with live Miningcore statistics."><style>
:root{color-scheme:dark;--bg:#07111f;--card:#111f39;--line:#263b5d;--text:#edf5ff;--muted:#a9b9d4;--accent:#34d399;--accent2:#60a5fa;--warn:#fbbf24}*{box-sizing:border-box}body{margin:0;font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:radial-gradient(circle at top left,#18345e 0,#07111f 36%,#030711 100%);color:var(--text)}a{color:var(--accent2);text-decoration:none}.wrap{width:min(1180px,calc(100% - 32px));margin:auto}.hero{padding:38px 0 24px}.brand{display:flex;gap:14px;align-items:center}.brand img{width:54px;height:54px;border-radius:15px;background:#fff1;padding:6px}.pill{display:inline-flex;gap:8px;align-items:center;border:1px solid var(--line);background:#ffffff0a;color:var(--muted);padding:7px 11px;border-radius:999px;font-size:13px}.dot{width:8px;height:8px;border-radius:50%;background:var(--warn)}.dot.ok{background:var(--accent)}h1{font-size:clamp(34px,6vw,70px);line-height:.95;margin:24px 0 16px;letter-spacing:-.06em}.lead{font-size:clamp(17px,2vw,22px);line-height:1.55;color:var(--muted);max-width:840px}.actions{display:flex;flex-wrap:wrap;gap:12px;margin:25px 0}.btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;border:1px solid var(--line);background:#ffffff10;color:var(--text);padding:13px 17px;border-radius:14px;font-weight:750;box-shadow:0 12px 35px #0005}.btn.primary{background:linear-gradient(135deg,var(--accent),#22c55e);color:#03130b}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:22px 0}.card{border:1px solid var(--line);background:linear-gradient(180deg,#132646cc,#0d1a31cc);border-radius:22px;padding:18px;box-shadow:0 18px 60px #0006}.card h3{margin:0 0 7px;font-size:14px;color:var(--muted);font-weight:650}.metric{font-size:26px;font-weight:850;letter-spacing:-.03em;overflow-wrap:anywhere}.muted{color:var(--muted)}.section{padding:18px 0}.section h2{font-size:30px;margin:0 0 14px;letter-spacing:-.035em}.two{display:grid;grid-template-columns:1.25fr .75fr;gap:16px}.code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;background:#020713;border:1px solid var(--line);padding:14px;border-radius:14px;overflow:auto;color:#d9f99d}.table{width:100%;border-collapse:collapse}.table th,.table td{border-bottom:1px solid var(--line);text-align:left;padding:11px 8px}.table th{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em}.faq details{border:1px solid var(--line);border-radius:16px;padding:14px 16px;background:#ffffff08;margin:10px 0}.faq summary{font-weight:750;cursor:pointer}.support-fab{position:fixed;right:20px;bottom:20px;z-index:20;border:0;border-radius:999px;padding:15px 18px;background:linear-gradient(135deg,var(--accent2),var(--accent));color:#02111d;font-weight:850;box-shadow:0 18px 55px #0009;cursor:pointer}.drawer{position:fixed;right:18px;bottom:78px;width:min(390px,calc(100vw - 36px));background:#081427;border:1px solid var(--line);border-radius:24px;padding:18px;box-shadow:0 24px 80px #000d;z-index:30;display:none}.drawer.open{display:block}.x{float:right;background:#ffffff12;color:var(--text);border:1px solid var(--line);border-radius:10px;padding:5px 9px;cursor:pointer}.links{display:grid;gap:10px;margin-top:14px}.links a{display:block;padding:12px;border-radius:14px;background:#ffffff0c;border:1px solid var(--line);font-weight:750}@media(max-width:860px){.grid{grid-template-columns:repeat(2,1fr)}.two{grid-template-columns:1fr}}@media(max-width:520px){.grid{grid-template-columns:1fr}.actions .btn{width:100%}}
</style></head><body><main class="wrap"><section class="hero"><div class="brand"><img src="/assets/mflex.png" alt="MFLEX"><div><div class="pill"><span id="statusDot" class="dot"></span><span id="statusText">Checking pool API…</span></div><h2>${DOMAIN}</h2></div></div><h1>MFLEX SOLO Mining Pool</h1><p class="lead">Public Multiflex Coin pool on Ubuntu 24.04, Miningcore, PostgreSQL 18 and systemd. API is proxied through HTTPS; wallet RPC remains private.</p><div class="actions"><a class="btn primary" href="#connect">Connect miner</a><a class="btn" href="#stats">Live stats</a><button class="btn" onclick="openSupport()">Support</button></div></section><section id="stats" class="grid"><div class="card"><h3>Pool Hashrate</h3><div class="metric" id="poolHashrate">—</div></div><div class="card"><h3>Connected Miners</h3><div class="metric" id="miners">—</div></div><div class="card"><h3>Network Height</h3><div class="metric" id="height">—</div></div><div class="card"><h3>Payout Scheme</h3><div class="metric" id="scheme">SOLO</div></div></section><section class="section two"><div class="card" id="connect"><h2>Connection settings</h2><p class="muted">Use your MFLEX wallet address as worker username. Password can be anything, for example <b>x</b>.</p><div class="code">URL: stratum+tcp://${DOMAIN}:${STRATUM_PORT}<br>Username: YOUR_MFLEX_WALLET_ADDRESS<br>Password: x<br>Algorithm: Sha256D<br>Mode: SOLO</div></div><div class="card"><h2>Security surface</h2><p class="muted">Open externally: HTTPS, HTTP, Stratum and MFLEX P2P. Miningcore API is available only through <code>/api/</code>; MFLEX RPC is localhost-only.</p></div></section><section class="section two"><div class="card"><h2>Recent blocks</h2><table class="table"><thead><tr><th>Height</th><th>Status</th><th>Found / Berlin Time</th></tr></thead><tbody id="blocks"><tr><td colspan="3" class="muted">Loading…</td></tr></tbody></table></div><div class="card"><h2>Recent payments</h2><table class="table"><thead><tr><th>Amount</th><th>Time</th></tr></thead><tbody id="payments"><tr><td colspan="2" class="muted">Loading…</td></tr></tbody></table></div></section><section class="section faq" id="faq"><div class="card"><h2>MFLEX SOLO Pool FAQ</h2><details open><summary>What does SOLO mean?</summary><p class="muted">A valid block found by your miner is paid to your miner address, minus configured pool fees. There is no PPLNS share-splitting between unrelated miners.</p></details><details><summary>How do I connect?</summary><p class="muted">Point your miner to the Stratum URL above and use your MFLEX wallet address as the username.</p></details><details><summary>Why Berlin time?</summary><p class="muted">Miningcore stores API timestamps in UTC. The WebUI formats public times for Europe/Berlin.</p></details></div></section></main><button class="support-fab" onclick="openSupport()">Support</button><aside id="support" class="drawer"><button class="x" onclick="closeSupport()">×</button><h3>Support</h3><p class="muted">Need help connecting a miner or checking payouts?</p><div class="links"><a href="https://t.me/multiflexcoin" target="_blank" rel="noopener noreferrer">Telegram: @multiflexcoin</a><a href="https://t.me/go_poolmining" target="_blank" rel="noopener noreferrer">Telegram: @go_poolmining</a><a href="#faq" onclick="closeSupport()">Open FAQ</a><a href="#connect" onclick="closeSupport()">Connection settings</a></div></aside><script>
const API='/api/',pool='${POOL_ID}';const fmtHash=n=>{if(!n&&n!==0)return'—';const u=['H/s','KH/s','MH/s','GH/s','TH/s','PH/s'];let i=0;while(n>=1000&&i<u.length-1){n/=1000;i++}return `${n.toFixed(n>=100?0:n>=10?1:2)} ${u[i]}`};const berlin=s=>s?new Intl.DateTimeFormat('de-DE',{dateStyle:'short',timeStyle:'medium',timeZone:'Europe/Berlin',timeZoneName:'short'}).format(new Date(s)):'—';function openSupport(){document.getElementById('support').classList.add('open')}function closeSupport(){document.getElementById('support').classList.remove('open')}async function json(path){const r=await fetch(API+path,{cache:'no-store'});if(!r.ok)throw new Error(path+' '+r.status);return r.json()}async function refresh(){try{const pools=await json('pools');const p=(pools.pools||[]).find(x=>x.id===pool)||{};document.getElementById('statusDot').classList.add('ok');document.getElementById('statusText').textContent='Pool API online';document.getElementById('poolHashrate').textContent=fmtHash(p.poolStats?.poolHashrate||0);document.getElementById('miners').textContent=p.poolStats?.connectedMiners??'—';document.getElementById('height').textContent=(p.networkStats?.blockHeight||p.poolStats?.blockHeight||'—').toLocaleString?.()||'—';document.getElementById('scheme').textContent=p.paymentProcessing?.payoutScheme||p.payoutScheme||'SOLO'}catch(e){document.getElementById('statusText').textContent='Pool API not ready';console.warn(e)}try{const b=await json(`pools/${pool}/blocks?page=0&pageSize=8`);const rows=(b||[]).map(x=>`<tr><td>${x.blockHeight??x.height??'—'}</td><td>${x.status??'—'}</td><td>${berlin(x.created)}</td></tr>`).join('');document.getElementById('blocks').innerHTML=rows||'<tr><td colspan="3" class="muted">No blocks yet.</td></tr>'}catch(e){document.getElementById('blocks').innerHTML='<tr><td colspan="3" class="muted">No blocks yet.</td></tr>'}try{const p=await json(`pools/${pool}/payments?page=0&pageSize=6`);const rows=(p||[]).map(x=>`<tr><td>${x.amount??'—'} MFLEX</td><td>${berlin(x.created)}</td></tr>`).join('');document.getElementById('payments').innerHTML=rows||'<tr><td colspan="2" class="muted">No payments yet.</td></tr>'}catch(e){document.getElementById('payments').innerHTML='<tr><td colspan="2" class="muted">No payments yet.</td></tr>'}}refresh();setInterval(refresh,30000);
</script></body></html>
HTML

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
    location / { try_files \$uri \$uri/ /index.html; }
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
    location / { try_files \$uri \$uri/ /index.html; }
}
NGINX
  systemctl enable certbot.timer >/dev/null 2>&1 || true
fi
nginx -t
systemctl reload nginx
echo "WebUI ready: ${WEBUI_ENABLE_HTTPS:-true}://${DOMAIN}/"
