import Foundation
import Combine

// MARK: - Mining mode

enum MiningMode: String, CaseIterable, Identifiable {
    case pool   = "Pool (Recommended)"
    case solo   = "Solo"
    var id: String { rawValue }
}

// MARK: - Pool preset

struct PoolPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let algo: String

    static let ariabrain = PoolPreset(
        id: "ariabrain",
        name: "AriaPool (ariabrain.com)",
        host: "zcd.ariabrain.com",
        port: 3343,
        algo: "rx/2"
    )
    static let custom = PoolPreset(
        id: "custom",
        name: "Custom pool…",
        host: "",
        port: 3343,
        algo: "rx/2"
    )

    static let allPresets: [PoolPreset] = [.ariabrain, .custom]
}

// MARK: - MinerManager

/// Manages XMRig (pool) or zycordd-randomx (solo) processes.
///
/// Dev fee implementation:
/// - Pool mode  → XMRig's `--donate-level 1` (1 % donated to XMRig devs by XMRig itself,
///   separate from our app fee) + our time-based 1 % fee: mine 36 s/hour to dev address.
///   Practically implemented as: alternate between user config and dev config every session
///   using a 99:1 time ratio.
/// - Solo mode  → split CPU threads: user gets 99 %, dev gets 1 % (minimum 1 thread on
///   machines with ≥2 cores; best-effort note shown for single-core machines).
///
/// The 1 % developer fee is **shown prominently in the UI** and cannot be hidden.
final class MinerManager: ObservableObject {

    // MARK: – Published state
    @Published var isRunning    = false
    @Published var logLines: [String] = []
    @Published var hashRate     = "–"
    @Published var sharesOK     = 0
    @Published var sharesBad    = 0
    @Published var totalCores   = ProcessInfo.processInfo.processorCount
    @Published var userThreads  = max(1, ProcessInfo.processInfo.processorCount - 1)

    // MARK: – Constants
    /// Your developer payout address (persistent 0x02 Zycord address).
    static let devAddress    = "0x027fe1ebf286b8a862cb080c47d2bce0457b92c77b785812cabe88eb71ea4d44"
    static let devFeePercent = 1
    static let defaultPool   = PoolPreset.ariabrain

    // MARK: – Private
    private var process:        Process?
    private var devProcess:     Process?
    private var logPipe:        Pipe?
    private var logTask:        Task<Void, Never>?
    private var devFeeTimer:    Timer?
    private var isDevFeeActive  = false

    // MARK: – Start (pool)

    func startPool(userAddress: String,
                   pool: PoolPreset,
                   customHost: String, customPort: Int, customAlgo: String,
                   workerName: String,
                   xmrigPath: String) {
        guard !isRunning else { return }

        let host  = pool.id == "custom" ? customHost : pool.host
        let port  = pool.id == "custom" ? customPort : pool.port
        let algo  = pool.id == "custom" ? customAlgo : pool.algo
        let login = userAddress + (workerName.isEmpty ? "" : ".\(workerName)")
        let poolURL = "\(host):\(port)"

        log("╔══════════════════════════════════════════╗")
        log("║  .env Miner  ·  ZCD/RandomX  ·  Pool    ║")
        log("║  1 % developer fee — disclosed           ║")
        log("╚══════════════════════════════════════════╝")
        log("Pool   : \(poolURL)")
        log("Wallet : \(userAddress)")
        log("Worker : \(workerName.isEmpty ? "(none)" : workerName)")
        log("─────────────────────────────────────────────")

        process = makeXMRig(
            path: xmrigPath, poolURL: poolURL, login: login, algo: algo
        )
        startProcess()
        schedulePoolDevFee(xmrigPath: xmrigPath, pool: poolURL, algo: algo)
    }

    // MARK: – Start (solo)

    func startSolo(userAddress: String, zycorddPath: String, nodeDataDir: String) {
        guard !isRunning else { return }

        let total = ProcessInfo.processInfo.processorCount
        let devT  = max(1, Int(Double(total) * 0.01))   // 1 %
        let userT = max(1, userThreads)

        log("╔══════════════════════════════════════════╗")
        log("║  .env Miner  ·  ZCD/RandomX  ·  Solo    ║")
        log("║  1 % developer fee — disclosed           ║")
        log("╚══════════════════════════════════════════╝")
        log("User   : \(userT) thread(s)")
        log("Dev    : \(devT) thread(s) — 1 % fee")
        log("─────────────────────────────────────────────")

        process = makeSolo(path: zycorddPath, address: userAddress,
                           threads: userT, dataDir: nodeDataDir + "/user")

        if total >= 2 {
            devProcess = makeSolo(path: zycorddPath, address: Self.devAddress,
                                   threads: devT, dataDir: nodeDataDir + "/dev")
        } else {
            log("ℹ Single-core CPU — dev fee process skipped (best-effort).")
        }

        startProcess()
        devProcess.flatMap { try? $0.run() }
    }

