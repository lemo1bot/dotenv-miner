# .env One Click Miner — macOS Multi-Coin Miner

<p align="center">
  <img src="ZycordMiner/ZycordMiner/Assets.xcassets/Logo.imageset/logo.png" width="160" alt=".env One Click Miner Logo" />
  <br />
  <strong>High-performance, transparent multi-algorithm CPU 1-click miner and wallet generator for macOS.</strong>
  <br /><br />
  <a href="https://github.com/lemo1bot/dotenv-miner/releases/latest/download/DotEnv-1.0.0.dmg">
    <img src="https://img.shields.io/badge/Download_DMG-v1.0.0-00FF66?style=for-the-badge&logo=apple&logoColor=black" alt="Download DotEnv DMG" />
  </a>
  <a href="https://github.com/lemo1bot/dotenv-miner/releases">
    <img src="https://img.shields.io/github/v/release/lemo1bot/dotenv-miner?style=for-the-badge&color=00FF66" alt="Latest Release" />
  </a>
  <a href="#license">
    <img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="MIT License" />
  </a>
</p>

---

## ⚡ Supported Coins & Algorithms

| Coin | Symbol | Algorithm | Mining Engine | Default Pool / Mode |
| :--- | :--- | :--- | :--- | :--- |
| **Zycord** | `ZCD` | RandomX v2 (`rx/2`) | XMRig Native ARM64 | `pool.ariabrain.com:3333` |
| **ConnectCoin** | `XCC` | Pay-to-Connect (`rx/0`) | Stratum Bridge + XMRig | `connectcoincrypto.com:3333` |
| **Common Foundry** | `CMFD` | ForgeMatrix AI PoW | XMRig Native ARM64 | `159.69.194.46:29445` |
| **TrueNorth** | `TNC` | Bitcoin + RandomX (`rx/0`) | Stratum Bridge + XMRig | `stratum.truenorth.io:3333` |
| **Privacy Bank Chain**| `PBC` | Post-Quantum Privacy (`rx/pbc`) | PBCMiner ARM64 | `pool.pbcmining.org:3333` |
| **Blocknet** | `BNT` | Argon2id PoW | Seine Native ARM64 | `bntpool.com:3333` |
| **Parano1d** | `NOID` | Proof-Native L1 (`Poseidon2b`)| Parano1d Native ARM64 | Built-in L1 Miner Node |

---

## 🔑 1-Click Client-Side Wallet Generation

Generate real, cryptographically secure addresses and recovery phrases for all 7 supported coins directly within the app:

- **100% Client-Side CSPRNG**: Generated using macOS Security framework and CryptoKit.
- **12-Word Recovery Phrases & Raw Private Keys**: Immediate backup for every coin.
- **Non-Custodial Privacy Guarantee**:
  > 🔒 **We DO NOT store, save, or transmit your private key or recovery phrase to any server.** Keys are generated purely in local memory and are never saved to disk or network. Always copy down your 12-word seed phrase on paper.
- **Zycord Dual Addresses**: Automatic generation of **Fix / Permanent (02…)** mining wallets and **Temporary / Stealth (01…)** one-shot receiving addresses.
- **Privacy Bank Chain (PBC)**: Cryptographically validated Ed25519 elliptic curve key pairs on CryptoNote standard with Keccak-256 checksums (`Pbe…`).
- **Blocknet (BNT)**: Canonical 68-byte Base58 stealth addresses with SHA3-256 checksums.
- **Parano1d (NOID)**: Canonical Bech32m addresses starting with `o11…`.

---

## 🖥️ UI & Window Features

- **Freely Resizable Window**: Full vertical and horizontal window resizing (minimum 580×480 with no upper constraint) to accommodate custom terminal logging and metrics.
- **Horizontal Token Carousel**: Smooth left and right scrolling navigation controls across all tokens with active algorithm tags.
- **Live Telemetry & Estimation**: Real-time hash rate graph, share latency, accepted/rejected shares, difficulty, block height, and estimated token earnings.
- **Transparent 1% Developer Fee**: Fully disclosed and audited; 36 seconds per hour (1%) mining to the dev address, 99% to the user.

---

## 📦 Bundled Engine Binaries

The DMG includes pre-compiled Apple Silicon binaries signed and ready to run with zero setup:
- `xmrig` (Apple Silicon ARM64)
- `pbcminer` (PBC RandomX ARM64)
- `seine` (Blocknet Argon2id ARM64)
- `parano1d` (Parano1d Proof-Native ARM64)
- `stratum_bridge.py` (Local JSON-RPC bridge for Bitcoin stratum coins)

---

## 🛠️ Building From Source

```bash
# Clone the repository
git clone https://github.com/lemo1bot/dotenv-miner.git
cd dotenv-miner

# Build and package the DMG
chmod +x build_dmg.sh
./build_dmg.sh
```

The compiled application and DMG will be output to `dist/DotEnv-1.0.0.dmg`.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
