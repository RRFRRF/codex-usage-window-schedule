# Codex Usage Window Schedule

Anchor OpenAI Codex CLI rate-limit window by running a minimal request with each account at scheduled times.

## Schedule Strategy

Two anchor points cover different work patterns:

| Anchor | Beijing Time | UTC | Window Cycle | Scenario |
|--------|-------------|-----|-------------|----------|
| Primary | 05:00 | 21:00 | 5→10→15→20→01 | Morning work |
| Fallback | 11:00 | 03:00 | 11→16→21→02→07 | Skip morning, start afternoon |

- If you use Codex in the morning → 05:00 anchor takes effect, 11:00 run is a no-op (just ~3k tokens wasted)
- If you skip the morning → 05:00 anchor expires unused, 11:00 re-anchors for the afternoon

## How It Works

Codex subscription quota resets on a rolling 5-hour window from the first request of the cycle. By firing a trivial `codex exec "hi"` at the anchor times, we fix the window start — maximizing usable hours during your actual work time.

## Prerequisites

This project is designed to run on a **24/7 server** — you need a machine that's always on to fire the cron jobs. Suitable platforms:

- **OpenClaw** — always-on agent runtime
- **Hermes Agent** — persistent agent with cron/scheduler support
- **Any Linux VPS** — with system crontab
- **Other cron tools** — GitHub Actions, Cloudflare Workers Cron, etc.

## Setup

### 1. Install Codex CLI

```bash
npm install -g @openai/codex
```

### 2. Login Each Account

Run `codex login --device-auth` for each account. This generates `~/.codex/auth.json` with OAuth tokens.

On headless servers (no browser), use the device code flow:

```bash
codex login --device-auth
# → Open https://auth.openai.com/codex/device in your browser
# → Enter the one-time code shown in terminal
```

Repeat for each account. After each successful login, copy the auth file:

```bash
# After logging in account 1
cp ~/.codex/auth.json auths/auth-a1.json

# After logging in account 2
cp ~/.codex/auth.json auths/auth-a2.json
```

The `auths/` directory is gitignored — credentials never leave your machine.

### 3. Test Manually

```bash
bash anchor.sh
```

### 4. Schedule the Cron Jobs

**System crontab (VPS):**

```bash
crontab -e

# Beijing 05:00 = UTC 21:00
0 21 * * * /bin/bash /path/to/codex-usage-window-schedule/anchor.sh >> /path/to/codex-usage-window-schedule/anchor.log 2>&1
# Beijing 11:00 = UTC 03:00
0 3 * * * /bin/bash /path/to/codex-usage-window-schedule/anchor.sh >> /path/to/codex-usage-window-schedule/anchor.log 2>&1
```

**Hermes Agent cron:**

```json
[
  { "name": "codex-anchor-5am",  "schedule": "0 21 * * *", "script": "anchor.sh", "no_agent": true },
  { "name": "codex-anchor-11am", "schedule": "0 3 * * *",  "script": "anchor.sh", "no_agent": true }
]
```

## Auth File Format

Each `auths/*.json` follows the Codex CLI format:

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "<id_token>",
    "access_token": "<access_token>",
    "refresh_token": "<refresh_token>",
    "account_id": "<account_id>"
  },
  "last_refresh": "2026-05-06T02:49:44.198027Z"
}
```

> **Note:** `access_token` and `refresh_token` expire periodically. If anchoring starts failing with auth errors, re-login with `codex login --device-auth` and update the JSON files.

## Script Behavior

- Iterates all `auths/*.json` files alphabetically
- For each: copies to `~/.codex/auth.json`, runs `codex exec --skip-git-repo-check --ephemeral --ignore-user-config --ignore-rules -m gpt-5.4-mini "hi"`
- Uses `gpt-5.4-mini` by default (override via `CODEX_ANCHOR_MODEL` env var)
- ~1,455 tokens per account — minimal overhead
- 60s timeout per account
- Logs all output; exit code = number of failed accounts

## File Structure

```
codex-usage-window-schedule/
├── README.md
├── .gitignore          # ignores auths/*.json and *.log, keeps .gitkeep
├── anchor.sh           # main cron script
└── auths/              # (gitignored for *.json)
    ├── .gitkeep        # keeps directory in repo
    ├── auth-a1.json    # account 1 credentials (not tracked)
    └── auth-a2.json    # account 2 credentials (not tracked)
```
