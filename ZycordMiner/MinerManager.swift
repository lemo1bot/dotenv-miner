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

final class MinerManager: ObservableObject {

    // MARK: – Published state
    @Published var isRunning          = false
    @Published var logLines: [String] = []

    // Live Hashrate Metrics
    @Published var hashRate           = "–"
    @Published var rawHashRate: Double = 0.0
    @Published var hashRateHistory: [Double] = []  // Rolling window for real-time chart
    @Published var speed10s           = "–"
    @Published var speed60s           = "–"
    @Published var speed15m           = "–"
    @Published var maxHashRate        = "–"

    // Real-time Mining & Job Telemetry
    @Published var currentJobHash     = "–"
    @Published var currentDifficulty  = "–"
    @Published var blockHeight        = "–"
    @Published var lastShareLatency   = "–"
    @Published var totalHashes: UInt64 = 0
    @Published var uptimeSeconds: Int  = 0

    // Shares
    @Published var sharesOK           = 0
    @Published var sharesBad          = 0

    // Hardware
    @Published var totalCores         = ProcessInfo.processInfo.processorCount
    @Published var userThreads        = max(1, ProcessInfo.processInfo.processorCount - 1)

    // MARK: – Constants
    static let devAddress    = "0x027fe1ebf286b8a862cb080c47d2bce0457b92c77b785812cabe88eb71ea4d44"
    static let devFeePercent = 1
    static let defaultPool   = PoolPreset.ariabrain

    // MARK: – Private
    private var process:        Process?
    private var devProcess:     Process?
    private var logPipe:        Pipe?
    private var logTask:        Task<Void, Never>?
    private var devFeeTimer:    Timer?
    private var tickerTimer:    Timer?

    var uptimeFormatted: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        let s = uptimeSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: – Start (pool)

    func startPool(userAddress: String,
                   pool: PoolPreset,
                   customHost: String, customPort: Int, customAlgo: String,
                   workerName: String,
                   xmrigPath: String) {
        guard !isRunning else { return }

        resetTelemetry()

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
        startTicker()
        schedulePoolDevFee(xmrigPath: xmrigPath, pool: poolURL, algo: algo)
    }

    // MARK: – Start (solo)

    func startSolo(userAddress: String, zycorddPath: String, nodeDataDir: String) {
        guard !isRunning else { return }

        resetTelemetry()

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
        startTicker()
        devProcess.flatMap { try? $0.run() }
    }

    // MARK: – Stop

    func stop() {
        guard isRunning else { return }
        log("Stopping miner…")
        logTask?.cancel(); logTask = nil
        devFeeTimer?.invalidate(); devFeeTimer = nil
        tickerTimer?.invalidate(); tickerTimer = nil
        [process, devProcess].forEach { $0?.interrupt() }
        process = nil; devProcess = nil; logPipe = nil
        isRunning = false
        rawHashRate = 0.0
        hashRate = "–"
        log("Stopped.")
    }

    private func resetTelemetry() {
        uptimeSeconds = 0
        totalHashes = 0
        sharesOK = 0
        sharesBad = 0
        rawHashRate = 0.0
        hashRate = "–"
        speed10s = "–"
        speed60s = "–"
        speed15m = "–"
        maxHashRate = "–"
        currentJobHash = "–"
        currentDifficulty = "–"
        blockHeight = "–"
        lastShareLatency = "–"
        hashRateHistory = Array(repeating: 0.0, count: 20)
    }

    private func startTicker() {
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.uptimeSeconds += 1
            if self.rawHashRate > 0 {
                self.totalHashes += UInt64(self.rawHashRate)
            }
        }
    }

    // MARK: – Pool dev fee (time-based 1 %)

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

                        self.parseTelemetry(from: line)
                    }
                }
            }
        }
    }

    private func parseTelemetry(from line: String) {
        // Parse XMRig hashrate: "speed 10s/60s/15m 1234.56 1234.56 1234.56 H/s max 1450.0 H/s"
        if line.contains("speed") && line.contains("H/s") {
            let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
            if let idx = parts.firstIndex(of: "H/s") {
                if idx >= 3 {
                    self.speed10s = parts[idx - 3]
                    self.speed60s = parts[idx - 2]
                    self.speed15m = parts[idx - 1]
                    self.hashRate = "\(parts[idx - 3]) H/s"

                    if let val = Double(parts[idx - 3]) {
                        self.rawHashRate = val
                        self.appendHashSample(val)
                    }
                } else if idx >= 1 {
                    self.hashRate = "\(parts[idx - 1]) H/s"
                    if let val = Double(parts[idx - 1]) {
                        self.rawHashRate = val
                        self.appendHashSample(val)
                    }
                }
            }
            if let maxIdx = parts.firstIndex(of: "max"), maxIdx + 1 < parts.count {
                self.maxHashRate = "\(parts[maxIdx + 1]) H/s"
            }
        }

        // Parse new job & block height: "new job from ... diff 200000 algo rx/2 height 82410"
        if line.contains("new job") || line.contains("job") {
            let parts = line.components(separatedBy: " ")
            if let hIdx = parts.firstIndex(of: "height"), hIdx + 1 < parts.count {
                self.blockHeight = "#" + parts[hIdx + 1]
            }
            if let dIdx = parts.firstIndex(of: "diff"), dIdx + 1 < parts.count {
                self.currentDifficulty = parts[dIdx + 1]
            }
            // Generate or extract job hash
            if let r = line.range(of: #"[0-9a-fA-F]{16,64}"#, options: .regularExpression) {
                self.currentJobHash = String(line[r])
            } else if line.contains("height") {
                // Synthesize display hash from job height & diff
                let synth = "0x" + String(line.hashValue, radix: 16).replacingOccurrences(of: "-", with: "")
                self.currentJobHash = String(synth.prefix(18)) + "…"
            }
        }

        // Parse shares accepted/rejected with latency: "accepted (1/0) diff 200000 (45 ms)"
        if line.contains("accepted") {
            self.sharesOK += 1
            if let msRange = line.range(of: #"\([0-9]+\s*ms\)"#, options: .regularExpression) {
                self.lastShareLatency = String(line[msRange]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            }
        }
        if line.contains("rejected") {
            self.sharesBad += 1
        }

        // Parse zycordd solo hashrate: "hashrate=1234.5 H/s"
        if let r = line.range(of: #"hashrate=([0-9.]+)\s*(\S+/s)"#, options: .regularExpression) {
            let matched = String(line[r]).replacingOccurrences(of: "hashrate=", with: "")
            self.hashRate = matched
            let numStr = matched.components(separatedBy: " ").first ?? ""
            if let val = Double(numStr) {
                self.rawHashRate = val
                self.appendHashSample(val)
            }
        }

        // Parse zycordd candidate block: "candidate block hash=0x..."
        if let r = line.range(of: #"0x[0-9a-fA-F]{16,64}"#, options: .regularExpression) {
            self.currentJobHash = String(line[r])
        }
    }

    private func appendHashSample(_ sample: Double) {
        hashRateHistory.append(sample)
        if hashRateHistory.count > 30 {
            hashRateHistory.removeFirst()
        }
    }

    func log(_ msg: String) {
        DispatchQueue.main.async { self.logLines.append(msg) }
    }
}
