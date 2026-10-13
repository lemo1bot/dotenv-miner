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
git push -u origin main
git push origin --tags --force

echo ""
echo "✓ Git commits, tags, and files successfully pushed to https://github.com/$GH_USER/$REPO_NAME"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/update_release.py" ]]; then
    echo "─────────────────────────────────────────────────────────────"
    echo "Would you like to automatically update the GitHub Release"
    echo "asset (DotEnv-1.0.0.dmg) on https://github.com/$GH_USER/$REPO_NAME/releases ?"
    echo ""
    echo "Paste your GitHub Personal Access Token (ghp_...) to update"
    echo "the Release page now, or press Enter to skip:"
    read -r -s -p "Token: " GH_PAT || GH_PAT=""
    echo ""
    if [[ -n "$GH_PAT" ]]; then
        python3 "$SCRIPT_DIR/update_release.py" "$GH_PAT" "$GH_USER" "$REPO_NAME"
    fi
fi
