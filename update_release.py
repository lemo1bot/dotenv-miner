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
    print("→ Updating release title to '.env — Blocknet (BNT) & Multi-Coin macOS Miner v1.0.0'…")
    patch_url = f"https://api.github.com/repos/{owner}/{repo}/releases/{release_id}"
    patch_data = json.dumps({
        "name": ".env — Blocknet (BNT) & Multi-Coin macOS Miner v1.0.0",
        "body": "Official macOS Release for **.env** Miner.\n\n### ⚡ Blocknet (BNT) & bntpool.com Features:\n- **Native ARM64 Argon2id Engine (`seine` v0.2.15)**: High performance mining directly on Apple Silicon.\n- **Real-time Live Telemetry**: Actual hardware hashrate graph and live share submission status directly from engine stdout.\n- **Live bntpool.com Integration**: Real-time balance polling (`/api/miner/<address>/balance?include_pending_estimate=true`), immature balance, confirmed balance, total paid, and payout progress bar towards 0.10 BNT.\n- **Blocknet.app Integration**: Auto-detects wallet address from `/Applications/blocknet.app` wallet data in `~/Library/Application Support/blocknet/mainnet/`.\n\n### ⚡ Other Supported Coins:\n- **Zycord (ZCD)**: RandomX v2 (`rx/2`) via bundled native ARM64 XMRig\n- **ConnectCoin (XCC)**: Pay-to-Connect (`rx/0`) via native Stratum Bridge\n- **Common Foundry (CMFD)**: ForgeMatrix AI PoW\n- **TrueNorth (TNC)**: Bitcoin + RandomX (`rx/0`)\n- **Privacy Bank Chain (PBC)**: Post-Quantum Privacy (`rx/pbc`)\n- **Parano1d (NOID)**: Proof-Native L1 (`Poseidon2b`)\n\n### 📦 Installation:\n1. Download `DotEnv-1.0.0.dmg` or `env-1.0.0.dmg` below.\n2. Open the DMG and drag **`.env`** (`DotEnv.app`) to your Applications folder."
    }).encode("utf-8")
    patch_req = urllib.request.Request(
        patch_url,
        data=patch_data,
        headers={**auth_headers, "Content-Type": "application/json"},
        method="PATCH"
    )
    try:
        with urllib.request.urlopen(patch_req) as resp:
            print("✓ Release metadata updated.")
    except urllib.error.HTTPError as e:
        print(f"Notice: Release title update returned {e.code}: {e.reason}")
        if e.code == 401:
            print("\n❌ 401 Unauthorized: The token was rejected by GitHub.")
            sys.exit(1)

    # 3. Check for existing assets and remove old ones
    for asset in release.get("assets", []):
        if asset["name"] in ("DotEnv-1.0.0.dmg", "env-1.0.0.dmg"):
            asset_id = asset["id"]
            print(f"→ Removing previous asset {asset['name']} (ID {asset_id})…")
            del_url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}"
            del_req = urllib.request.Request(del_url, headers=auth_headers, method="DELETE")
            try:
                with urllib.request.urlopen(del_req):
                    print(f"✓ Removed old {asset['name']}.")
            except Exception as e:
                print(f"Warning: Could not delete old asset: {e}")

    # 4. Upload fresh DMGs
    with open(dmg_path, "rb") as f:
        file_bytes = f.read()

    for asset_name in ["DotEnv-1.0.0.dmg", "env-1.0.0.dmg"]:
        print(f"→ Uploading new {asset_name} ({dmg_size_mb:.2f} MB)…")
        upload_url = f"{upload_base}?name={asset_name}"
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
                print(f"✓ Successfully uploaded {asset_name}!")
                print(f"  Download URL: {res.get('browser_download_url')}")
        except urllib.error.HTTPError as e:
            print(f"Failed to upload {asset_name}: {e.code} {e.reason}")
            print(e.read().decode())

if __name__ == "__main__":
    main()