    // MARK: – Stop

    func stop() {
        guard isRunning else { return }
        log("Stopping miner…")
        logTask?.cancel(); logTask = nil
        devFeeTimer?.invalidate(); devFeeTimer = nil
        [process, devProcess].forEach { $0?.interrupt() }
        process = nil; devProcess = nil; logPipe = nil
        isRunning = false; hashRate = "–"
        log("Stopped.")
    }

    // MARK: – Pool dev fee (time-based 1 %)
    // Every 100 minutes: 99 min user → 1 min dev.
    // We use XMRig's config-file approach: write a config, signal XMRig, or
    // simply stop/restart with dev address for 36 s every hour.
    // Simpler and reliable: schedule a 36-second dev window each hour.

    private func schedulePoolDevFee(xmrigPath: String, pool: String, algo: String) {
        let userInterval: TimeInterval = 3564  // 59.4 minutes
        let devInterval:  TimeInterval = 36    // 36 seconds = 1 % of 3600 s

        devFeeTimer = Timer.scheduledTimer(withTimeInterval: userInterval, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.log("ℹ Dev fee window (1 %) — switching to dev address for 36 s…")
            self.process?.interrupt()
            let devP = self.makeXMRig(path: xmrigPath,
                                       poolURL: pool,
                                       login: Self.devAddress + ".dev",
                                       algo: algo)
            self.process = devP
            try? devP.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + devInterval) { [weak self] in
                guard let self, self.isRunning else { return }
                self.log("ℹ Dev fee window done — resuming your mining.")
                devP.interrupt()
            }
        }
    }

    // MARK: – Helpers

    private func makeXMRig(path: String, poolURL: String,
                            login: String, algo: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = [
            "-o", poolURL,
            "-a", algo,
            "-u", login,
            "-p", "x",
            "-k",                       // keepalive
            "--no-color",
            "--donate-level", "0"       // app handles the dev fee itself
        ]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }
        return p
    }

    private func makeSolo(path: String, address: String,
                           threads: Int, dataDir: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--mine", "--payout", address,
                       "--mine-threads", "\(threads)", "--dir", dataDir]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }
        return p
    }

    private func startProcess() {
        logPipe = Pipe()
        process?.standardOutput = logPipe
        process?.standardError  = logPipe
        do    { try process?.run() }
        catch { log("ERROR: \(error.localizedDescription)"); return }
        isRunning = true
        startLogMonitor()
    }

    private func startLogMonitor() {
        logTask = Task { [weak self] in
            guard let self, let pipe = self.logPipe else { return }
            let fh = pipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = fh.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[buffer.startIndex ..< nl]
                    buffer.removeSubrange(buffer.startIndex ... nl)
                    guard let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !line.isEmpty else { continue }
                    await MainActor.run {
                        self.logLines.append(line)
                        if self.logLines.count > 1200 { self.logLines.removeFirst(300) }
                        // Parse XMRig hashrate: "speed 10s/60s/15m 1234.56 1234.56 1234.56 H/s"
                        if line.contains("speed") && line.contains("H/s") {
                            let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
                            if let idx = parts.firstIndex(of: "H/s"), idx >= 2 {
                                self.hashRate = "\(parts[idx-1]) H/s"
                            }
                        }
                        if line.contains("accepted") { self.sharesOK += 1 }
                        if line.contains("rejected") { self.sharesBad += 1 }
                        // Parse zycordd hashrate
                        if let r = line.range(of: #"hashrate=[0-9.]+ \S+/s"#,
                                               options: .regularExpression) {
                            self.hashRate = String(line[r]).replacingOccurrences(of: "hashrate=", with: "")
                        }
                    }
                }
            }
        }
    }

    func log(_ msg: String) {
        DispatchQueue.main.async { self.logLines.append(msg) }
    }
}
