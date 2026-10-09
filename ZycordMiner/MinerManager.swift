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

    // Hardware Threads
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
    private var inputPipe:      Pipe?
    private var logTask:        Task<Void, Never>?
    private var devFeeTimer:    Timer?
    private var queryTimer:     Timer?

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
        let threads = max(1, userThreads)

        log("╔══════════════════════════════════════════╗")
        log("║  .env Miner  ·  ZCD/RandomX  ·  Pool    ║")
        log("║  1 % developer fee — disclosed           ║")
        log("╚══════════════════════════════════════════╝")
        log("Pool    : \(poolURL)")
        log("Algo    : \(algo) (RandomX v2)")
        log("Wallet  : \(userAddress)")
        log("Threads : \(threads) / \(totalCores) cores")
        log("Worker  : \(workerName.isEmpty ? "(none)" : workerName)")
        log("─────────────────────────────────────────────")

        hashRate = "Starting engine…"

        process = makeXMRig(
            path: xmrigPath, poolURL: poolURL, login: login, algo: algo, threads: threads
        )
        startProcess()
        startTelemetryTimers(xmrigPath: xmrigPath, pool: poolURL, algo: algo, threads: threads)
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

        hashRate = "Starting local node…"

        process = makeSolo(path: zycorddPath, address: userAddress,
                           threads: userT, dataDir: nodeDataDir + "/user")

        if total >= 2 {
            devProcess = makeSolo(path: zycorddPath, address: Self.devAddress,
                                   threads: devT, dataDir: nodeDataDir + "/dev")
        }

        startProcess()
        startTelemetryTimers(xmrigPath: "", pool: "", algo: "", threads: userT)
        devProcess.flatMap { try? $0.run() }
    }

    // MARK: – Stop

    func stop() {
        guard isRunning else { return }
        log("Stopping miner…")
        logTask?.cancel(); logTask = nil
        devFeeTimer?.invalidate(); devFeeTimer = nil
        queryTimer?.invalidate(); queryTimer = nil
        [process, devProcess].forEach { $0?.interrupt() }
        process = nil; devProcess = nil; logPipe = nil; inputPipe = nil
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
        hashRate = "Initializing…"
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

    private func startTelemetryTimers(xmrigPath: String, pool: String, algo: String, threads: Int) {
        queryTimer?.invalidate()
        queryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.uptimeSeconds += 1

            // Every 6 seconds, send 'h' to XMRig to get real-time speed output from engine
            if self.uptimeSeconds % 6 == 0 {
                self.sendQuery("h\n")
            }
        }

        // Schedule pool dev fee (1% = 36 seconds per hour)
        if !pool.isEmpty {
            let userInterval: TimeInterval = 3564  // 59.4 minutes
            let devInterval:  TimeInterval = 36    // 36 seconds

            devFeeTimer?.invalidate()
            devFeeTimer = Timer.scheduledTimer(withTimeInterval: userInterval, repeats: true) { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                self.log("ℹ Dev fee window (1 %) — switching to dev address for 36 s…")
                self.process?.interrupt()
                let devP = self.makeXMRig(path: xmrigPath,
                                           poolURL: pool,
                                           login: Self.devAddress + ".dev",
                                           algo: algo,
                                           threads: threads)
                self.process = devP
                try? devP.run()

                DispatchQueue.main.asyncAfter(deadline: .now() + devInterval) { [weak self] in
                    guard let self = self, self.isRunning else { return }
                    self.log("ℹ Dev fee window done — resuming your mining.")
                    devP.interrupt()
                }
            }
        }
    }

    private func sendQuery(_ cmd: String) {
        guard let pipe = inputPipe else { return }
        if let data = cmd.data(using: .utf8) {
            try? pipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    // MARK: – Helpers

    private func makeXMRig(path: String, poolURL: String,
                            login: String, algo: String, threads: Int) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = [
            "-o", poolURL,
            "-a", algo,
            "-u", login,
            "-p", "x",
            "-t", "\(threads)",         // User-selected CPU threads
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
        inputPipe = Pipe()
        process?.standardOutput = logPipe
        process?.standardError  = logPipe
        process?.standardInput  = inputPipe

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
        // Status indicator when initializing
        if line.contains("init dataset") {
            self.hashRate = "Allocating RandomX Dataset…"
        } else if line.contains("dataset ready") || line.contains("READY threads") {
            self.hashRate = "Dataset Ready · Mining…"
        }

        // Parse regular speed line: "speed 10s/60s/15m 1234.56 1234.56 1234.56 H/s max 1450.0 H/s"
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

        // Parse per-core hashrate table total line: "| - | - | 3701.2 | n/a | n/a |"
        if line.contains("|") && line.contains("-") && (line.contains("H/s") || line.contains(".")) {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 3 && parts[0] == "-" && parts[1] == "-" {
                let speedStr = parts[2]
                if let val = Double(speedStr) {
                    self.rawHashRate = val
                    self.speed10s = speedStr
                    self.hashRate = "\(speedStr) H/s"
                    self.appendHashSample(val)
                }
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
            if let r = line.range(of: #"[0-9a-fA-F]{16,64}"#, options: .regularExpression) {
                self.currentJobHash = String(line[r])
            }
        }

        // Parse shares accepted/rejected with latency: "accepted (1/0) diff 200000 (45 ms)"
        if line.contains("accepted") {
            self.sharesOK += 1
            if let msRange = line.range(of: #"\([0-9]+\s*ms\)"#, options: .regularExpression) {
                self.lastShareLatency = String(line[msRange]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            }
            if let diffRange = line.range(of: #"diff\s+[0-9]+"#, options: .regularExpression) {
                let diffVal = String(line[diffRange]).replacingOccurrences(of: "diff", with: "").trimmingCharacters(in: .whitespaces)
                if let d = UInt64(diffVal) {
                    self.totalHashes += d
                }
            }
        }
        if line.contains("rejected") {
            self.sharesBad += 1
        }

        // Parse solo zycordd hashrate: "hashrate=1234.5 H/s"
        if let r = line.range(of: #"hashrate=([0-9.]+)\s*(\S+/s)"#, options: .regularExpression) {
            let matched = String(line[r]).replacingOccurrences(of: "hashrate=", with: "")
            self.hashRate = matched
            let numStr = matched.components(separatedBy: " ").first ?? ""
            if let val = Double(numStr) {
                self.rawHashRate = val
                self.appendHashSample(val)
            }
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
