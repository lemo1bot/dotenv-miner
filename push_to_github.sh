#!/usr/bin/env bash
# ============================================================
#  push_to_github.sh — Push .env miner repo to GitHub
#
#  Usage:
#    ./push_to_github.sh [repository-name] [--ssh]
#
#  Examples:
#    ./push_to_github.sh dotenv-miner          # HTTPS (uses Personal Access Token)
#    ./push_to_github.sh dotenv-miner --ssh    # SSH (uses ~/.ssh key)
# ============================================================

set -euo pipefail

REPO_NAME="${1:-dotenv-miner}"
USE_SSH=0
[[ "${2:-}" == "--ssh" ]] && USE_SSH=1

GH_USER="lemo1bot"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Pushing to GitHub: $GH_USER/$REPO_NAME"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

git remote remove origin 2>/dev/null || true

if [[ $USE_SSH -eq 1 ]]; then
    REMOTE_URL="git@github.com:$GH_USER/$REPO_NAME.git"
    echo "→ Using SSH remote: $REMOTE_URL"
else
    REMOTE_URL="https://github.com/$GH_USER/$REPO_NAME.git"
    echo "→ Using HTTPS remote: $REMOTE_URL"
    echo "  NOTE: When prompted for password, paste your GitHub Personal Access Token (ghp_...)"
    echo "        Generate one at: https://github.com/settings/tokens"
fi

git remote add origin "$REMOTE_URL"
echo ""
echo "→ Pushing 'main' branch and 'v1.0.0' tag (including DotEnv-1.0.0.dmg)…"
git push -u origin main --tags

echo ""
echo "✓ Successfully pushed to https://github.com/$GH_USER/$REPO_NAME"
