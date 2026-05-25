#!/usr/bin/env bash
# run.sh — orchestrator for daily-world-news
# Wraps deterministic phases so the LLM only needs 1 bash call per phase.
#
# Usage: bash scripts/run.sh <phase>
# Phases: preflight | tech-gather | world-prep | audio | finalize | publish
#
# Exit codes:
#   0  success
#   42 ALREADY_DONE (preflight idempotency — LLM should stop the whole run)
#   1  error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${SKILL_DIR}"

export PATH="/opt/homebrew/bin:$PATH"
export TODAY="${TODAY:-$(TZ=Asia/Tokyo date +%Y-%m-%d)}"
export YESTERDAY="${YESTERDAY:-$(TZ=Asia/Tokyo date -v-1d +%Y-%m-%d 2>/dev/null || TZ=Asia/Tokyo date -d 'yesterday' +%Y-%m-%d)}"

PHASE="${1:-}"

load_project_secrets() {
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/load-secrets.sh"
}

case "$PHASE" in
  preflight)
    # Idempotency: if today's podcast mp3 already exists, we're done.
    if [[ -f "summaries/${TODAY}.mp3" && -f "summaries/${TODAY}-podcast.md" ]]; then
      echo "ALREADY_DONE ${TODAY}" >&2
      exit 42
    fi
    # Load secrets (exports TELEGRAM_*, R2_*, etc.)
    load_project_secrets
    # Deps — silent no-op if already installed
    if ! python3 -c "import feedparser, requests, thefuzz, yfinance, edge_tts" 2>/dev/null; then
      pip3 install feedparser requests thefuzz yfinance edge-tts --break-system-packages -q
    fi
    command -v ffmpeg >/dev/null || brew install ffmpeg
    # Market data
    python3 scripts/fetch_market.py -o "summaries/${TODAY}-market.json"
    # Env echoed for the LLM to reuse
    echo "TODAY=${TODAY}"
    echo "YESTERDAY=${YESTERDAY}"
    echo "PREFLIGHT_OK"
    ;;

  tech-gather)
    # Deterministic fetch + score + dedup (gather_tech.py already filters score≥5)
    python3 gather_tech.py \
      --sources config/TECH_SOURCES.json \
      --yesterday "summaries/${YESTERDAY}-tech.md" \
      --output "summaries/${TODAY}-raw-tech.json"
    # Build compact dedup digest from past 3 days' tech summaries
    python3 scripts/build_dedup_digest.py tech > "summaries/${TODAY}-dedup-tech.txt"
    echo "TECH_GATHER_OK"
    ;;

  world-prep)
    # Build compact dedup digest from past 3 days' world summaries
    python3 scripts/build_dedup_digest.py world > "summaries/${TODAY}-dedup-world.txt"
    echo "WORLD_PREP_OK"
    ;;

  audio)
    python3 scripts/generate-audio.py \
      "summaries/${TODAY}-podcast.md" \
      "summaries/${TODAY}.mp3"
    ;;

  finalize)
    # Pure validation gate — fails sys.exit(1) on any check failure, blocks publish.
    # git ops moved to publish so the regenerated feed.xml is captured in the daily commit.
    python3 scripts/validate.py "${TODAY}"
    echo "VALIDATE_OK"
    ;;

  publish)
    # Publish is often invoked in a fresh automation shell. Make it self-contained
    # instead of relying on the caller to remember to preload secrets.
    load_project_secrets
    bash scripts/upload-r2.sh "summaries/${TODAY}.mp3" "podcasts/${TODAY}.mp3"
    python3 scripts/generate-rss.py
    bash scripts/upload-r2.sh "summaries/feed.xml" "feed.xml"
    # Poll iTunes for today's episode link, send Telegram message (falls back to show URL on timeout)
    python3 scripts/send_apple_link.py --date "${TODAY}"
    # git ops moved here from finalize so the freshly regenerated feed.xml is in the same commit
    git add -A
    if git diff --cached --quiet; then
      echo "nothing to commit"
    else
      git commit -m "📰 每日新聞摘要 ${TODAY}"
    fi
    # Push is mandatory — fail loudly so cron/LLM can retry/diagnose
    git push
    echo "PUBLISH_OK pushed to $(git rev-parse --abbrev-ref HEAD)"
    ;;

  *)
    echo "usage: $0 {preflight|tech-gather|world-prep|audio|finalize|publish}" >&2
    exit 1
    ;;
esac
