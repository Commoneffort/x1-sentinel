# CAPYBARA

**Precognitive validator monitoring for X1 (and Solana / Tachyon / Agave).**

Catches the early warning signs of skipped slots before they happen — PoH drift, slot fill creep, banking backpressure, snapshot stalls, CPU saturation — and turns the noise into one HIGH/CRIT signal.

```
        ██████╗ █████╗ ██████╗ ██╗   ██╗██████╗  █████╗ ██████╗  █████╗ 
       ██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗
       ██║     ███████║██████╔╝ ╚████╔╝ ██████╔╝███████║██████╔╝███████║
       ██║     ██╔══██║██╔═══╝   ╚██╔╝  ██╔══██╗██╔══██║██╔══██╗██╔══██║
       ╚██████╗██║  ██║██║        ██║   ██████╔╝██║  ██║██║  ██║██║  ██║
        ╚═════╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
                  precognitive validator monitoring · v0.2
```

Features:

- **12 dashboard panels** with color-coded thresholds, sparklines, and inline help
- **Auto-detection** of validator service, identity, paths, RAID layout, RPC
- **Snapshot-state detector** that suppresses false alarms during snapshot windows
- **Composite risk score** that fires Telegram/Discord alerts at HIGH+
- **Historical CSV** written every minute by the daemon, queryable with `--history`
- **Built-in `?`-help and `--docs`** so operators can read what every value means
- **Free and MIT-licensed** — no fees, no telemetry, no surprise auto-payments

## Quick install

```bash
git clone https://github.com/Commoneffort/x1-sentinel.git
cd x1-sentinel
chmod +x x1-sentinel
./install.sh
```

The installer:
1. Auto-detects your validator service, identity, paths, RPC, disks, RAID
2. Shows what it found and lets you override any value
3. Writes a config to `~/.config/x1-sentinel/sentinel.conf`
4. Optionally installs a systemd user service for daemon mode
5. Optionally configures Telegram or Discord alerts (sends a test message)
6. Optionally opens required firewall ports

Nothing is installed without confirmation. Read `install.sh` first if you prefer.

## Usage

```bash
# Interactive dashboard (default — splash screen, then live monitoring)
x1-sentinel

# In the dashboard:
#   h    toggle inline help next to each metric
#   ?    full help overlay
#   d    open the metric reference manual
#   q    quit

# Background daemon (alerts + writes CSV history every minute)
x1-sentinel --daemon
# or via systemd:
systemctl --user enable --now x1-sentinel

# View metric history once the daemon has accumulated some
x1-sentinel --history          # last 24h
x1-sentinel --history 168      # last week

# Open the metric reference
x1-sentinel --docs

# Discover what your validator emits (debugging)
x1-sentinel --list-metrics 90
```

## What it monitors

| Layer | Signals |
|---|---|
| **PoH** | Tick rate, tick-CV (jitter), lock contention, record latency |
| **Slot timing** | Fill duration vs 400ms budget, near-budget %, peak duration |
| **Slot replay** | Time to validate other leaders' slots |
| **Block production** | Your validator's actual skip rate (lifetime + recent) |
| **Banking stage** | Packet rx/drop, buffered queue, leading vs idle state |
| **TPU/QUIC** | Active connections, throttling, setup timeouts |
| **Block load** | CU consumption per slot vs 48M cap |
| **AccountsDB** | Store/flush latency, snapshot peak duration |
| **Snapshot state** | Active/in-progress/idle detection |
| **Shreds/Turbine** | Repairs, recovered, 1st/2nd layer fast-path |
| **System** | Per-core CPU, loadavg, RAM, page faults, NVMe await/qd/util |
| **RPC drift** | Local slot vs cluster slot |
| **Composite risk** | Weighted score from all subsystems |

## Risk score levels

The composite score is calibrated for X1 mainnet. Each contributor is capped at 30 so no single bad metric can falsely peg the score at CRIT.

| Score | Level | What to do |
|---|---|---|
| 0–25 | LOW | Healthy. Just watch. |
| 26–55 | MED | One subsystem degrading. Investigate the listed driver. |
| 56–90 | HIGH | Multiple stress signals. Likely already missing slots. **Telegram/Discord fires here.** |
| 91+ | CRIT | Active failure or imminent skip burst. |

## Alerts

Configure any combination in `sentinel.conf`:

```bash
TG_TOKEN=...        # Telegram bot from @BotFather
TG_CHAT=...         # Your chat ID from @userinfobot
DISCORD_WEBHOOK=... # Discord webhook URL
WEBHOOK_URL=...     # Generic webhook (POSTs JSON)
```

Alerts are rate-limited per (level + title) to prevent storms. Default: one alert per type per 5 minutes.

## Identity auto-detection

CAPYBARA finds your validator's identity automatically by trying, in order:

1. The `--identity` flag from your validator's systemd unit
2. `~/.config/solana/identity.json`
3. `/root/.config/solana/identity.json`
4. `/home/sol/.config/solana/identity.json`
5. `/home/solana/.config/solana/identity.json`
6. Any `/home/*/.config/solana/identity.json` you have read access to
7. `~/validator-keypair.json`

If the keypair file is readable but `solana-keygen` isn't on PATH, CAPYBARA derives the pubkey directly from the JSON byte array using a built-in base58 encoder. You can also set `PUBKEY=...` in the config to skip the file entirely.

## Supported validator builds

Tested on:
- **Tachyon** (X1 mainnet/testnet) ✓
- **Agave** (Solana) ✓ — most metric names match upstream
- **Solana 1.x** ✓ — legacy fallback parsers included

The parser auto-detects metric names emitted by your build and falls back gracefully when names differ. Run `x1-sentinel --list-metrics 90` if a panel won't populate; paste the output as an issue and we'll add the names.

## Firewall ports

If you accept the firewall step, the installer opens (via `ufw`):
- `8000-8020/tcp+udp` — TPU dynamic range
- `8001/tcp` — gossip
- `8899/tcp` — RPC (only if you're exposing it)

## Uninstall

```bash
systemctl --user disable --now x1-sentinel 2>/dev/null
rm -rf ~/.local/share/x1-sentinel ~/.config/x1-sentinel
rm -f ~/.local/bin/x1-sentinel ~/.config/systemd/user/x1-sentinel.service
```

## Contributing

Bug reports and PRs welcome. Particularly useful: testing on validator builds we haven't covered (Firedancer, custom forks). Run `x1-sentinel --list-metrics 90` and paste the output as an issue.

## License

MIT
