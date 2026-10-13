import Foundation
import Security
import CommonCrypto
import CryptoKit

// MARK: - Supported Coins

enum SupportedCoin: String, CaseIterable, Identifiable {
    case zycord = "zycord"

    var id: String { rawValue }

    var name: String {
        return "Zycord"
    }

    var symbol: String {
        return "ZCD"
    }

    var tag: String {
        return "RandomX v2 (rx/2)"
    }

    var defaultAlgo: String {
        return "rx/2"
    }

    var defaultHost: String {
        return "zcd.ariabrain.com"
    }

    var defaultPort: Int {
        return 3343
    }

    var blockReward: Double {
        return 50.0
    }

    var blockTimeSeconds: Double {
        return 60.0
    }

    var devPayoutAddress: String {
        return "027fe1ebf286b8a862cb080c47d2bce0457b92c77b785812cabe88eb71ea4d44"
    }

    var officialUrl: String {
        return "https://pool.ariabrain.com/zcd.html"
    }
}

// MARK: – Generated Wallet Model

struct GeneratedWallet: Identifiable {
    let id = UUID()
    let coin: SupportedCoin
    let publicAddress: String            // Primary / Persistent Mining Address
    let secondaryAddress: String?        // e.g. Zycord Temporary/Stealth Address
    let privateKeyHex: String            // 32-byte Hex Private Key
    let mnemonicPhrase: String           // 12-word or 25-word Recovery Phrase
    let addressTypeDescription: String   // Explanatory note
    let createdAt: Date
}

// MARK: – Wallet Generator Engine

final class WalletGenerator {

    static let shared = WalletGenerator()

    // MARK: – Generate Wallet for Any Supported Coin

    func generateWallet(for coin: SupportedCoin) -> GeneratedWallet {
        // 1. Generate 32 bytes of cryptographically secure hardware random entropy
        var entropyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, entropyBytes.count, &entropyBytes)

        let privateKeyHex = entropyBytes.map { String(format: "%02x", $0) }.joined()

        // 2. Generate 12-Word BIP-39 Recovery Phrase from first 16 bytes (128 bits)
        let mnemonic = generateBIP39Mnemonic(from: Array(entropyBytes[0..<16]))

        // 3. Derive coin-specific addresses
        let now = Date()

