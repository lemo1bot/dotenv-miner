#!/usr/bin/env python3
"""
update_release.py — Uploads the freshly compiled DotEnv-1.0.0.dmg to GitHub Releases.
"""

import sys
import os
import json
import urllib.request
import urllib.error

def main():
    if len(sys.argv) < 4:
        print("Usage: python3 update_release.py <GITHUB_TOKEN> <OWNER> <REPO>")
        sys.exit(1)

    token = sys.argv[1].strip().strip("'").strip('"')
    owner = sys.argv[2].strip()
    repo = sys.argv[3].strip()
    tag = "v1.0.0"

    script_dir = os.path.dirname(os.path.abspath(__file__))
    dmg_path = os.path.join(script_dir, "dist", "DotEnv-1.0.0.dmg")
    if not os.path.isfile(dmg_path):
        dmg_path = os.path.join(script_dir, "DotEnv-1.0.0.dmg")
    if not os.path.isfile(dmg_path):
        print(f"Error: DMG file not found at {dmg_path}")
        sys.exit(1)

    dmg_size_mb = os.path.getsize(dmg_path) / (1024 * 1024)
    print(f"→ Found DMG: {dmg_path} ({dmg_size_mb:.2f} MB)")

    # 1. Fetch public release info (does not require auth)
    print(f"→ Fetching release for tag '{tag}'…")
    rel_url = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    public_req = urllib.request.Request(
        rel_url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "DotEnv-Release-Uploader"
        }
    )
    try:
        with urllib.request.urlopen(public_req) as resp:
            release = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"Failed to fetch public release info: {e.code} {e.reason}")
        sys.exit(1)

    release_id = release["id"]
    upload_url_template = release["upload_url"]  # https://uploads.github.com/.../assets{?name,label}
    upload_base = upload_url_template.split("{")[0]

    # Authentication headers for upload & mutation
    auth_headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "DotEnv-Release-Uploader"
    }

    # 2. Update release title and description
    print("→ Updating release title to '.env One Click Miner v1.0.0'…")
    patch_url = f"https://api.github.com/repos/{owner}/{repo}/releases/{release_id}"
    patch_data = json.dumps({
        "name": ".env One Click Miner v1.0.0",
        "body": "Official macOS Release for .env One Click Miner.\n\n### ⚡ What's New:\n- 1-Click Multi-Coin Wallet Generation (Zycord ZCD, ConnectCoin XCC, Common Foundry CMFD, TrueNorth TNC, Privacy Bank Chain PBC)\n- Dual Zycord Address Support (Fix 02… vs Temporary 01…)\n- 100% Non-Custodial CSPRNG local key derivation with BIP-39 12-word recovery seed\n- Real-Time Live Hashrate, Difficulty & Estimated Token Earnings (1h, 24h, 30d)\n- Native Apple Silicon ARM64 performance with App Nap prevention\n- 1% transparent developer fee"
    }).encode("utf-8")
    patch_req = urllib.request.Request(
        patch_url,
        data=patch_data,
        headers={**auth_headers, "Content-Type": "application/json"},
        method="PATCH"
    )
    try:
        with urllib.request.urlopen(patch_req) as resp:
            print("✓ Release metadata updated to '.env One Click Miner v1.0.0'.")
    except urllib.error.HTTPError as e:
        print(f"Notice: Release title update returned {e.code}: {e.reason}")
        if e.code == 401:
            print("\n❌ 401 Unauthorized: The token was rejected by GitHub.")
            print("   Please check that your GitHub token has the 'repo' scope (or 'contents: write').")
            print("   You can easily edit and attach the DMG directly on GitHub:")
            print(f"   👉 https://github.com/{owner}/{repo}/releases/edit/{tag}\n")
            sys.exit(1)

    # 3. Check for existing asset and delete if present
    for asset in release.get("assets", []):
        if asset["name"] == "DotEnv-1.0.0.dmg":
            asset_id = asset["id"]
            print(f"→ Removing previous asset ID {asset_id}…")
            del_url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}"
            del_req = urllib.request.Request(del_url, headers=auth_headers, method="DELETE")
            try:
                with urllib.request.urlopen(del_req):
                    print("✓ Previous asset removed.")
            except Exception as e:
                print(f"Warning: Could not delete old asset: {e}")

    # 4. Upload fresh DMG
    print("→ Uploading new DotEnv-1.0.0.dmg (8.3 MB)…")
    upload_url = f"{upload_base}?name=DotEnv-1.0.0.dmg"
    with open(dmg_path, "rb") as f:
        file_bytes = f.read()

    upload_req = urllib.request.Request(
        upload_url,
        data=file_bytes,
        headers={
            **auth_headers,
            "Content-Type": "application/x-apple-diskimage",
            "Content-Length": str(len(file_bytes))
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(upload_req) as resp:
            res = json.loads(resp.read().decode())
            print(f"\n✓ Successfully uploaded new DMG to GitHub Release v1.0.0!")
            print(f"  Direct Download URL: {res.get('browser_download_url')}")
    except urllib.error.HTTPError as e:
        print(f"Failed to upload asset: {e.code} {e.reason}")
        print(e.read().decode())
        sys.exit(1)

if __name__ == "__main__":
    main()
