#!/usr/bin/env bash
set -euo pipefail

# Bare-metal installer for Aalnase Miningcore on Ubuntu 24.04+.
# Installs:
#   - .NET 10 build/runtime dependencies
#   - PostgreSQL 18 and Miningcore schema/user
#   - Miningcore under /opt/miningcore with systemd service
#   - Multiflex Core from https://github.com/Aalnase/multiflexcoin under /opt/multiflexcoin
#
# Usage:
#   sudo ./contrib/install/install-ubuntu-24.04.sh
#   sudo POOL_MODE=home ./contrib/install/install-ubuntu-24.04.sh
#   sudo POOL_MODE=public MFLEX_POOL_ADDRESS=M... ./contrib/install/install-ubuntu-24.04.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root, for example: sudo $0" >&2
    exit 1
  fi
}

require_ubuntu_24_plus() {
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    echo "This installer is intended for Ubuntu 24.04 or newer. Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  local major minor
  major="${VERSION_ID%%.*}"
  minor="${VERSION_ID#*.}"
  minor="${minor%%.*}"
  if (( major < 24 || (major == 24 && minor < 4) )); then
    echo "Ubuntu 24.04 or newer is required. Detected: ${VERSION_ID}" >&2
    exit 1
  fi
}

backup_if_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    cp -a "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

random_secret() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

ask_pool_mode() {
  if [[ -n "${POOL_MODE:-}" ]]; then
    case "${POOL_MODE}" in
      public|home) return ;;
      *) echo "POOL_MODE must be 'public' or 'home'" >&2; exit 1 ;;
    esac
  fi

  echo "Select installation profile:"
  echo "  1) public  - public internet pool, API can bind publicly, payments enabled"
  echo "  2) home    - home/LAN pool, conservative defaults, API localhost only"
  read -r -p "Profile [home]: " choice
  case "${choice:-2}" in
    1|public|Public|PUBLIC) POOL_MODE="public" ;;
    *) POOL_MODE="home" ;;
  esac
  export POOL_MODE
}


ask_webui_settings() {
  # Frontend installation is optional in this bare-metal script. When enabled,
  # collect the public domain and Let's Encrypt email up front so HTTPS can be
  # issued non-interactively and static WebUI files can be branded correctly.
  INSTALL_WEBUI="${INSTALL_WEBUI:-false}"
  WEBUI_ENABLE_HTTPS="${WEBUI_ENABLE_HTTPS:-true}"

  case "${INSTALL_WEBUI}" in
    true|false) ;;
    *) echo "INSTALL_WEBUI must be 'true' or 'false'" >&2; exit 1 ;;
  esac
  case "${WEBUI_ENABLE_HTTPS}" in
    true|false) ;;
    *) echo "WEBUI_ENABLE_HTTPS must be 'true' or 'false'" >&2; exit 1 ;;
  esac

  if [[ "${INSTALL_WEBUI}" != "true" ]]; then
    export INSTALL_WEBUI WEBUI_ENABLE_HTTPS
    return 0
  fi

  if [[ -z "${WEBUI_DOMAIN:-}" ]]; then
    read -r -p "WebUI domain/subdomain (for example test.go-poolmining.com): " WEBUI_DOMAIN
  fi
  if [[ -z "${WEBUI_DOMAIN:-}" ]]; then
    echo "WEBUI_DOMAIN is required when INSTALL_WEBUI=true" >&2
    exit 1
  fi

  if [[ "${WEBUI_ENABLE_HTTPS}" == "true" && -z "${LETSENCRYPT_EMAIL:-}" ]]; then
    read -r -p "Let's Encrypt email for ${WEBUI_DOMAIN}: " LETSENCRYPT_EMAIL
  fi
  if [[ "${WEBUI_ENABLE_HTTPS}" == "true" && -z "${LETSENCRYPT_EMAIL:-}" ]]; then
    echo "LETSENCRYPT_EMAIL is required when WEBUI_ENABLE_HTTPS=true" >&2
    exit 1
  fi

  export INSTALL_WEBUI WEBUI_ENABLE_HTTPS WEBUI_DOMAIN LETSENCRYPT_EMAIL
}

