#!/usr/bin/env python3
"""
stratum_bridge.py — Lightweight local Stratum bridge for Bitcoin-derived RandomX coins
Bridges Bitcoin Stratum (mining.subscribe + mining.authorize) to CryptoNote Stratum for XMRig.
Supports ConnectCoin (XCC) and TrueNorth (TNC).
"""

import sys
import socket
import threading
import json
import hashlib
import time

def sha256d(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()

def build_merkle(coinbase_hash, branch):
    root = coinbase_hash
    for b in branch:
        root = sha256d(root + bytes.fromhex(b))
    return root

class StratumBridge:
    def __init__(self, upstream_host, upstream_port, user_address, algo="rx/2", local_port=4455):
        self.upstream_host = upstream_host
        self.upstream_port = int(upstream_port)
        self.user_address = user_address.strip()
        self.algo = algo
        self.local_port = int(local_port)
        self.jobs = {}
        self.extranonce1 = b""
        self.extranonce2_size = 4
        self.difficulty = 0.00002
        self.running = True
        self.clients = []
        self.lock = threading.Lock()
        self.current_cn_job = None

    def start(self):
        print(f"[Bridge] Connecting to upstream stratum: {self.upstream_host}:{self.upstream_port}…")
        self.up_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.up_sock.connect((self.upstream_host, self.upstream_port))

        # Start upstream reader
        threading.Thread(target=self.upstream_reader, daemon=True).start()

        # Subscribe
        sub_req = {"id": 1, "method": "mining.subscribe", "params": ["xmrig/6.26.0"]}
        self.up_sock.sendall((json.dumps(sub_req) + "\n").encode())

        time.sleep(0.3)
        # Authorize
        auth_req = {"id": 2, "method": "mining.authorize", "params": [f"{self.user_address}.mac", "x"]}
        self.up_sock.sendall((json.dumps(auth_req) + "\n").encode())

        # Start local TCP server for XMRig
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", self.local_port))
        self.server.listen(5)
        print(f"[Bridge] Listening for XMRig on 127.0.0.1:{self.local_port}")

        threading.Thread(target=self.server_accept, daemon=True).start()

    def server_accept(self):
        while self.running:
            try:
                client, _ = self.server.accept()
                with self.lock:
                    self.clients.append(client)
                threading.Thread(target=self.client_handler, args=(client,), daemon=True).start()
            except:
                break

    def upstream_reader(self):
        buf = ""
        while self.running:
            try:
                data = self.up_sock.recv(4096).decode("utf-8", errors="ignore")
                if not data:
                    print("[Bridge] Upstream pool disconnected.")
                    break
                buf += data
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    if line.strip():
                        self.handle_upstream_msg(json.loads(line.strip()))
            except Exception as e:
                print(f"[Bridge] Upstream read exception: {e}")
                break

    def handle_upstream_msg(self, msg):
        method = msg.get("method")
        params = msg.get("params", [])

        if method == "mining.set_difficulty":
            self.difficulty = float(params[0])
            print(f"[Bridge] Pool difficulty updated: {self.difficulty}")

        elif method == "mining.notify":
            job_id, prevhash_hex, coinb1_hex, coinb2_hex, branch, ver_hex, nbits_hex, ntime_hex = params[:8]
            seed_hash = params[9] if len(params) > 9 else ("00" * 32)

            extranonce2 = b"\x00" * self.extranonce2_size
            coinbase = bytes.fromhex(coinb1_hex) + self.extranonce1 + extranonce2 + bytes.fromhex(coinb2_hex)
            coinbase_hash = sha256d(coinbase)
            merkle_root = build_merkle(coinbase_hash, branch)

            ver = bytes.fromhex(ver_hex)[::-1]
            prev = bytes.fromhex(prevhash_hex)
            ntime = bytes.fromhex(ntime_hex)[::-1]
            nbits = bytes.fromhex(nbits_hex)[::-1]
            nonce = b"\x00\x00\x00\x00"

            header = ver + prev + merkle_root + ntime + nbits + nonce
            target_val = int(0xFFFFFFFFFFFFFFFF / max(self.difficulty * 4294967296.0, 1.0))
            target_hex = target_val.to_bytes(8, "little").hex()

            self.jobs[job_id] = {
                "extranonce2": extranonce2.hex(),
                "ntime": ntime_hex,
                "header": header
            }

            cn_job = {
                "blob": header.hex(),
                "job_id": job_id,
                "target": target_hex,
                "algo": self.algo,
                "seed_hash": seed_hash,
                "height": 1000
            }
            self.current_cn_job = cn_job

            # Push job to all connected XMRig clients
            with self.lock:
                for c in list(self.clients):
                    push = {"jsonrpc": "2.0", "method": "job", "params": cn_job}
                    try:
                        c.sendall((json.dumps(push) + "\n").encode())
                    except:
                        if c in self.clients: self.clients.remove(c)

        elif msg.get("id") == 1 and "result" in msg:
            res = msg["result"]
            if len(res) >= 2 and res[1]:
                self.extranonce1 = bytes.fromhex(res[1])
                self.extranonce2_size = res[2] if len(res) >= 3 else 4
                print(f"[Bridge] Subscribed to pool! (extranonce1={self.extranonce1.hex()})")

        elif msg.get("id") == 2:
            ok = msg.get("result")
            err = msg.get("error")
            if ok:
                print(f"[Bridge] ✓ Pool authorized worker {self.user_address}.mac successfully!")
            else:
                print(f"[Bridge] ❌ Pool authorization error: {err}")

        elif "result" in msg:
            # Result from mining.submit
            if msg.get("result"):
                print("[Bridge] ✓ Share accepted by pool!")
            elif msg.get("error"):
                print(f"[Bridge] ⚠️ Share rejected by pool: {msg.get('error')}")

    def client_handler(self, client):
        buf = ""
        while self.running:
            try:
                data = client.recv(4096).decode("utf-8", errors="ignore")
                if not data: break
                buf += data
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    if not line.strip(): continue
                    req = json.loads(line.strip())
                    req_id = req.get("id")
                    method = req.get("method")

                    if method == "login":
                        resp = {
                            "id": req_id,
                            "jsonrpc": "2.0",
                            "result": {
                                "id": "local_bridge",
                                "job": self.current_cn_job or {},
                                "status": "OK",
                                "extensions": ["keepalive"]
                            },
                            "error": None
                        }
                        client.sendall((json.dumps(resp) + "\n").encode())

                    elif method == "submit":
                        params = req.get("params", {})
                        job_id = params.get("job_id")
                        nonce_hex = params.get("nonce", "00000000")
                        job = self.jobs.get(job_id, {})
                        extranonce2 = job.get("extranonce2", "00000000")
                        ntime = job.get("ntime", "00000000")

                        submit_req = {
                            "id": 100 + int(req_id if isinstance(req_id, int) else 1),
                            "method": "mining.submit",
                            "params": [f"{self.user_address}.mac", job_id, extranonce2, ntime, nonce_hex]
                        }
                        self.up_sock.sendall((json.dumps(submit_req) + "\n").encode())

                        # Acknowledge XMRig immediately
                        resp = {"id": req_id, "jsonrpc": "2.0", "result": {"status": "OK"}, "error": None}
                        client.sendall((json.dumps(resp) + "\n").encode())

                    elif method == "keepalived":
                        resp = {"id": req_id, "jsonrpc": "2.0", "result": {"status": "KEEPALIVE"}, "error": None}
                        client.sendall((json.dumps(resp) + "\n").encode())
            except Exception as e:
                break

        with self.lock:
            if client in self.clients:
                self.clients.remove(client)

def main():
    if len(sys.argv) < 4:
        print("Usage: stratum_bridge.py <host> <port> <user_address> [algo] [local_port]")
        sys.exit(1)

    host = sys.argv[1]
    port = int(sys.argv[2])
    addr = sys.argv[3]
    algo = sys.argv[4] if len(sys.argv) > 4 else "rx/2"
    local_port = int(sys.argv[5]) if len(sys.argv) > 5 else 4455

    bridge = StratumBridge(host, port, addr, algo=algo, local_port=local_port)
    bridge.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        bridge.running = False
        print("[Bridge] Stopped.")

if __name__ == "__main__":
    main()
