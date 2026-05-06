# Codex Usage Window Schedule

Anchor OpenAI Codex CLI rate-limit window to **05:00 daily** by running a minimal request with each account at that time.

After anchoring, the daily quota refresh cycle becomes:
```
05:00 → 10:00 → 15:00 → 20:00 → 01:00
```

## How It Works

Codex subscription quota resets on a rolling 5-hour window from the first request of the cycle. By firing a trivial `codex exec "say hello"` at 05:00 each day, we anchor the window start to 5 AM — maximizing usable hours during the workday.

## Setup

### 1. Install Codex CLI

```bash
npm install -g @openai/codex
```

### 2. Place Auth Files

Copy each account's `auth.json` into `auths/`:

```bash
# Account 1
cp /path/to/account1/auth.json auths/auth-a1.json

# Account 2
cp /path/to/account2/auth.json auths/auth-a2.json
```

The `auths/` directory is gitignored — credentials never leave your machine.

### 3. Test Manually

```bash
bash anchor.sh
```

### 4. Add Crontab

```bash
# Edit crontab
crontab -e

# Add this line:
0 5 * * * /bin/bash /path/to/codex-usage-window-schedule/anchor.sh >> /path/to/codex-usage-window-schedule/anchor.log 2>&1
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

> **Note:** `access_token` and `refresh_token` expire periodically. If anchoring starts failing with auth errors, re-login with `codex login` and update the JSON files.

## Script Behavior

- Iterates all `auths/*.json` files alphabetically
- For each: copies to `~/.codex/auth.json`, runs `codex exec --skip-git-repo-check --ephemeral "say hello"`
- 60s timeout per account
- Logs all output; exit code = number of failed accounts

## File Structure

```
codex-usage-window-schedule/
├── README.md
├── .gitignore          # ignores auths/ and *.log
├── anchor.sh           # main cron script
└── auths/              # (gitignored)
    ├── auth-a1.json
    └── auth-a2.json
```