install_base_packages() {
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release git sudo jq logrotate ufw fail2ban

  if ! apt-cache show dotnet-sdk-10.0 >/dev/null 2>&1; then
    local ms_deb="/tmp/packages-microsoft-prod.deb"
    curl -fsSL "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" -o "$ms_deb"
    dpkg -i "$ms_deb"
    rm -f "$ms_deb"
    apt-get update
  fi

  apt-get install -y --no-install-recommends \
    dotnet-sdk-10.0 aspnetcore-runtime-10.0 \
    build-essential cmake ninja-build pkg-config python3 \
    gperf bison flex automake libtool gettext zip unzip clang \
    libssl-dev libboost-all-dev libsodium-dev libzmq5 libzmq3-dev \
    libgmp-dev libc++-dev zlib1g-dev

  if [[ "${INSTALL_WEBUI:-false}" == "true" ]]; then
    apt-get install -y --no-install-recommends nginx certbot python3-certbot-nginx
  fi
}

install_postgresql18() {
  if ! apt-cache show postgresql-18 >/dev/null 2>&1; then
    install -d -m 0755 /usr/share/postgresql-common/pgdg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list
    apt-get update
  fi

  apt-get install -y postgresql-18 postgresql-client-18
  systemctl enable --now postgresql
}

setup_users() {
  id -u miningcore >/dev/null 2>&1 || useradd --system --home /opt/miningcore --shell /usr/sbin/nologin miningcore
  id -u multiflex >/dev/null 2>&1 || useradd --system --home /var/lib/multiflexcoin --shell /usr/sbin/nologin multiflex
}

setup_postgres_schema() {
  local db_name="${MININGCORE_DB_NAME:-miningcore}"
  local db_user="${MININGCORE_DB_USER:-miningcore}"
  local db_password="${MININGCORE_DB_PASSWORD:-$(random_secret)}"
  export MININGCORE_DB_NAME="$db_name" MININGCORE_DB_USER="$db_user" MININGCORE_DB_PASSWORD="$db_password"

  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${db_user}') THEN
    CREATE ROLE ${db_user} LOGIN PASSWORD '${db_password}';
  ELSE
    ALTER ROLE ${db_user} LOGIN PASSWORD '${db_password}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${db_name} OWNER ${db_user}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
SQL

  # Load schema only if it is not present yet. createdb.sql starts with SET ROLE miningcore;
  # so keep the default role/database names unless the operator explicitly customizes later.
  if ! sudo -u postgres psql -d "$db_name" -tAc "SELECT to_regclass('public.shares')" | grep -q shares; then
    sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 -f "$REPO_ROOT/src/Miningcore/Persistence/Postgres/Scripts/createdb.sql"
  fi

  sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 <<SQL
GRANT USAGE ON SCHEMA public TO ${db_user};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${db_user};
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${db_user};
SQL
}

build_install_miningcore() {
  install -d -o miningcore -g miningcore /opt/miningcore /etc/miningcore /var/log/miningcore

  echo "Publishing Miningcore (.NET 10). This also builds native hashing libraries..."
  (cd "$REPO_ROOT" && BUILD_JOBS="${BUILD_JOBS:-$(nproc)}" dotnet publish src/Miningcore/Miningcore.csproj \
    -c Release --framework net10.0 -o /opt/miningcore)

  chown -R miningcore:miningcore /opt/miningcore /var/log/miningcore
}