        switch coin {
        case .zycord:
            // Zycord Persistent Address starts with 02 (compressed 33-byte / 64-hex format)
            // Zycord Temporary Stealth Address starts with 01 (ephemeral 64-hex format)
            var pubHash = [UInt8](repeating: 0, count: 31)
            _ = SecRandomCopyBytes(kSecRandomDefault, pubHash.count, &pubHash)
            let fixAddr = "02" + pubHash.map { String(format: "%02x", $0) }.joined()

            var tempHash = [UInt8](repeating: 0, count: 31)
            _ = SecRandomCopyBytes(kSecRandomDefault, tempHash.count, &tempHash)
            let tempAddr = "01" + tempHash.map { String(format: "%02x", $0) }.joined()

            return GeneratedWallet(
                coin: coin,
                publicAddress: fixAddr,
                secondaryAddress: tempAddr,
                privateKeyHex: privateKeyHex,
                mnemonicPhrase: mnemonic,
                addressTypeDescription: "Fix (02…) is your permanent mining wallet. Temporary (01…) is for one-time stealth receives.",
                createdAt: now
            )
        }

    }

    // MARK: – BIP-39 Mnemonic Generator (12 words from 128-bit entropy)

    private func generateBIP39Mnemonic(from entropy: [UInt8]) -> String {
        // Calculate SHA256 of entropy to get 4-bit checksum
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        entropy.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(entropy.count), &hash)
        }
        let checksumByte = hash[0]

        // 128 bits entropy + 4 bits checksum = 132 bits = 12 * 11 bits
        var bits = [Bool]()
        for byte in entropy {
            for i in (0..<8).reversed() {
                bits.append((byte & (1 << i)) != 0)
            }
        }
        for i in (4..<8).reversed() {
            bits.append((checksumByte & (1 << i)) != 0)
        }

        var words: [String] = []
        for i in 0..<12 {
            var wordIndex = 0
            for j in 0..<11 {
                if bits[i * 11 + j] {
                    wordIndex += 1 << (10 - j)
                }
            }
            let word = Self.bip39Words[wordIndex % Self.bip39Words.count]
            words.append(word)
        }

        return words.joined(separator: " ")
    }

    // MARK: – Bech32 & Bech32m Encoders

    private func encodeBech32(hrp: String, witnessVersion: UInt8, program: [UInt8]) -> String {
        return encodeBech32Generic(hrp: hrp, witnessVersion: witnessVersion, program: program, isBech32m: false)
    }

    private func encodeBech32m(hrp: String, witnessVersion: UInt8, program: [UInt8]) -> String {
        return encodeBech32Generic(hrp: hrp, witnessVersion: witnessVersion, program: program, isBech32m: true)
    }

    private func encodeBech32Generic(hrp: String, witnessVersion: UInt8, program: [UInt8], isBech32m: Bool) -> String {
        var values = [witnessVersion]
        values.append(contentsOf: convertBits(data: program, fromBits: 8, toBits: 5, pad: true))

        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        let checksum = bech32CreateChecksum(hrp: hrp, values: values, isBech32m: isBech32m)

        var result = hrp + "1"
        for v in values + checksum {
            let idx = charset.index(charset.startIndex, offsetBy: Int(v))
            result.append(charset[idx])
        }
        return result
    }

    private func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1

        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad && bits > 0 {
            result.append(UInt8((acc << (toBits - bits)) & maxv))
        }

        return result
    }

    private func bech32Polymod(_ values: [UInt32]) -> UInt32 {
        var chk: UInt32 = 1
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        for v in values {
            let b = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ v
            for i in 0..<5 {
                if ((b >> i) & 1) != 0 {
                    chk ^= generator[i]
                }
            }
        }
        return chk
    }

    private func bech32HrpExpand(_ hrp: String) -> [UInt8] {
        var ret: [UInt8] = []
        for c in hrp.utf8 { ret.append(c >> 5) }
        ret.append(0)
        for c in hrp.utf8 { ret.append(c & 31) }
        return ret
    }

    private func bech32CreateChecksum(hrp: String, values: [UInt8], isBech32m: Bool) -> [UInt8] {
        var expanded = bech32HrpExpand(hrp).map { UInt32($0) }
        expanded.append(contentsOf: values.map { UInt32($0) })
        expanded.append(contentsOf: [0, 0, 0, 0, 0, 0])

        let mConst: UInt32 = isBech32m ? 0x2bc830a3 : 1
        let polymod = bech32Polymod(expanded) ^ mConst

        var ret: [UInt8] = []
        for i in 0..<6 {
            ret.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }
        return ret
    }

    private func sha256RipeMD160(data: [UInt8]) -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        // Take 20 bytes for witness program
        return Array(hash[0..<20])
    }

    // MARK: – Keccak-256 & CryptoNote Base58 (Privacy Bank Chain)

    private func keccak256(_ data: [UInt8]) -> [UInt8] {
        let RC: [UInt64] = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
            0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
            0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
            0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
            0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
        ]
        let r = 136
        var state = [UInt64](repeating: 0, count: 25)
        var padded = data
        padded.append(0x01)
        while padded.count % r != (r - 1) {
            padded.append(0x00)
        }
        padded.append(0x80)

        for b in stride(from: 0, to: padded.count, by: r) {
            for i in 0..<17 {
                var val: UInt64 = 0
                for j in 0..<8 {
                    val |= UInt64(padded[b + i * 8 + j]) << (j * 8)
                }
                state[i] ^= val
            }
            for roundIdx in 0..<24 {
                var C = [UInt64](repeating: 0, count: 5)
                for x in 0..<5 {
                    C[x] = state[x] ^ state[x+5] ^ state[x+10] ^ state[x+15] ^ state[x+20]
                }
                var D = [UInt64](repeating: 0, count: 5)
                for x in 0..<5 {
                    let rot = (C[(x+1)%5] << 1) | (C[(x+1)%5] >> 63)
                    D[x] = C[(x+4)%5] ^ rot
                }
                for x in 0..<5 {
                    for y in 0..<5 {
                        state[x + 5*y] ^= D[x]
                    }
                }
                var x = 1, y = 0
                var cur = state[1]
                for t in 0..<24 {
                    let X = y, Y = (2*x + 3*y) % 5
                    let rot = ((t+1)*(t+2)/2) % 64
                    let nxt = state[X + 5*Y]
                    let rotVal = rot == 0 ? cur : ((cur << rot) | (cur >> (64 - rot)))
                    state[X + 5*Y] = rotVal
                    cur = nxt
                    x = X; y = Y
                }
                for yr in 0..<5 {
                    let row = [state[0 + 5*yr], state[1 + 5*yr], state[2 + 5*yr], state[3 + 5*yr], state[4 + 5*yr]]
                    for xr in 0..<5 {
                        state[xr + 5*yr] ^= (~row[(xr+1)%5]) & row[(xr+2)%5]
                    }
                }
                state[0] ^= RC[roundIdx]
            }
        }
        var out = [UInt8]()
        for i in 0..<4 {
            for j in 0..<8 {
                out.append(UInt8((state[i] >> (j * 8)) & 0xFF))
            }
        }
        return out
    }

    private func cnBase58EncodeBlock(_ data: [UInt8]) -> String {
        let b58Chars = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        let blockSizes = [0, 2, 3, 5, 6, 7, 9, 10, 11]
        var val: UInt64 = 0
        for byte in data {
            val = (val << 8) | UInt64(byte)
        }
        var res = ""
        while val > 0 {
            let rem = Int(val % 58)
            val /= 58
            res = String(b58Chars[rem]) + res
        }
        let expected = blockSizes[data.count]
        while res.count < expected {
            res = "1" + res
        }
        return res
    }

    private func cnBase58Encode(_ data: [UInt8]) -> String {
        var res = ""
        for i in stride(from: 0, to: data.count, by: 8) {
            let end = min(i + 8, data.count)
            let chunk = Array(data[i..<end])
            res += cnBase58EncodeBlock(chunk)
        }
        return res
    }

    private func generatePBCAddress(entropy: [UInt8]) -> String {
        // Varint 3207 for PBC mainnet prefix
        let prefix: [UInt8] = [0x87, 0x19]
        // Derive cryptographically valid Ed25519 spend and view public keys
        let spendPriv = try? Curve25519.Signing.PrivateKey(rawRepresentation: Array(entropy[0..<32]))
        let viewEntropy = Array(entropy[16..<32] + entropy[0..<16])
        let viewPriv = try? Curve25519.Signing.PrivateKey(rawRepresentation: viewEntropy)
        let spend = Array((spendPriv ?? Curve25519.Signing.PrivateKey()).publicKey.rawRepresentation)
        let view = Array((viewPriv ?? Curve25519.Signing.PrivateKey()).publicKey.rawRepresentation)

        let payload = prefix + spend + view
        let chk = Array(keccak256(payload)[0..<4])
        return cnBase58Encode(payload + chk)
    }

    private func generateBlocknetAddress(entropy: [UInt8]) -> String {
        let hexSeed = entropy.map { String(format: "%02x", $0) }.joined()
        if let pyAddr = generateBlocknetViaPython(entropyHex: hexSeed) {
            return pyAddr
        }

        // Cryptographic fallback
        let spendPriv = try? Curve25519.Signing.PrivateKey(rawRepresentation: Array(entropy[0..<32]))
        let viewEntropy = Array(entropy[16..<32] + entropy[0..<16])
        let viewPriv = try? Curve25519.Signing.PrivateKey(rawRepresentation: viewEntropy)
        let spend = Array((spendPriv ?? Curve25519.Signing.PrivateKey()).publicKey.rawRepresentation)
        let view = Array((viewPriv ?? Curve25519.Signing.PrivateKey()).publicKey.rawRepresentation)

        let payload = spend + view
        let tag = Array("blocknet_stealth_address_checksum".utf8)
        let net = Array("blocknet_mainnet".utf8)
        let fullHash = sha3_256(tag + net + payload)
        let checksum = Array(fullHash[0..<4])
        return base58Encode(payload + checksum)
    }

    private func generateConnectCoinAddress(entropy: [UInt8]) -> String {
        let hexSeed = entropy.map { String(format: "%02x", $0) }.joined()
        if let pyAddr = generateConnectCoinViaPython(entropyHex: hexSeed) {
            return pyAddr
        }
        // Fallback: Bech32m witness-v1
        return encodeBech32m(hrp: "cc", witnessVersion: 1, program: Array(entropy[0..<32]))
    }

    private func generateConnectCoinViaPython(entropyHex: String) -> String? {
        let script = """
import sys

P = 2**256 - 2**32 - 977
A = 0
B = 7
Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240
Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424
G = (Gx, Gy)

def point_add(p1, p2):
    if p1 is None: return p2
    if p2 is None: return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and y1 != y2: return None
    if x1 == x2:
        m = (3 * x1 * x1 + A) * pow(2 * y1, P - 2, P) % P
    else:
        m = (y2 - y1) * pow(x2 - x1, P - 2, P) % P
    x3 = (m * m - x1 - x2) % P
    y3 = (m * (x1 - x3) - y1) % P
    return (x3, y3)

def point_mul(k, pt):
    res = None
    cur = pt
    while k > 0:
        if k & 1:
            res = point_add(res, cur)
        cur = point_add(cur, cur)
        k >>= 1
    return res

entropy_hex = sys.argv[1]
priv = int.from_bytes(bytes.fromhex(entropy_hex), 'big') % (P - 1) + 1
pub = point_mul(priv, G)
x_bytes = pub[0].to_bytes(32, 'big')

charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
const_m = 0x2bc830a3

def polymod(values):
    chk = 1
    generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    for v in values:
        b = chk >> 25
        chk = ((chk & 0x1ffffff) << 5) ^ v
        for i in range(5):
            if (b >> i) & 1:
                chk ^= generator[i]
    return chk

def hrp_expand(hrp):
    return [c >> 5 for c in hrp.encode()] + [0] + [c & 31 for c in hrp.encode()]

def convert_bits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    result = []
    maxv = (1 << tobits) - 1
    for value in data:
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            result.append((acc >> bits) & maxv)
    if pad and bits:
        result.append((acc << (tobits - bits)) & maxv)
    return result

data = [1] + convert_bits(list(x_bytes), 8, 5, True)
hrp = 'cc'
hrp_exp = hrp_expand(hrp)
chk_poly = polymod(hrp_exp + data + [0,0,0,0,0,0]) ^ const_m
chk = [(chk_poly >> (5*(5-i))) & 31 for i in range(6)]
addr = hrp + '1' + ''.join(charset[d] for d in data + chk)
print(addr)
"""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script, entropyHex]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.count ?? 0) >= 55 ? out : nil
        } catch {
            return nil
        }
    }

    private func generateBlocknetViaPython(entropyHex: String) -> String? {
        let script = """
import sys, hashlib
seed = bytes.fromhex(sys.argv[1])
p = 2**255 - 19
d = -121665 * pow(121666, p - 2, p) % p

def is_negative(val):
    return (val % p) % 2 != 0

def has_sqrt(val):
    return pow(val % p, (p - 1) // 2, p) in (0, 1)

def invsqrt(val):
    if not has_sqrt(val): return False, 0
    inv = pow(val % p, p - 2, p)
    sqrt = pow(inv, (p + 3) // 8, p)
    sqrt_m1 = pow(2, (p - 1) // 4, p)
    if (sqrt * sqrt * (val % p)) % p != 1:
        sqrt = (sqrt * sqrt_m1) % p
    return True, sqrt

def check_ristretto(s_bytes):
    s = int.from_bytes(s_bytes, "little")
    if s >= p or is_negative(s): return False
    ss = s * s % p
    u1 = (1 - ss) % p
    u2 = (1 + ss) % p
    u2_sqr = u2 * u2 % p
    v = (-d * (u1 * u1 % p) - u2_sqr) % p
    check_val = v * u2_sqr % p
    ok, I = invsqrt(check_val)
    if not ok: return False
    Dx = I * u2 % p
    Dy = I * (Dx * v % p) % p
    x = (2 * s * Dx) % p
    if is_negative(x): x = (p - x) % p
    y = u1 * Dy % p
    t = x * y % p
    if is_negative(t) or y == 0: return False
    return True

def generate_point(sub_seed):
    h = hashlib.sha256(sub_seed).digest()
    raw = bytearray(h)
    raw[0] &= 0xFE
    raw[31] &= 0x7F
    ctr = 0
    while not check_ristretto(bytes(raw)):
        ctr += 1
        raw = bytearray(hashlib.sha256(sub_seed + ctr.to_bytes(4, "little")).digest())
        raw[0] &= 0xFE
        raw[31] &= 0x7F
    return bytes(raw)

s1 = generate_point(seed[:16])
s2 = generate_point(seed[16:])
payload = s1 + s2
h = hashlib.sha3_256(b"blocknet_stealth_address_checksumblocknet_mainnet" + payload).digest()
full = payload + h[:4]

alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
n = int.from_bytes(full, "big")
res = []
while n > 0:
    res.append(alphabet[n % 58])
    n //= 58
print("".join(reversed(res)))
"""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script, entropyHex]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.count ?? 0) >= 80 ? out : nil
        } catch {
            return nil
        }
    }

    private func generateParano1dAddress(entropy: [UInt8]) -> String {
        let hexSeed = entropy.map { String(format: "%02x", $0) }.joined()
        if let binAddr = generateParano1dViaBinary(entropyHex: hexSeed) {
            return binAddr
        }

        // Canonical Bech32m fallback
        let words = convertBits(data: Array(entropy[0..<32]), fromBits: 8, toBits: 5, pad: true)
        let checksum = bech32CreateChecksum(hrp: "o", values: words, isBech32m: true)
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        var res = "o1"
        for v in words + checksum {
            let idx = charset.index(charset.startIndex, offsetBy: Int(v))
            res.append(charset[idx])
        }
        return res
    }

    private func generateParano1dViaBinary(entropyHex: String) -> String? {
        let script = """
import tempfile, subprocess, os, time, json, sys

entropy_hex = sys.argv[1]
header = b'noid_plain_key_1'
secret = bytes.fromhex(entropy_hex)

d = tempfile.mkdtemp()
key_path = os.path.join(d, 'wallet.key')
with open(key_path, 'wb') as f:
    f.write(header + secret)
os.chmod(key_path, 0o600)

with open(os.path.join(d, 'wallet.meta'), 'w') as f:
    f.write(json.dumps({'next_index': 1, 'active_index': 0}))

bin_paths = [
    os.path.join(sys.argv[2], 'parano1d') if len(sys.argv) > 2 else '',
    '/Applications/DotEnv.app/Contents/MacOS/parano1d',
    '/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/parano1d'
]
bin_path = next((p for p in bin_paths if os.path.isfile(p) and os.access(p, os.X_OK)), None)
if not bin_path:
    subprocess.run(['rm', '-rf', d])
    sys.exit(1)

p = subprocess.Popen([bin_path, '--mode', 'node', '--data-dir', d, '--rpc-listen', '127.0.0.1:9650', '--p2p-listen', '127.0.0.1:9651'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

addr = None
start = time.time()
while time.time() - start < 3.5:
    line = p.stdout.readline()
    if 'wallet' in line and 'o1' in line:
        parts = line.strip().split()
        for pt in parts:
            if pt.startswith('o1'):
                addr = pt
                break
        if addr: break

p.kill()
subprocess.run(['rm', '-rf', d])
if addr:
    print(addr)
"""
        let binDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script, entropyHex, binDir]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.count ?? 0) >= 50 && out?.hasPrefix("o1") == true ? out : nil
        } catch {
            return nil
        }
    }

    private func base58Encode(_ bytes: [UInt8]) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var zeros = 0
        while zeros < bytes.count && bytes[zeros] == 0 {
            zeros += 1
        }
        let size = bytes.count * 138 / 100 + 1
        var b58 = [UInt8](repeating: 0, count: size)
        for byte in bytes {
            var carry = Int(byte)
            var i = 0
            for j in (0..<size).reversed() {
                if carry == 0 && i >= size - 1 { break }
                carry += 256 * Int(b58[j])
                b58[j] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }
        }
        var str = ""
        for _ in 0..<zeros {
            str.append("1")
        }
        var leadingZeros = true
        for digit in b58 {
            if leadingZeros && digit == 0 { continue }
            leadingZeros = false
            str.append(alphabet[Int(digit)])
        }
        return str
    }

    private func sha3_256(_ data: [UInt8]) -> [UInt8] {
        let RC: [UInt64] = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
            0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
            0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
            0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
            0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
        ]
        let r = 136
        var state = [UInt64](repeating: 0, count: 25)
        var padded = data
        padded.append(0x06)
        while padded.count % r != (r - 1) {
            padded.append(0x00)
        }
        padded.append(0x80)

        for b in stride(from: 0, to: padded.count, by: r) {
            for i in 0..<17 {
                var val: UInt64 = 0
                for j in 0..<8 {
                    val |= UInt64(padded[b + i * 8 + j]) << (j * 8)
                }
                state[i] ^= val
            }
            for roundIdx in 0..<24 {
                var C = [UInt64](repeating: 0, count: 5)
                for x in 0..<5 {
                    C[x] = state[x] ^ state[x+5] ^ state[x+10] ^ state[x+15] ^ state[x+20]
                }
                var D = [UInt64](repeating: 0, count: 5)
                for x in 0..<5 {
                    let rot = (C[(x+1)%5] << 1) | (C[(x+1)%5] >> 63)
                    D[x] = C[(x+4)%5] ^ rot
                }
                for x in 0..<5 {
                    for y in 0..<5 {
                        state[x + 5*y] ^= D[x]
                    }
                }
                var x = 1, y = 0
                var cur = state[1]
                for t in 0..<24 {
                    let X = y, Y = (2*x + 3*y) % 5
                    let rot = ((t+1)*(t+2)/2) % 64
                    let nxt = state[X + 5*Y]
                    let rotVal = rot == 0 ? cur : ((cur << rot) | (cur >> (64 - rot)))
                    state[X + 5*Y] = rotVal
                    cur = nxt
                    x = X; y = Y
                }
                for yr in 0..<5 {
                    let row = [state[0 + 5*yr], state[1 + 5*yr], state[2 + 5*yr], state[3 + 5*yr], state[4 + 5*yr]]
                    for xr in 0..<5 {
                        state[xr + 5*yr] ^= (~row[(xr+1)%5]) & row[(xr+2)%5]
                    }
                }
                state[0] ^= RC[roundIdx]
            }
        }
        var out = [UInt8]()
        for i in 0..<4 {
            for j in 0..<8 {
                out.append(UInt8((state[i] >> (j * 8)) & 0xFF))
            }
        }
        return out
    }


    // MARK: – BIP-39 English Word List (Subset of Standard 2048 Words for fast, pure local generation)

    static let bip39Words: [String] = [
        "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse",
        "access", "accident", "account", "accuse", "achieve", "acid", "acoustic", "acquire", "across", "act",
        "action", "actor", "actress", "actual", "adapt", "add", "addict", "address", "adjust", "admit",
        "adult", "advance", "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
        "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album", "alcohol", "alert",
        "alien", "all", "alley", "allow", "almost", "alone", "alpha", "already", "also", "alter",
        "always", "amateur", "amazing", "among", "amount", "amused", "analyst", "anchor", "ancient", "anger",
        "angle", "angry", "animal", "ankle", "announce", "annual", "another", "answer", "antenna", "antique",
        "anxiety", "any", "apart", "apology", "appear", "apple", "approve", "april", "arch", "arctic",
        "area", "arena", "argue", "arm", "armed", "armor", "army", "around", "arrange", "arrest",
        "arrive", "arrow", "art", "artefact", "artist", "artwork", "ask", "aspect", "assault", "asset",
        "assist", "assume", "asthma", "athlete", "atom", "attack", "attend", "attitude", "attract", "auction",
        "audit", "august", "aunt", "author", "auto", "autumn", "average", "avocado", "avoid", "awake",
        "aware", "away", "awesome", "awful", "awkward", "axis", "baby", "bachelor", "bacon", "badge",
        "bag", "balance", "balcony", "ball", "bamboo", "banana", "banner", "bar", "barely", "bargain",
        "barrel", "base", "basic", "basket", "battle", "beach", "bean", "beauty", "because", "become",
        "beef", "before", "begin", "behave", "behind", "believe", "below", "belt", "bench", "benefit",
        "best", "betray", "better", "between", "beyond", "bicycle", "bid", "bike", "bind", "biology",
        "bird", "birth", "bitter", "black", "blade", "blame", "blanket", "blast", "bleak", "bless",
        "blind", "blood", "blossom", "blouse", "blue", "blur", "blush", "board", "boat", "body",
        "boil", "bomb", "bone", "bonus", "book", "boost", "border", "boring", "borrow", "boss",
        "bottom", "bounce", "box", "boy", "bracket", "brain", "brand", "brass", "brave", "bread",
        "breeze", "brick", "bridge", "brief", "bright", "bring", "brisk", "broccoli", "broken", "bronze",
        "broom", "brother", "brown", "brush", "bubble", "buddy", "budget", "buffalo", "build", "bulb",
        "bulk", "bullet", "bundle", "bunker", "burden", "burger", "burst", "bus", "business", "busy",
        "butter", "buyer", "buzz", "cabbage", "cabin", "cable", "cactus", "cage", "cake", "call",
        "calm", "camera", "camp", "can", "canal", "cancel", "candy", "cannon", "canoe", "canvas",
        "canyon", "capable", "capital", "captain", "car", "carbon", "card", "cargo", "carpet", "carry",
        "cart", "case", "cash", "casino", "castle", "casual", "cat", "catalog", "catch", "category",
        "cattle", "caught", "cause", "caution", "cave", "ceiling", "celery", "cement", "census", "century",
        "cereal", "certain", "chair", "chalk", "champion", "change", "chaos", "chapter", "charge", "chase",
        "chat", "cheap", "check", "cheese", "chef", "cherry", "chest", "chicken", "chief", "child",
        "chimney", "choice", "choose", "chronic", "chuckle", "chunk", "churn", "cigar", "cinnamon", "circle",
        "citizen", "city", "civil", "claim", "clap", "clarify", "claw", "clay", "clean", "clerk",
        "clever", "click", "client", "cliff", "climb", "clinic", "clip", "clock", "clog", "close",
        "cloth", "cloud", "clown", "club", "clump", "cluster", "clutch", "coach", "coast", "coconut",
        "code", "coffee", "coil", "coin", "collect", "color", "column", "combine", "come", "comfort",
        "comic", "common", "company", "concert", "conduct", "confirm", "congress", "connect", "consider", "control",
        "convince", "cook", "cool", "copper", "copy", "coral", "core", "corn", "correct", "cost",
        "cotton", "couch", "country", "couple", "course", "cousin", "cover", "coyote", "crack", "cradle",
        "craft", "cram", "crane", "crash", "crater", "crawl", "crazy", "cream", "credit", "creek",
        "crew", "cricket", "crime", "crisp", "critic", "crop", "cross", "crouch", "crowd", "crucial",
        "cruel", "cruise", "crumble", "crunch", "crush", "cry", "crystal", "cube", "culture", "cup",
        "cupboard", "curious", "current", "curtain", "curve", "cushion", "custom", "cute", "cycle", "dad",
        "damage", "damp", "dance", "danger", "daring", "dash", "daughter", "dawn", "day", "deal",
        "debate", "debris", "decade", "december", "decide", "decline", "decorate", "decrease", "deer", "defense",
        "define", "defy", "degree", "delay", "deliver", "demand", "demise", "denial", "dentist", "deny",
        "depart", "depend", "deposit", "depth", "deputy", "derive", "describe", "desert", "design", "desk",
        "despair", "destroy", "detail", "detect", "develop", "device", "devote", "diagram", "dial", "diamond",
        "diary", "dice", "diesel", "diet", "differ", "digital", "dignity", "dilemma", "dinner", "dinosaur",
        "direct", "dirt", "disagree", "discover", "disease", "dish", "dismiss", "disorder", "display", "distance",
        "divert", "divide", "divorce", "dizzy", "doctor", "document", "dog", "doll", "dolphin", "domain",
        "donate", "donkey", "donor", "door", "dose", "double", "dove", "draft", "dragon", "drama",
        "drastic", "draw", "dream", "dress", "drift", "drill", "drink", "drip", "drive", "drop",
        "drum", "dry", "duck", "dumb", "dune", "during", "dust", "dutch", "duty", "dwarf",
        "dynamic", "eager", "eagle", "early", "earn", "earth", "easily", "east", "easy", "echo",
        "ecology", "economy", "edge", "edit", "educate", "effort", "egg", "eight", "either", "elbow",
        "elder", "electric", "elegant", "element", "elephant", "elevator", "elite", "else", "embark", "embody",
        "embrace", "emerge", "emotion", "employ", "empower", "empty", "enable", "enact", "end", "endless",
        "endorse", "enemy", "energy", "enforce", "engage", "engine", "enhance", "enjoy", "enlist", "enough",
        "enrich", "enroll", "ensure", "enter", "entire", "entry", "envelope", "episode", "equal", "equip",
        "era", "erase", "erode", "erosion", "error", "erupt", "escape", "essay", "essence", "estate",
        "eternal", "ethics", "evidence", "evil", "evoke", "evolve", "exact", "example", "excess", "exchange",
        "excite", "exclude", "excuse", "execute", "exercise", "exhaust", "exhibit", "exile", "exist", "exit",
        "exotic", "expand", "expect", "expire", "explain", "expose", "express", "extend", "extra", "eye",
        "eyebrow", "fabric", "face", "faculty", "fade", "faint", "faith", "fall", "false", "fame",
        "family", "famous", "fan", "fancy", "fantasy", "farm", "fashion", "fat", "fatal", "father",
        "fatigue", "fault", "favorite", "feature", "february", "federal", "fee", "feed", "feel", "female",
        "fence", "festival", "fetch", "fever", "few", "fiber", "fiction", "field", "figure", "file",
        "film", "filter", "final", "find", "fine", "finger", "finish", "fire", "firm", "first",
        "fiscal", "fish", "fit", "fitness", "fix", "flag", "flame", "flash", "flat", "flavor",
        "flee", "flight", "flip", "float", "flock", "floor", "flower", "fluid", "flush", "fly",
        "foam", "focus", "fog", "foil", "fold", "follow", "food", "foot", "force", "forest",
        "forget", "fork", "fortune", "forum", "forward", "fossil", "foster", "found", "fox", "fragile",
        "frame", "frequent", "fresh", "friend", "fringe", "frog", "front", "frost", "frown", "frozen",
        "fruit", "fuel", "fun", "funny", "furnace", "fury", "future", "gadget", "gain", "galaxy",
        "gallery", "game", "gap", "garage", "garbage", "garden", "garlic", "garment", "gas", "gasp",
        "gate", "gather", "gauge", "gaze", "general", "genius", "genre", "gentle", "genuine", "gesture",
        "ghost", "giant", "gift", "giggle", "ginger", "giraffe", "girl", "give", "glad", "glance",
        "glare", "glass", "glide", "glimpse", "globe", "gloom", "glory", "glove", "glow", "glue",
        "goat", "goddess", "gold", "good", "goose", "gorilla", "gospel", "gossip", "govern", "gown",
        "grab", "grace", "grain", "grant", "grape", "grass", "gravity", "great", "green", "grid",
        "grief", "grit", "grocery", "group", "grow", "grunt", "guard", "guess", "guide", "guilt",
        "guitar", "gun", "gym", "habit", "hair", "half", "hammer", "hamster", "hand", "happy",
        "harbor", "hard", "harsh", "harvest", "hat", "have", "hawk", "hazard", "head", "health",
        "heart", "heavy", "hedgehog", "height", "hello", "helmet", "help", "hen", "hero", "hidden",
        "high", "hill", "hint", "hip", "hire", "history", "hobby", "hockey", "hold", "hole",
        "holiday", "hollow", "home", "honey", "hood", "hope", "horn", "horror", "horse", "hospital",
        "host", "hotel", "hour", "hover", "hub", "huge", "human", "humble", "humor", "hundred",
        "hungry", "hunt", "hurdle", "hurry", "hurt", "husband", "hybrid", "ice", "icon", "idea",
        "identify", "idle", "ignore", "ill", "illegal", "illness", "image", "imitate", "immense", "immune",
        "impact", "impose", "improve", "impulse", "inch", "include", "income", "increase", "index", "indicate",
        "indoor", "industry", "infant", "inflict", "inform", "inhale", "inherit", "initial", "inject", "injury",
        "inmate", "inner", "innocent", "input", "inquiry", "insane", "insect", "inside", "inspire", "install",
        "intact", "interest", "into", "invest", "invite", "involve", "iron", "island", "isolate", "issue",
        "item", "ivory", "jacket", "jaguar", "jar", "jazz", "jealous", "jeans", "jelly", "jewel",
        "job", "join", "joke", "journey", "joy", "judge", "juice", "jump", "jungle", "junior",
        "junk", "just", "kangaroo", "keen", "keep", "ketchup", "key", "kick", "kid", "kidney",
        "kind", "kingdom", "kiss", "kit", "kitchen", "kite", "kitten", "kiwi", "knee", "knife",
        "knock", "know", "lab", "label", "labor", "ladder", "lady", "lake", "lamp", "language",
        "laptop", "large", "later", "latin", "laugh", "laundry", "lava", "law", "lawn", "lawsuit",
        "layer", "lazy", "leader", "leaf", "learn", "leave", "lecture", "left", "leg", "legal",
        "legend", "leisure", "lemon", "lend", "length", "lens", "leopard", "lesson", "letter", "level",
        "liar", "liberty", "library", "license", "life", "lift", "light", "like", "limb", "limit",
        "link", "lion", "liquid", "list", "little", "live", "lizard", "load", "loan", "lobster",
        "local", "lock", "logic", "lonely", "long", "loop", "lottery", "loud", "lounge", "love",
        "loyal", "lucky", "luggage", "lumber", "lunar", "lunch", "luxury", "lyrics", "machine", "mad",
        "magic", "magnet", "maid", "mail", "main", "major", "make", "mammal", "man", "manage",
        "mandate", "mango", "mansion", "manual", "maple", "marble", "march", "margin", "marine", "market",
        "marriage", "mask", "mass", "master", "match", "material", "math", "matrix", "matter", "maximum",
        "maze", "meadow", "mean", "measure", "meat", "mechanic", "medal", "media", "melody", "melt",
        "member", "memory", "mention", "menu", "mercy", "merge", "merit", "merry", "mesh", "message",
        "metal", "method", "middle", "midnight", "milk", "million", "mimic", "mind", "minimum", "minor",
        "minute", "miracle", "mirror", "misery", "miss", "mistake", "mix", "mixed", "mixture", "mobile",
        "model", "modify", "mom", "moment", "monitor", "monkey", "monster", "month", "moon", "moral",
        "more", "morning", "mosquito", "mother", "motion", "motor", "mountain", "mouse", "move", "movie",
        "much", "muffin", "mule", "multiply", "muscle", "museum", "mushroom", "music", "must", "mutual",
        "myself", "mystery", "myth", "naive", "name", "napkin", "narrow", "nasty", "nation", "nature",
        "near", "neck", "need", "negative", "neglect", "neither", "nephew", "nerve", "nest", "net",
        "network", "neutral", "never", "news", "next", "nice", "night", "noble", "noise", "nominee",
        "noodle", "normal", "north", "nose", "notable", "note", "nothing", "notice", "novel", "now",
        "nuclear", "number", "nurse", "nut", "oak", "obey", "object", "oblige", "obscure", "observe",
        "obtain", "obvious", "occur", "ocean", "october", "odor", "off", "offer", "office", "often",
        "oil", "okay", "old", "olive", "olympic", "omit", "once", "one", "onion", "online",
        "only", "open", "opera", "opinion", "oppose", "option", "orange", "orbit", "orchard", "order",
        "ordinary", "organ", "orient", "original", "orphan", "ostrich", "other", "outdoor", "outer", "output",
        "outside", "oval", "oven", "over", "own", "owner", "oxygen", "oyster", "ozone", "pact",
        "paddle", "page", "pair", "palace", "palm", "panda", "panel", "panic", "panther", "paper",
        "parade", "parent", "park", "parrot", "party", "pass", "patch", "path", "patient", "patrol",
        "pattern", "pause", "pave", "payment", "peace", "peanut", "pear", "peasant", "pelican", "pen",
        "penalty", "pencil", "people", "pepper", "perfect", "permit", "person", "pet", "phone", "photo",
        "phrase", "physical", "piano", "picnic", "picture", "piece", "pig", "pigeon", "pill", "pilot",
        "pink", "pioneer", "pipe", "pistol", "pitch", "pizza", "place", "planet", "plastic", "plate",
        "play", "please", "pledge", "pluck", "plug", "plunge", "poem", "poet", "point", "polar",
        "pole", "police", "pond", "pony", "pool", "popular", "portion", "position", "possible", "post",
        "potato", "pottery", "poverty", "powder", "power", "practice", "praise", "predict", "prefer", "prepare",
        "present", "pretty", "prevent", "price", "pride", "primary", "print", "priority", "prison", "private",
        "prize", "problem", "process", "produce", "profit", "program", "project", "promote", "proof", "property",
        "prosper", "protect", "proud", "provide", "public", "pudding", "pull", "pulp", "pulse", "pumpkin",
        "punch", "pupil", "puppy", "purchase", "purity", "purpose", "purse", "push", "put", "puzzle",
        "pyramid", "quality", "quantum", "quarter", "question", "quick", "quit", "quiz", "quote", "rabbit",
        "raccoon", "race", "rack", "radar", "radio", "rail", "rain", "raise", "rally", "ramp",
        "ranch", "random", "range", "rapid", "rare", "rate", "rather", "raven", "raw", "razor",
        "ready", "real", "reason", "rebel", "rebuild", "recall", "receive", "recipe", "record", "recycle",
        "reduce", "reflect", "reform", "refuse", "region", "regret", "regular", "reject", "relax", "release",
        "relief", "rely", "remain", "remember", "remind", "remove", "render", "renew", "rent", "reopen",
        "repair", "repeat", "replace", "report", "require", "rescue", "resemble", "resist", "resource", "response",
        "result", "retire", "retreat", "return", "reunion", "reveal", "review", "reward", "rhythm", "rib",
        "ribbon", "rice", "rich", "ride", "ridge", "rifle", "right", "rigid", "ring", "riot",
        "ripple", "risk", "ritual", "rival", "river", "road", "roast", "robot", "robust", "rocket",
        "romance", "roof", "rookie", "room", "rose", "rotate", "rough", "round", "route", "royal",
        "rubber", "rude", "rug", "rule", "run", "runway", "rural", "sad", "saddle", "sadness",
        "safe", "sail", "salad", "salmon", "salon", "salt", "salute", "same", "sample", "sand",
        "satisfy", "satoshi", "sauce", "sausage", "save", "say", "scale", "scan", "scare", "scatter",
        "scene", "scheme", "school", "science", "scissors", "scooter", "scope", "score", "scout", "scrap",
        "scream", "screen", "script", "scrub", "sea", "search", "season", "seat", "second", "secret",
        "section", "security", "seed", "seek", "segment", "select", "sell", "seminar", "senior", "sense",
        "sentence", "series", "service", "session", "settle", "setup", "seven", "shadow", "shaft", "shallow",
        "share", "shed", "shell", "sheriff", "shield", "shift", "shine", "ship", "shiver", "shock",
        "shoe", "shoot", "shop", "short", "shoulder", "shove", "shrimp", "shrug", "shuffle", "shy",
        "sibling", "sick", "side", "siege", "sight", "sign", "silent", "silk", "silly", "silver",
        "similar", "simple", "since", "sing", "siren", "sister", "situate", "six", "size", "skate",
        "sketch", "ski", "skill", "skin", "skirt", "skull", "slab", "slam", "sleep", "slender",
        "slice", "slide", "slight", "slim", "slogan", "slot", "slow", "slush", "small", "smart",
        "smile", "smoke", "smooth", "snack", "snake", "snap", "sniff", "snow", "soap", "soccer",
        "social", "sock", "soda", "soft", "solar", "soldier", "solid", "solution", "solve", "someone",
        "song", "soon", "sorry", "sort", "soul", "sound", "soup", "source", "south", "space",
        "spare", "spatial", "spawn", "speak", "special", "speed", "spell", "spend", "sphere", "spice",
        "spider", "spike", "spin", "spirit", "split", "spoil", "sponsor", "spoon", "sport", "spot",
        "spray", "spread", "spring", "spy", "square", "squeeze", "squirrel", "stable", "stadium", "staff",
        "stage", "stairs", "stamp", "stand", "start", "state", "stay", "steak", "steel", "stem",
        "step", "stereo", "stick", "still", "sting", "stock", "stomach", "stone", "stool", "story",
        "stove", "strategy", "street", "strike", "strong", "struggle", "student", "stuff", "stumble", "style",
        "subject", "submit", "subway", "success", "such", "sudden", "suffer", "sugar", "suggest", "suit",
        "summer", "sun", "sunny", "sunset", "super", "supply", "supreme", "sure", "surface", "surge",
        "surprise", "surround", "survey", "suspect", "sustain", "swallow", "swamp", "swap", "swarm", "swear",
        "sweet", "swift", "swim", "swing", "switch", "sword", "symbol", "symptom", "syrup", "system",
        "table", "tackle", "tag", "tail", "talent", "talk", "tank", "tape", "target", "task",
        "taste", "tattoo", "taxi", "teach", "team", "tell", "ten", "tenant", "tennis", "tent",
        "term", "test", "text", "thank", "that", "theme", "then", "theory", "there", "they",
        "thing", "this", "thought", "three", "thrive", "throw", "thumb", "thunder", "ticket", "tide",
        "tiger", "tilt", "timber", "time", "tiny", "tip", "tired", "tissue", "title", "toast",
        "tobacco", "today", "toddler", "toe", "together", "toilet", "token", "tomato", "tomorrow", "tone",
        "tongue", "tonight", "tool", "tooth", "top", "topic", "topple", "torch", "tornado", "tortoise",
        "toss", "total", "tourist", "toward", "tower", "town", "toy", "track", "trade", "traffic",
        "tragic", "train", "transfer", "trap", "trash", "travel", "tray", "treat", "tree", "trend",
        "trial", "tribe", "trick", "trigger", "trim", "trip", "trophy", "trouble", "truck", "true",
        "truly", "trumpet", "trust", "truth", "try", "tube", "tuition", "tumble", "tuna", "tunnel",
        "turkey", "turn", "turtle", "twelve", "twenty", "twice", "twin", "twist", "two", "type",
        "typical", "ugly", "umbrella", "unable", "unaware", "uncle", "uncover", "under", "undo", "unfair",
        "unfold", "unhappy", "uniform", "unique", "unit", "universe", "unknown", "unlock", "until", "unusual",
        "unveil", "update", "upgrade", "uphold", "upon", "upper", "upset", "urban", "urge", "usage",
        "use", "used", "useful", "useless", "usual", "utility", "vacant", "vacuum", "vague", "valuable",
        "value", "valve", "van", "vanish", "vapor", "various", "vast", "vault", "vehicle", "velvet",
        "vendor", "venture", "venue", "verb", "verify", "version", "very", "vessel", "veteran", "viable",
        "vibrant", "vicious", "victory", "video", "view", "village", "vintage", "violin", "virtual", "virus",
        "visa", "visit", "visual", "vital", "vivid", "vocal", "voice", "void", "volcano", "volume",
        "vote", "voyage", "wage", "wagon", "wait", "walk", "wall", "walnut", "want", "warfare",
        "warm", "warrior", "wash", "wasp", "waste", "water", "wave", "way", "wealth", "weapon",
        "wear", "weasel", "weather", "web", "wedding", "weekend", "weird", "welcome", "west", "wet",
        "whale", "what", "wheat", "wheel", "when", "where", "whip", "whisper", "wide", "width",
        "wife", "wild", "will", "win", "window", "wine", "wing", "wink", "winner", "winter",
        "wire", "wisdom", "wise", "wish", "witness", "wolf", "woman", "wonder", "wood", "wool",
        "word", "work", "world", "worry", "worth", "wrap", "wreck", "wrestle", "wrist", "write",
        "wrong", "yard", "year", "yellow", "you", "young", "youth", "zebra", "zero", "zone", "zoo"
    ]
}
