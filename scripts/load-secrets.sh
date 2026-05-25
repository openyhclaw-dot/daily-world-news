#!/usr/bin/env bash
# load-secrets.sh — 從 1Password CLI 載入所有 secrets 為環境變數
# 用法：source scripts/load-secrets.sh
#
# 前提：
#   1. 已安裝 1Password CLI (op)
#   2. 已登入或設定 OP_SERVICE_ACCOUNT_TOKEN
#   3. Vault "openclaw" 中已建立 "secrets" item（secrets 存在 notesPlain field）
#
# .env fallback：若 OP_SERVICE_ACCOUNT_TOKEN 未設定，嘗試從 .env 載入

set -euo pipefail

# Compatible with both bash and zsh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SKILL_DIR}/../.." && pwd)"

# Ensure Homebrew tools are in PATH (macOS)
if [ -d "/opt/homebrew/bin" ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Codex automations start each shell with a minimal environment. Load the
# 1Password service-account token from the user's op env file when available.
if [ -f "${HOME}/.config/op/env" ]; then
  # shellcheck disable=SC1090
  source "${HOME}/.config/op/env"
fi

load_env_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
      export\ *) line="${line#export }" ;;
    esac
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac

    local key="${line%%=*}"
    local value="${line#*=}"
    case "$key" in
      OP_SERVICE_ACCOUNT_TOKEN|TELEGRAM_BOT_TOKEN|TG_BOT_DEFAULT|TELEGRAM_CHAT_ID|BRIGHTDATA_API_TOKEN|R2_API_TOKEN|R2_ACCOUNT_ID|R2_BUCKET)
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "${key}=${value}"
        ;;
    esac
  done < "$file"
}

# Codex automations run from the skill directory. Prefer the local project
# .env, then keep the historical parent .env fallback.
load_env_file "${SKILL_DIR}/.env"
load_env_file "${PROJECT_ROOT}/.env"

if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "🔑 OP_SERVICE_ACCOUNT_TOKEN loaded from local env" >&2
fi

export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TG_BOT_DEFAULT:-}}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:--1003767828002}"
export R2_BUCKET="${R2_BUCKET:-ai-podcast}"

has_local_secrets=1
for VAR in TELEGRAM_BOT_TOKEN R2_API_TOKEN R2_ACCOUNT_ID; do
  eval "VAL=\${${VAR}:-}"
  if [ -z "$VAL" ]; then
    has_local_secrets=0
    break
  fi
done

if [ "$has_local_secrets" -eq 1 ]; then
  echo "✅ Secrets loaded from local env" >&2
  return 0 2>/dev/null || exit 0
fi

# 檢查 op CLI
if ! command -v op &>/dev/null; then
  echo "ERROR: 1Password CLI (op) not found. Install: https://developer.1password.com/docs/cli/get-started/" >&2
  exit 1
fi

# 檢查登入狀態
OP_WHOAMI_ERR="$(op whoami 2>&1 >/dev/null || true)"
if [ -n "$OP_WHOAMI_ERR" ]; then
  if echo "$OP_WHOAMI_ERR" | grep -Eqi 'lookup|no such host|Could not resolve|network|dial tcp'; then
    echo "ERROR: 1Password network/DNS unavailable in current sandbox. Re-run with network/full-access sandbox." >&2
    echo "$OP_WHOAMI_ERR" >&2
    exit 86
  fi
  echo "ERROR: 1Password CLI not authenticated. Run 'op signin' or set OP_SERVICE_ACCOUNT_TOKEN." >&2
  echo "$OP_WHOAMI_ERR" >&2
  exit 1
fi

echo "🔐 Loading secrets from 1Password (vault: openclaw / item: secrets)..." >&2

# Secrets 存在 notesPlain field 中，格式為 KEY=VALUE（每行一個）
# 解析 notesPlain 並 export 需要的變數
NOTES=$(op item get secrets --vault openclaw --fields notesPlain 2>/dev/null || \
        op item get secrets --vault openclaw --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for f in data.get('fields', []):
    if f.get('label') == 'notesPlain':
        print(f.get('value', ''))
        break
")

# Parse KEY=VALUE lines from notes
parse_secret() {
  local key="$1"
  echo "$NOTES" | grep "^${key}=" | head -1 | cut -d= -f2-
}

export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$(parse_secret 'TG_BOT_DEFAULT')}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:--1003767828002}"
export BRIGHTDATA_API_TOKEN="${BRIGHTDATA_API_TOKEN:-$(parse_secret 'BRIGHTDATA_API_TOKEN')}"
export R2_API_TOKEN="${R2_API_TOKEN:-$(parse_secret 'R2_API_TOKEN')}"
export R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-$(parse_secret 'R2_ACCOUNT_ID')}"
export R2_BUCKET="${R2_BUCKET:-$(parse_secret 'R2_BUCKET')}"
[ -z "$R2_BUCKET" ] && export R2_BUCKET="ai-podcast"

# Validate critical secrets
MISSING=0
for VAR in TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID R2_API_TOKEN R2_ACCOUNT_ID; do
  eval "VAL=\${${VAR}:-}"
  if [ -z "$VAL" ]; then
    echo "⚠️  Missing: $VAR" >&2
    MISSING=$((MISSING + 1))
  fi
done

if [ $MISSING -gt 0 ]; then
  echo "❌ ${MISSING} secrets missing — check 1Password item 'openclaw/secrets'" >&2
  exit 1
fi

echo "✅ Secrets loaded (5 items)" >&2