build_install_multiflexcoin() {
  local src_dir="${MFLEX_SOURCE_DIR:-/usr/local/src/multiflexcoin}"
  local repo_url="${MFLEX_REPO_URL:-https://github.com/Aalnase/multiflexcoin.git}"
  local branch="${MFLEX_BRANCH:-main}"

  install -d /usr/local/src /opt/multiflexcoin /etc/multiflexcoin /var/lib/multiflexcoin
  chown -R multiflex:multiflex /var/lib/multiflexcoin

  if [[ ! -d "$src_dir/.git" ]]; then
    git clone --depth 1 --branch "$branch" "$repo_url" "$src_dir"
  else
    git -C "$src_dir" fetch --depth 1 origin "$branch"
    git -C "$src_dir" checkout "$branch"
    git -C "$src_dir" reset --hard "origin/$branch"
  fi

  echo "Building Multiflex Core daemon/CLI from source. This can take a while..."
  # Only daemon + CLI are installed for pool servers. Skip Qt/GUI dependencies and
  # USDT tracing dependencies so fresh VPS installs do not spend time downloading
  # or building components that are not needed for headless pool operation.
  (cd "$src_dir" && make -C depends NO_QT=1 NO_USDT=1 -j"${BUILD_JOBS:-$(nproc)}")
  local toolchain
  toolchain="$(find "$src_dir/depends" -path '*/toolchain.cmake' | head -n1)"
  if [[ -z "$toolchain" ]]; then
    echo "Could not locate Multiflex depends toolchain.cmake" >&2
    exit 1
  fi
  cmake -S "$src_dir" -B "$src_dir/build" --toolchain "$toolchain" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF
  cmake --build "$src_dir/build" --parallel "${BUILD_JOBS:-$(nproc)}" --target bitcoind bitcoin-cli
  # Install only the daemon and CLI components. Installing all components would
  # also try to install the optional wrapper binary, which is disabled in this
  # build and may not exist.
  cmake --install "$src_dir/build" --prefix /opt/multiflexcoin --strip --component bitcoind
  cmake --install "$src_dir/build" --prefix /opt/multiflexcoin --strip --component bitcoin-cli

  # Provide convenient stable command names.
  ln -sf /opt/multiflexcoin/bin/multiflexd /usr/local/bin/multiflexd
  ln -sf /opt/multiflexcoin/bin/multiflex-cli /usr/local/bin/multiflex-cli
}

generate_multiflex_conf() {
  local rpc_user="${MFLEX_RPC_USER:-mflexrpc}"
  local rpc_password="${MFLEX_RPC_PASSWORD:-$(random_secret)}"
  local rpc_port="${MFLEX_RPC_PORT:-26015}"
  local p2p_port="${MFLEX_P2P_PORT:-24200}"
  export MFLEX_RPC_USER="$rpc_user" MFLEX_RPC_PASSWORD="$rpc_password" MFLEX_RPC_PORT="$rpc_port" MFLEX_P2P_PORT="$p2p_port"

  backup_if_exists /etc/multiflexcoin/multiflex.conf
  cat > /etc/multiflexcoin/multiflex.conf <<EOF
server=1
daemon=0
listen=1
port=${p2p_port}
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=${rpc_port}
rpcuser=${rpc_user}
rpcpassword=${rpc_password}
zmqpubhashblock=tcp://127.0.0.1:26016
zmqpubhashtx=tcp://127.0.0.1:26017

# Home pools can keep pruning enabled to reduce disk usage. Public pools should
# generally run archival/full nodes.
prune=$([[ "${POOL_MODE}" == "home" ]] && echo 550 || echo 0)
EOF
  chown root:multiflex /etc/multiflexcoin/multiflex.conf
  chmod 640 /etc/multiflexcoin/multiflex.conf
}

