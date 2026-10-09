#!/usr/bin/env bash
# ============================================================
#  push_to_github.sh — Push .env miner repo to GitHub
#
#  Usage:
#    ./push_to_github.sh [repository-name]
#
#  Example:
#    ./push_to_github.sh dotenv-miner
# ============================================================

set -euo pipefail

REPO_NAME="${1:-dotenv-miner}"
GH_USER="lemo1bot"

echo "╔══════════════════════════════════════════╗"
echo "║  Push to GitHub: $GH_USER/$REPO_NAME"
echo "╚══════════════════════════════════════════╝"
echo ""

# Remove old origin if any
git remote remove origin 2>/dev/null || true

# Add new origin
REMOTE_URL="https://github.com/$GH_USER/$REPO_NAME.git"
echo "→ Setting remote origin: $REMOTE_URL"
git remote add origin "$REMOTE_URL"

echo "→ Pushing 'main' branch (including dist/DotEnv-1.0.0.dmg)…"
git push -u origin main

echo ""
echo "✓ Successfully pushed to https://github.com/$GH_USER/$REPO_NAME"
