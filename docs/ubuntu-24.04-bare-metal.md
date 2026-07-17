# Ubuntu 24.04+ bare-metal install

This fork can run without Docker. The supported bare-metal target is Ubuntu 24.04 or newer with .NET 10 and PostgreSQL 18+.

## What the installer does

`contrib/install/install-ubuntu-24.04.sh` installs and configures:

- .NET 10 SDK/runtime and native build dependencies
- PostgreSQL 18 from the official PostgreSQL APT repository when Ubuntu does not provide it
- the Miningcore PostgreSQL role/database/schema
- Aalnase Miningcore published to `/opt/miningcore`
- Multiflex Core from `https://github.com/Aalnase/multiflexcoin` built from source and installed to `/opt/multiflexcoin`
- `multiflexd.service` and `miningcore.service`
- a generated MFLEX pool config at `/etc/miningcore/config.json`
- log rotation for Miningcore and Multiflex logs with 30-day default retention
- a daily maintenance timer for PostgreSQL `VACUUM (ANALYZE)` and safe cleanup of stale pool temp/backups

`coins.json` is intentionally left untouched. It remains a broad example catalog from which operators can copy the coin definitions they actually need.

## Public pool vs home pool

The installer asks for one of two profiles:

- `public`: intended for a public internet pool. Payment processing is enabled, API rate limiting is enabled at a WebUI-friendly default of `300` requests/second, and the pool uses higher default difficulty.
- `home`: intended for a home/LAN pool. Payment processing is disabled by default, API binds to localhost, API rate limiting is disabled, and the pool starts with lower difficulty.

Override the rate-limit default if needed with `MININGCORE_API_RATE_LIMIT=<requests-per-second>`.
Override the retention window if needed with `POOL_RETENTION_DAYS=<days>`; the default is `30`.

If WebUI installation is enabled later with `INSTALL_WEBUI=true`, the installer requires a public `WEBUI_DOMAIN` and, when HTTPS is enabled, `LETSENCRYPT_EMAIL`. If those variables are not supplied non-interactively, the installer prompts for them so Certbot/Let's Encrypt can issue the certificate correctly.

Run interactively:

```bash
sudo ./contrib/install/install-ubuntu-24.04.sh
```

Or non-interactively:

```bash
sudo POOL_MODE=home ./contrib/install/install-ubuntu-24.04.sh
sudo POOL_MODE=public MFLEX_POOL_ADDRESS=M... ./contrib/install/install-ubuntu-24.04.sh
sudo POOL_MODE=public INSTALL_WEBUI=true WEBUI_DOMAIN=test.go-poolmining.com LETSENCRYPT_EMAIL=admin@example.com ./contrib/install/install-ubuntu-24.04.sh
```

## Important files

- Miningcore binary: `/opt/miningcore/Miningcore`
- Miningcore config: `/etc/miningcore/config.json`
- Multiflex Core binary: `/opt/multiflexcoin/bin/bitcoind`
- MFLEX alias: `/usr/local/bin/multiflexd`
- Multiflex config: `/etc/multiflexcoin/multiflex.conf`
- Multiflex data: `/var/lib/multiflexcoin`
- Logs: `journalctl -u miningcore -f` and `journalctl -u multiflexd -f`
- Logrotate configs: `/etc/logrotate.d/miningcore` and `/etc/logrotate.d/multiflexcoin`
- Maintenance timer: `aalnase-pool-maintenance.timer`

## After install

The installer configures UFW/fail2ban/sysctl hardening, starts `multiflexd`, waits for RPC, prints the current MFLEX chain data-directory size, creates/loads a `poolwallet`, generates a legacy/base58 MFLEX pool payout address, writes it into `/etc/miningcore/config.json`, enforces MFLEX `payoutScheme: SOLO`, and then starts/restarts Miningcore automatically.

Firewall defaults:

- open/rate-limited: `22/tcp` SSH
- open: `3333/tcp` Miningcore Stratum
- open: `24200/tcp` Multiflex P2P
- closed externally: `26015/tcp` Multiflex RPC
- closed externally by default: `4000/tcp` Miningcore API

For a test system that really needs the Miningcore API public, run the installer with `ALLOW_PUBLIC_API=true`. For production, prefer keeping port 4000 private and exposing only selected endpoints through a reverse proxy.

Maintenance defaults:

- Miningcore file logs in `/var/log/miningcore/*.log` rotate daily, are compressed, and keep `POOL_RETENTION_DAYS` days (`30` by default).
- Multiflex `debug.log` rotates daily with the same retention.
- `systemd-journald` is capped and given the same retention window.
- `aalnase-pool-maintenance.timer` runs daily around 03:20 with randomized delay. It removes stale pool-related temp/build files, removes old `/root/backups/*` directories after the retention window, compresses leftover rotated logs, and runs PostgreSQL `VACUUM (ANALYZE)` on the Miningcore database.
- The cleanup job does **not** delete blockchain data, wallets, PostgreSQL data, or current config files.

Check status:

```bash
sudo systemctl status multiflexd --no-pager
sudo systemctl status miningcore --no-pager
journalctl -u miningcore -f
```

If you want to use a different payout address later, edit `/etc/miningcore/config.json`, replace the pool `address`, and restart Miningcore:

```bash
sudo nano /etc/miningcore/config.json
sudo systemctl restart miningcore
```

## Updating

Re-run the installer from an updated checkout. It rebuilds Miningcore and Multiflex Core, refreshes systemd units, and creates timestamped backups of existing config files before regenerating them.

## Notes

- PostgreSQL 18+ is enforced by Miningcore startup when PostgreSQL persistence is configured.
- The installer does not remove legacy/example coins from `coins.json` by design.
- Multiflex Core still uses upstream Bitcoin binary names internally (`bitcoind`, `bitcoin-cli`); the installer adds `multiflexd` and `multiflex-cli` symlinks for operator convenience.