generate_miningcore_config() {
  local pool_wallet="${MFLEX_POOL_ADDRESS:-YOUR_MFLEX_POOL_WALLET_ADDRESS}"
  local pool_port="${MININGCORE_POOL_PORT:-3333}"
  local api_address api_rate_disabled api_rate_limit payment_enabled min_diff start_diff max_diff

  if [[ "${POOL_MODE}" == "public" ]]; then
    api_address="*"
    api_rate_disabled="false"
    api_rate_limit="${MININGCORE_API_RATE_LIMIT:-300}"
    payment_enabled="true"
    min_diff=512
    start_diff=1024
    max_diff=1048576
  else
    api_address="127.0.0.1"
    api_rate_disabled="true"
    api_rate_limit="${MININGCORE_API_RATE_LIMIT:-300}"
    payment_enabled="false"
    min_diff=1
    start_diff=16
    max_diff=65536
  fi

  backup_if_exists /etc/miningcore/config.json
  python3 - "$REPO_ROOT/examples/multiflex_pool.json" "/etc/miningcore/config.json" <<PY
import json, os, sys
src, dst = sys.argv[1:]
with open(src) as f:
    data = json.load(f)
# Add the global sections normally expected by Miningcore examples.
data.setdefault('logging', {
    'level': 'info',
    'enableConsoleLog': True,
    'enableConsoleColors': True,
    'logFile': '/var/log/miningcore/miningcore.log',
    'apiLogFile': '/var/log/miningcore/api.log',
    'logBaseDirectory': '/var/log/miningcore',
    'perPoolLogFile': True,
})
data.setdefault('banning', {'manager': 'Integrated', 'banOnJunkReceive': True, 'banOnInvalidShares': False})
data.setdefault('notifications', {'enabled': False})
data['persistence'] = {'postgres': {
    'host': '127.0.0.1',
    'port': 5432,
    'user': os.environ['MININGCORE_DB_USER'],
    'password': os.environ['MININGCORE_DB_PASSWORD'],
    'database': os.environ['MININGCORE_DB_NAME'],
}}
data['paymentProcessing'] = {
    'enabled': '${payment_enabled}' == 'true',
    'interval': 600,
    'shareRecoveryFile': '/var/lib/miningcore/recovered-shares.txt',
}
data['api'] = {
    'enabled': True,
    'listenAddress': '${api_address}',
    'port': 4000,
    'metricsIpWhitelist': ['127.0.0.1'],
    'rateLimiting': {
        'disabled': '${api_rate_disabled}' == 'true',
        'rules': [{'Endpoint': '*', 'Period': '1s', 'Limit': int('${api_rate_limit}')}],
        'ipWhitelist': ['127.0.0.1', '::1'],
    },
}
pool = data['pools'][0]
pool['id'] = 'mflex'
pool['enabled'] = True
pool['coin'] = 'multiflex'
pool['address'] = '${pool_wallet}'
pool['ports'] = {'${pool_port}': {
    'listenAddress': '0.0.0.0',
    'difficulty': ${start_diff},
    'name': 'MFLEX ${POOL_MODE} mining',
    'varDiff': {
        'minDiff': ${min_diff},
        'maxDiff': ${max_diff},
        'targetTime': 15,
        'retargetTime': 90,
        'variancePercent': 30,
        'maxDelta': 200000,
    },
}}
pool['daemons'] = [{
    'host': '127.0.0.1',
    'port': int(os.environ['MFLEX_RPC_PORT']),
    'user': os.environ['MFLEX_RPC_USER'],
    'password': os.environ['MFLEX_RPC_PASSWORD'],
}]
pool['paymentProcessing']['enabled'] = '${payment_enabled}' == 'true'
# MFLEX is intended to run as a SOLO pool: the miner that finds the block
# receives the block reward. Do not inherit PPLNS defaults from generic examples.
pool['paymentProcessing']['payoutScheme'] = 'SOLO'
pool['paymentProcessing'].pop('payoutSchemeConfig', None)
with open(dst, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
  install -d -o miningcore -g miningcore /var/lib/miningcore
  chown root:miningcore /etc/miningcore/config.json
  chmod 640 /etc/miningcore/config.json
}

install_systemd_units() {
  install -m 0644 "$REPO_ROOT/contrib/install/miningcore.service" /etc/systemd/system/miningcore.service
  install -m 0644 "$REPO_ROOT/contrib/install/multiflexd.service" /etc/systemd/system/multiflexd.service
  systemctl daemon-reload
  systemctl enable multiflexd miningcore
}

configure_firewall_hardening() {
  echo "Configuring firewall and basic attack protection ..."

  cat > /etc/sysctl.d/99-aalnase-pool-hardening.conf <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_syn_backlog = 4096
EOF
  sysctl --system >/dev/null || true

  install -d -m 0755 /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd-aalnase.conf <<'EOF'
[sshd]
enabled = true
mode = aggressive
port = ssh
filter = sshd
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban >/dev/null
  systemctl restart fail2ban

  # Safe public surface:
  # - SSH is rate-limited so this script does not lock out remote admins.
  # - Stratum mining and MFLEX P2P are public.
  # - MFLEX RPC stays bound to localhost in multiflex.conf and is not opened.
  # - Miningcore API is not opened by default; expose it through a reverse proxy
  #   or set ALLOW_PUBLIC_API=true for a test system that really needs it.
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw limit 22/tcp comment "rate-limited SSH" >/dev/null
  ufw allow "${MININGCORE_POOL_PORT:-3333}"/tcp comment "Miningcore MFLEX stratum mining" >/dev/null
  ufw allow "${MFLEX_P2P_PORT:-24200}"/tcp comment "Multiflex P2P" >/dev/null
  if [[ "${INSTALL_WEBUI:-false}" == "true" ]]; then
    ufw allow 80/tcp comment "HTTP for WebUI and Lets Encrypt" >/dev/null
    ufw allow 443/tcp comment "HTTPS WebUI" >/dev/null
  fi
  if [[ "${ALLOW_PUBLIC_API:-false}" == "true" ]]; then
    ufw allow 4000/tcp comment "Miningcore API - explicitly enabled" >/dev/null
  fi
  ufw --force enable >/dev/null
  ufw status verbose
}


configure_retention_and_maintenance() {
  echo "Configuring log rotation, 30-day retention, and PostgreSQL maintenance ..."

  local retention_days="${POOL_RETENTION_DAYS:-30}"
  local postgres_db="${MININGCORE_DB_NAME:-miningcore}"

  # Miningcore writes normal file logs under /var/log/miningcore. Rotate daily,
  # keep 30 days by default, compress old logs, and use copytruncate so the
  # running process does not need a signal/restart to release file handles.
  cat > /etc/logrotate.d/miningcore <<EOF
/var/log/miningcore/*.log {
    daily
    rotate ${retention_days}
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 miningcore miningcore
}
EOF

  # Multiflex Core/Bitcoin-like daemons normally write debug.log in the data
  # directory. Keep the same retention policy and avoid interrupting the daemon.
  cat > /etc/logrotate.d/multiflexcoin <<EOF
/var/lib/multiflexcoin/debug.log
/var/lib/multiflexcoin/testnet*/debug.log
/var/lib/multiflexcoin/regtest/debug.log {
    daily
    rotate ${retention_days}
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su multiflex multiflex
    create 0640 multiflex multiflex
}
EOF

  # Journald can otherwise grow without a clear bound on small VPS systems.
  install -d -m 0755 /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/99-aalnase-pool-retention.conf <<EOF
[Journal]
SystemMaxUse=1G
RuntimeMaxUse=256M
MaxRetentionSec=${retention_days}day
Compress=yes
EOF
  systemctl restart systemd-journald

  # A conservative cleanup job for generated/transient files. It does not touch
  # blockchain data, wallets, PostgreSQL data, or current configs. Operator
  # backups made by this installer are kept for POOL_RETENTION_DAYS days.
  cat > /usr/local/sbin/aalnase-pool-maintenance.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
RETENTION_DAYS="${POOL_RETENTION_DAYS:-30}"
DB_NAME="${MININGCORE_DB_NAME:-miningcore}"

# Remove stale temp/build/cache leftovers related to this pool only.
find /tmp /var/tmp -xdev -mindepth 1 -maxdepth 2 \
  \( -iname '*miningcore*' -o -iname '*multiflex*' -o -iname '*mflex*' -o -iname '*aalnase*' \) \
  -mtime +"${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

# Remove old installer/operator backups after the retention window.
if [[ -d /root/backups ]]; then
  find /root/backups -xdev -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true
fi

# Compress any uncompressed rotated logs older than one day that logrotate left behind.
find /var/log/miningcore /var/lib/multiflexcoin -xdev -type f -name '*.log.[0-9]*' -mtime +1 ! -name '*.gz' -exec gzip -9 {} + 2>/dev/null || true

# Miningcore DB maintenance: non-blocking VACUUM ANALYZE. Autovacuum stays enabled,
# this timer is an extra predictable cleanup pass for shares/blocks/payments tables.
if systemctl is-active --quiet postgresql; then
  sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c 'VACUUM (ANALYZE);' >/dev/null
fi
EOF
  chmod 0755 /usr/local/sbin/aalnase-pool-maintenance.sh

  cat > /etc/systemd/system/aalnase-pool-maintenance.service <<EOF
[Unit]
Description=Aalnase Mining Pool daily cleanup and PostgreSQL vacuum
After=postgresql.service

[Service]
Type=oneshot
Environment=POOL_RETENTION_DAYS=${retention_days}
Environment=MININGCORE_DB_NAME=${postgres_db}
ExecStart=/usr/local/sbin/aalnase-pool-maintenance.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

  cat > /etc/systemd/system/aalnase-pool-maintenance.timer <<'EOF'
[Unit]
Description=Run Aalnase Mining Pool cleanup and PostgreSQL vacuum daily

[Timer]
OnCalendar=*-*-* 03:20:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now aalnase-pool-maintenance.timer

  # Validate logrotate syntax now so broken rotation config is caught during install.
  logrotate -d /etc/logrotate.d/miningcore >/dev/null
  logrotate -d /etc/logrotate.d/multiflexcoin >/dev/null
}

start_multiflex_for_setup() {
  systemctl daemon-reload
  systemctl enable multiflexd
  systemctl restart multiflexd
}

wait_for_multiflex_rpc() {
  local cli="/opt/multiflexcoin/bin/multiflex-cli"
  local conf="/etc/multiflexcoin/multiflex.conf"
  local datadir="/var/lib/multiflexcoin"
  local timeout="${MFLEX_RPC_WAIT_SECONDS:-300}"
  local i

  echo "Waiting for Multiflex RPC to become available (timeout ${timeout}s) ..."
  for ((i=0; i<timeout; i+=2)); do
    if "$cli" -conf="$conf" -datadir="$datadir" getblockchaininfo >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Multiflex RPC did not become available within ${timeout}s" >&2
  systemctl status multiflexd --no-pager || true
  journalctl -u multiflexd -n 80 --no-pager || true
  exit 1
}

wait_for_multiflex_sync_hint() {
  local cli="/opt/multiflexcoin/bin/multiflex-cli"
  local conf="/etc/multiflexcoin/multiflex.conf"
  local datadir="/var/lib/multiflexcoin"
  local timeout="${MFLEX_SYNC_WAIT_SECONDS:-600}"
  local info blocks headers ibd size i

  echo "Checking Multiflex chain size and sync state ..."
  du -sh "$datadir" 2>/dev/null || true

  for ((i=0; i<timeout; i+=5)); do
    info="$($cli -conf="$conf" -datadir="$datadir" getblockchaininfo 2>/dev/null || true)"
    if [[ -n "$info" ]]; then
      blocks="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("blocks", 0))' <<<"$info")"
      headers="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("headers", 0))' <<<"$info")"
      ibd="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(d.get("initialblockdownload", True)).lower())' <<<"$info")"
      size="$(du -sh "$datadir" 2>/dev/null | awk '{print $1}')"
      echo "MFLEX sync: blocks=${blocks}, headers=${headers}, initialblockdownload=${ibd}, datadir=${size:-unknown}"

      # Do not block forever on a brand-new/small chain where DNS peers may take
      # a while. Miningcore can start once RPC is online; it will reconnect as the
      # daemon syncs. If IBD is already false, great.
      if [[ "$ibd" == "false" ]]; then
        return 0
      fi
    fi
    sleep 5
  done

  echo "MFLEX is still in initial block download after ${timeout}s; continuing anyway because the chain is small and Miningcore can be restarted later if needed."
}

ensure_mflex_pool_address() {
  if [[ -n "${MFLEX_POOL_ADDRESS:-}" && "${MFLEX_POOL_ADDRESS}" != "YOUR_MFLEX_POOL_WALLET_ADDRESS" ]]; then
    export MFLEX_POOL_ADDRESS
    echo "Using provided MFLEX pool address: ${MFLEX_POOL_ADDRESS}"
    return 0
  fi

  local cli="/opt/multiflexcoin/bin/multiflex-cli"
  local conf="/etc/multiflexcoin/multiflex.conf"
  local datadir="/var/lib/multiflexcoin"
  local wallet="${MFLEX_POOL_WALLET_NAME:-poolwallet}"
  local addr=""

  echo "Creating/loading Multiflex wallet '${wallet}' for the pool payout address ..."
  "$cli" -conf="$conf" -datadir="$datadir" createwallet "$wallet" >/dev/null 2>&1 || \
    "$cli" -conf="$conf" -datadir="$datadir" loadwallet "$wallet" >/dev/null 2>&1 || true

  # Prefer legacy/base58 for Miningcore compatibility. Fall back to the daemon
  # default only if the address type argument is not supported.
  addr="$($cli -conf="$conf" -datadir="$datadir" -rpcwallet="$wallet" getnewaddress "" legacy 2>/dev/null || true)"
  if [[ -z "$addr" ]]; then
    addr="$($cli -conf="$conf" -datadir="$datadir" -rpcwallet="$wallet" getnewaddress 2>/dev/null || true)"
  fi

  if [[ -z "$addr" ]]; then
    echo "Could not create an MFLEX pool address" >&2
    exit 1
  fi

  export MFLEX_POOL_ADDRESS="$addr"
  echo "Generated MFLEX pool address: ${MFLEX_POOL_ADDRESS}"
}

start_miningcore_after_config() {
  systemctl daemon-reload
  systemctl enable miningcore
  systemctl restart miningcore || true
  systemctl status miningcore --no-pager || true
}

print_summary() {
  cat <<EOF

Installation complete.

Profile: ${POOL_MODE}
Miningcore: /opt/miningcore
Miningcore config: /etc/miningcore/config.json
Multiflex Core: /opt/multiflexcoin
Multiflex config: /etc/multiflexcoin/multiflex.conf

Services are started automatically by the installer.

Check status:
  sudo systemctl status multiflexd --no-pager
  sudo systemctl status miningcore --no-pager
  journalctl -u multiflexd -f
  journalctl -u miningcore -f

MFLEX RPC user: ${MFLEX_RPC_USER}
MFLEX RPC port: ${MFLEX_RPC_PORT}
Miningcore pool port: ${MININGCORE_POOL_PORT:-3333}
Log/backup retention: ${POOL_RETENTION_DAYS:-30} days
Maintenance timer: aalnase-pool-maintenance.timer (daily VACUUM ANALYZE + cleanup)
WebUI install requested: ${INSTALL_WEBUI:-false}
WebUI domain: ${WEBUI_DOMAIN:-not configured}
Let's Encrypt email: ${LETSENCRYPT_EMAIL:-not configured}

Generated MFLEX pool address: ${MFLEX_POOL_ADDRESS:-unknown}
If you prefer a different payout address, replace it in /etc/miningcore/config.json and restart miningcore.
EOF
}

main() {
  require_root
  require_ubuntu_24_plus
  ask_pool_mode
  ask_webui_settings
  install_base_packages
  install_postgresql18
  setup_users
  setup_postgres_schema
  build_install_miningcore
  build_install_multiflexcoin
  generate_multiflex_conf
  install_systemd_units
  configure_firewall_hardening
  configure_retention_and_maintenance
  start_multiflex_for_setup
  wait_for_multiflex_rpc
  wait_for_multiflex_sync_hint
  ensure_mflex_pool_address
  generate_miningcore_config
  start_miningcore_after_config
  if [[ "${INSTALL_WEBUI:-false}" == "true" ]]; then
    bash "$REPO_ROOT/contrib/install/install-webui-static.sh"
  fi
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
