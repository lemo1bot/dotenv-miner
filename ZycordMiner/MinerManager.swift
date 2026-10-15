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

    static func presets(for coin: SupportedCoin) -> [PoolPreset] {
        switch coin {
        case .blocknet:
            let primary = PoolPreset(
                id: "bntpool",
                name: "BNTPool (bntpool.com:3333)",
                host: "bntpool.com",
                port: 3333,
                algo: "argon2id"
            )
            let custom = PoolPreset(
                id: "custom",
                name: "Custom stratum pool…",
                host: "",
                port: 3333,
                algo: "argon2id"
            )
            return [primary, custom]

        case .zycord:
            let primary = PoolPreset(
                id: "ariabrain",
                name: "AriaPool (zcd.ariabrain.com)",
                host: "zcd.ariabrain.com",
                port: 3343,
                algo: "rx/2"
            )
            let custom = PoolPreset(
                id: "custom",
                name: "Custom pool…",
                host: "",
                port: 3343,
                algo: "rx/2"
            )
            return [primary, custom]
        }
    }

    static let bntpool = PoolPreset(
        id: "bntpool",
        name: "BNTPool (bntpool.com:3333)",
        host: "bntpool.com",
        port: 3333,
        algo: "argon2id"
    )
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
        port: 3333,
        algo: "argon2id"
    )

    static let allPresets: [PoolPreset] = [.bntpool, .ariabrain, .custom]
}

// MARK: - MinerManager

final class MinerManager: ObservableObject {

    // MARK: – Published state
    @Published var isRunning          = false
    @Published var logLines: [String] = []
    @Published var activeCoin: SupportedCoin = .blocknet

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
    @Published var userThreads        = 2

    // Live Pool & Earnings Telemetry
    @Published var poolPendingBalance: String   = "0.000000 BNT"
    @Published var poolImmatureBalance: String  = "0.000000 BNT"
    @Published var poolTotalPaid: String        = "0.000000 BNT"
    @Published var poolPaymentsCount: Int       = 0
    @Published var poolActiveWorkers: Int       = 0
    @Published var poolShares24h: Int           = 0
    @Published var poolHashRate: String         = "–"
    @Published var payoutProgress: Double       = 0.0
    @Published var lastPoolUpdate: String       = "–"
    @Published var isRefreshingPool: Bool       = false

    // Real blockchain & network stats from bntpool.com/api/stats
    @Published var networkHashRateVal: Double   = 15770.0
    @Published var poolTotalHashRateVal: Double = 4013.0
    @Published var poolMinersCount: Int         = 187

    // MARK: – Constants
    static let devAddress    = "ZFdwFWvEypMVUAPygLRJ7ossTTqX8WZGJUs5b7AYEvvPSjsGdn836AhFyDP1n2JoKHgXAJNxWXDthJsfBPB2mnGoMt2Tc"
    static let devFeePercent = 1
    static let defaultPool   = PoolPreset.bntpool

    // MARK: – Private
    private var process:        Process?
    private var devProcess:     Process?
    private var logPipe:        Pipe?
    private var inputPipe:      Pipe?
    private var logTask:        Task<Void, Never>?
    private var devFeeTimer:    Timer?
    private var queryTimer:     Timer?
    private var poolTimer:      Timer?
    private var activeMiningAddress: String = ""
    private var isSwitchingFee: Bool = false
    private var sleepAssertion: NSObjectProtocol?
    private var rawMaxHashRate: Double = 0.0


    var uptimeFormatted: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        let s = uptimeSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: – Real-Time Token Earnings Calculations

    func maxAllowedThreads(for coin: SupportedCoin) -> Int {
        switch coin {
        case .blocknet:
            let ramBytes = ProcessInfo.processInfo.physicalMemory
            // Argon2id requires ~2.0 GB RAM per lane.
            // Allocate at most 35% of system RAM so macOS and apps run fast and never swap to disk.
            let safeByRAM = max(1, min(4, Int((Double(ramBytes) * 0.35) / (2.0 * 1024 * 1024 * 1024))))
            return min(safeByRAM, totalCores)
        case .zycord:
            return max(1, totalCores - 1)
        }
    }

    /// Returns estimated network hashrate in H/s for realistic earnings estimation
    func networkHashRate(for coin: SupportedCoin) -> Double {
        switch coin {
        case .blocknet:
            return networkHashRateVal > 0 ? networkHashRateVal : 15770.0
        case .zycord:
            return 4_600_000.0  // ~4.6 MH/s
        }
    }

    func estimatedEarningsPerHour(coin: SupportedCoin) -> Double {
        guard rawHashRate > 0 else { return 0.0 }
        let netHash = max(100.0, networkHashRate(for: coin))
        let userShareOfNetwork = rawHashRate / netHash
        let blocksPerHour = 3600.0 / max(5.0, coin.blockTimeSeconds)
        return userShareOfNetwork * blocksPerHour * coin.blockReward
    }

    func estimatedEarningsPerDay(coin: SupportedCoin) -> Double {
        return estimatedEarningsPerHour(coin: coin) * 24.0
    }

    func estimatedEarningsPerMonth(coin: SupportedCoin) -> Double {
        return estimatedEarningsPerDay(coin: coin) * 30.0
    }

    // MARK: – Start (pool)

    func startPool(coin: SupportedCoin,
                   userAddress: String,
                   pool: PoolPreset,
                   customHost: String, customPort: Int, customAlgo: String,
                   workerName: String,
                   xmrigPath: String,
                   pbcminerPath: String = "",
                   seinePath: String = "",
                   parano1dPath: String = "") {
        guard !isRunning else { return }

        self.activeCoin = coin
        resetTelemetry()

        let host  = pool.id.hasPrefix("custom") ? (customHost.isEmpty ? coin.defaultHost : customHost) : (pool.host.isEmpty ? coin.defaultHost : pool.host)
        let port  = pool.id.hasPrefix("custom") ? (customPort == 0 ? coin.defaultPort : customPort) : (pool.port == 0 ? coin.defaultPort : pool.port)
        let algo  = pool.id.hasPrefix("custom") ? (customAlgo.isEmpty ? coin.defaultAlgo : customAlgo) : (pool.algo.isEmpty ? coin.defaultAlgo : pool.algo)

        // Strip 0x prefix if present
        var cleanAddr = userAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAddr.hasPrefix("0x") || cleanAddr.hasPrefix("0X") {
            cleanAddr = String(cleanAddr.dropFirst(2))
        }

        // Rig identifier (e.g. address.mac)
        let rig = workerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mac" : workerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = "\(cleanAddr).\(rig)"
        let poolURL = "\(host):\(port)"
        let threads = max(1, userThreads)
        let devAddr = coin.devPayoutAddress

        log("╔══════════════════════════════════════════════════════════╗")
        log("║  .env One Click Miner  ·  \(coin.name) (\(coin.symbol))  ·  Pool      ║")
        log("║  Connected to: \(poolURL)                       ║")
        log("╚══════════════════════════════════════════════════════════╝")
        log("Coin    : \(coin.name) (\(coin.symbol))")
        log("Pool    : \(poolURL)")
        log("Algo    : \(algo) (\(coin.tag))")
        log("Wallet  : \(cleanAddr)")
        log("Worker  : \(rig)")
        log("Threads : \(threads) / \(totalCores) cores")
        log("─────────────────────────────────────────────")

        hashRate = "Starting engine…"

        // Prevent macOS App Nap and system idle sleep during mining
        if sleepAssertion == nil {
            sleepAssertion = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Mining \(coin.name) (\(coin.symbol))"
            )
        }

        let minerBinary = coin == .blocknet ? (!seinePath.isEmpty ? seinePath : (Bundle.main.resourceURL?.appendingPathComponent("seine").path ?? "/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/seine")) : xmrigPath

        if coin == .blocknet {
            process = makeSeine(path: minerBinary, poolURL: poolURL, address: cleanAddr, worker: rig, threads: threads)
        } else {
            process = makeXMRig(
                path: minerBinary, poolURL: poolURL, login: login, algo: algo, threads: threads
            )
        }

        activeMiningAddress = cleanAddr
        startProcess()
        startTelemetryTimers(
            coin: coin,
            binaryPath: minerBinary,
            pool: poolURL,
            algo: algo,
            threads: threads,
            userLogin: login,
            userAddress: cleanAddr,
            worker: rig,
            devAddress: devAddr
        )

        // Poll live pool stats for the active coin immediately and every 10 seconds
        fetchPoolStats(coin: coin, address: cleanAddr)
        poolTimer?.invalidate()
        poolTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.fetchPoolStats(coin: self.activeCoin, address: self.activeMiningAddress)
        }
    }


    // MARK: – Start (solo)

    func startSolo(userAddress: String, zycorddPath: String, nodeDataDir: String) {
        guard !isRunning else { return }

        resetTelemetry()

        let total = ProcessInfo.processInfo.processorCount
        let devT  = max(1, Int(Double(total) * 0.01))   // 1 %
        let userT = max(1, userThreads)

        log("╔══════════════════════════════════════════════════════════╗")
        log("║  .env One Click Miner  ·  ZCD/RandomX  ·  Solo           ║")
        log("║  1 % developer fee — disclosed                           ║")
        log("╚══════════════════════════════════════════════════════════╝")
        log("User   : \(userT) thread(s)")
        log("Dev    : \(devT) thread(s) — 1 % fee")
        log("─────────────────────────────────────────────")

        hashRate = "Starting local node…"

        // Prevent macOS App Nap and system idle sleep during mining
        if sleepAssertion == nil {
            sleepAssertion = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Mining Zycord (ZCD) Solo"
            )
        }

        process = makeSolo(path: zycorddPath, address: userAddress,
                           threads: userT, dataDir: nodeDataDir + "/user")

        if total >= 2 {
            devProcess = makeSolo(path: zycorddPath, address: Self.devAddress,
                                   threads: devT, dataDir: nodeDataDir + "/dev")
        }

        startProcess()
        startTelemetryTimers(coin: .zycord, binaryPath: "", pool: "", algo: "", threads: userT, userLogin: "", userAddress: userAddress, worker: "solo")
        devProcess.flatMap { try? $0.run() }
    }

    // MARK: – Stop

    func stop() {
        guard isRunning else { return }
        log("Stopping miner…")
        logTask?.cancel(); logTask = nil
        devFeeTimer?.invalidate(); devFeeTimer = nil
        queryTimer?.invalidate(); queryTimer = nil
        poolTimer?.invalidate(); poolTimer = nil
        if let assertion = sleepAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            sleepAssertion = nil
        }
        [process, devProcess].forEach {
            $0?.terminate()
            $0?.interrupt()
        }
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
        rawMaxHashRate = 0.0
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

    private func startTelemetryTimers(
        coin: SupportedCoin,
        binaryPath: String,
        pool: String,
        algo: String,
        threads: Int,
        userLogin: String,
        userAddress: String,
        worker: String,
        devAddress: String = MinerManager.devAddress
    ) {
        queryTimer?.invalidate()
        queryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.uptimeSeconds += 1

            // Every 6 seconds, send 'h' to XMRig to get real-time speed output from engine (if xmrig)
            if coin != .blocknet && self.uptimeSeconds % 6 == 0 {
                self.sendQuery("h\n")
            }
        }

        // Schedule pool dev fee (1% = 36 seconds per hour)
        // Skip if the user is already mining to the dev address!
        let isDevSelf = userAddress.lowercased() == devAddress.lowercased() || userLogin.lowercased().hasPrefix(devAddress.lowercased())
        if !pool.isEmpty && !isDevSelf {
            let userInterval: TimeInterval = 3564  // 59.4 minutes
            let devInterval:  TimeInterval = 36    // 36 seconds

            devFeeTimer?.invalidate()
            devFeeTimer = Timer.scheduledTimer(withTimeInterval: userInterval, repeats: true) { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                self.log("ℹ Dev fee window (1 %) — switching to dev address for 36 s…")
                
                self.isSwitchingFee = true
                self.process?.terminate()
                self.process = nil

                let devP: Process
                if coin == .blocknet {
                    devP = self.makeSeine(path: binaryPath, poolURL: pool, address: devAddress, worker: "dev", threads: threads)
                } else {
                    devP = self.makeXMRig(path: binaryPath, poolURL: pool, login: devAddress + ".dev", algo: algo, threads: threads)
                }
                self.process = devP
                self.startProcess()
                self.isSwitchingFee = false

                DispatchQueue.main.asyncAfter(deadline: .now() + devInterval) { [weak self] in
                    guard let self = self, self.isRunning else { return }
                    self.log("ℹ Dev fee window done — resuming your mining.")
                    
                    self.isSwitchingFee = true
                    self.process?.terminate()
                    self.process = nil

                    let userP: Process
                    if coin == .blocknet {
                        userP = self.makeSeine(path: binaryPath, poolURL: pool, address: userAddress, worker: worker, threads: threads)
                    } else {
                        userP = self.makeXMRig(path: binaryPath, poolURL: pool, login: userLogin, algo: algo, threads: threads)
                    }
                    self.process = userP
                    self.startProcess()
                    self.isSwitchingFee = false
                    self.log("✓ Resumed mining to your wallet: \(userAddress)")
                }
            }
        } else if isDevSelf {
            self.log("ℹ Developer wallet detected: 100% full-time mining, dev-fee timer bypassed.")
        }
    }

    private func sendQuery(_ cmd: String) {
        guard let pipe = inputPipe else { return }
        if let data = cmd.data(using: .utf8) {
            try? pipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    // MARK: – Helpers

    private func makeSeine(path: String, poolURL: String,
                           address: String, worker: String, threads: Int) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        let cleanPool = poolURL.replacingOccurrences(of: "stratum+tcp://", with: "").replacingOccurrences(of: "stratum+ssl://", with: "")

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let seineDataDir = appSupport.appendingPathComponent("DotEnvMiner/seine-data").path
        try? FileManager.default.createDirectory(atPath: seineDataDir, withIntermediateDirectories: true)

        let safeMax = maxAllowedThreads(for: .blocknet)
        let effectiveThreads = max(1, min(threads, safeMax))

        p.arguments = [
            "--ui", "plain",
            "--mode", "pool",
            "--pool-url", cleanPool,
            "--address", address,
            "--pool-worker", worker,
            "--threads", "\(effectiveThreads)",
            "--data-dir", seineDataDir,
            "--backend-control-timeout-ms", "120000",
            "--allow-best-effort-deadlines",
            "--stats-secs", "1",
            "--allow-oversubscribe"
        ]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.isSwitchingFee {
                    self.isRunning = false
                }
            }
        }
        return p
    }

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
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.isSwitchingFee {
                    self.isRunning = false
                }
            }
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
        logTask?.cancel()
        logPipe = Pipe()
        inputPipe = Pipe()
        process?.standardOutput = logPipe
        process?.standardError  = logPipe
        process?.standardInput  = inputPipe

        do {
            try process?.run()
        } catch {
            let msg = error.localizedDescription
            log("ERROR: \(msg)")
            DispatchQueue.main.async {
                self.hashRate = "Error: \(msg)"
                self.isRunning = false
            }
            return
        }
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
        // Parse Seine net miner (Argon2id for Blocknet)
        // 1. STATS: "INFO   STATS     elapsed=4.0s hashes=7 rate=1.746 H/s templates=1 submitted=0 stale=0 accepted=0 deferred=0 dropped=0"
        if line.contains("STATS") && line.contains("rate=") {
            if let rRange = line.range(of: #"rate=\s*([0-9.]+)\s*H/s"#, options: .regularExpression) {
                let matched = String(line[rRange])
                let valStr = matched.replacingOccurrences(of: "rate=", with: "").replacingOccurrences(of: "H/s", with: "").trimmingCharacters(in: .whitespaces)
                if let val = Double(valStr) {
                    self.rawHashRate = val
                    self.hashRate = String(format: "%.2f H/s", val)
                    self.appendHashSample(val)
                    self.speed10s = String(format: "%.2f", val)
                    self.speed60s = String(format: "%.2f", val)
                    if val > self.rawMaxHashRate {
                        self.rawMaxHashRate = val
                        self.maxHashRate = String(format: "%.2f H/s", val)
                    }
                }
            }
            if let hRange = line.range(of: #"hashes=([0-9]+)"#, options: .regularExpression) {
                let matched = String(line[hRange]).replacingOccurrences(of: "hashes=", with: "")
                if let hVal = UInt64(matched) {
                    self.totalHashes = hVal
                }
            }
            if let accRange = line.range(of: #"accepted=([0-9]+)"#, options: .regularExpression) {
                let matched = String(line[accRange]).replacingOccurrences(of: "accepted=", with: "")
                if let acc = Int(matched) {
                    self.sharesOK = acc
                }
            }
            if let staleRange = line.range(of: #"stale=([0-9]+)"#, options: .regularExpression) {
                let matched = String(line[staleRange]).replacingOccurrences(of: "stale=", with: "")
                if let st = Int(matched) {
                    self.sharesBad = st
                }
            }
        }

        // 2. JOB: "INFO   JOB       new job height=66274 difficulty=60"
        if line.contains("JOB") && line.contains("height=") {
            if let hRange = line.range(of: #"height=([0-9]+)"#, options: .regularExpression) {
                let h = String(line[hRange]).replacingOccurrences(of: "height=", with: "")
                self.blockHeight = "#" + h
            }
            if let dRange = line.range(of: #"difficulty=([0-9]+)"#, options: .regularExpression) {
                let d = String(line[dRange]).replacingOccurrences(of: "difficulty=", with: "")
                self.currentDifficulty = d
            }
        }

        // 3. SHARE:
        if line.contains("SHARE") && line.contains("accepted") {
            self.sharesOK += 1
            self.lastShareLatency = "Accepted ✓"
        }
        if line.contains("SHARE") && line.contains("submitted") {
            self.lastShareLatency = "Submitting…"
        }
        if line.contains("SHARE") && (line.contains("rejected") || line.contains("stale") || line.contains("dropped")) {
            self.sharesBad += 1
            self.lastShareLatency = "Rejected ✗"
        }
        if line.contains("AUTH") && line.contains("login accepted") {
            if self.rawHashRate == 0.0 {
                self.hashRate = "Mining Active · Argon2id"
            }
        }

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

        // Parse general hashrate (e.g. Seine, Parano1d, custom miner logs)
        if (line.contains("H/s") || line.contains("h/s")) && !line.contains("speed") && !line.contains("diff") && !line.contains("max") {
            if let r = line.range(of: #"([0-9]+(\.[0-9]+)?)\s*([kKMGT]?H/s)"#, options: .caseInsensitive) {
                let matched = String(line[r])
                self.hashRate = matched
                let numStr = matched.components(separatedBy: " ").first ?? ""
                if let val = Double(numStr) {
                    var mult = 1.0
                    let lower = matched.lowercased()
                    if lower.contains("kh/s") { mult = 1_000.0 }
                    else if lower.contains("mh/s") { mult = 1_000_000.0 }
                    else if lower.contains("gh/s") { mult = 1_000_000_000.0 }
                    self.rawHashRate = val * mult
                    self.appendHashSample(val * mult)
                }
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

    // MARK: – Live Pool API Stats (Multi-Coin)

    func fetchPoolStats(address: String) {
        fetchPoolStats(coin: activeCoin, address: address)
    }

    func fetchPoolStats(coin: SupportedCoin, address: String) {
        var cleanAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAddr.hasPrefix("0x") || cleanAddr.hasPrefix("0X") {
            cleanAddr = String(cleanAddr.dropFirst(2))
        }
        guard cleanAddr.count >= 15 else { return }

        DispatchQueue.main.async { self.isRefreshingPool = true }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())

        switch coin {
        case .blocknet:
            let group = DispatchGroup()

            // 1. Fetch balance & pending estimates
            if let balUrl = URL(string: "https://bntpool.com/api/miner/\(cleanAddr)/balance?include_pending_estimate=true") {
                group.enter()
                var req = URLRequest(url: balUrl)
                req.timeoutInterval = 8.0
                req.cachePolicy = .reloadIgnoringLocalCacheData
                URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                    defer { group.leave() }
                    guard let self = self, let data = data,
                          let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
                    let balObj = dict["balance"] as? [String: Any]
                    let estObj = dict["pending_estimate"] as? [String: Any]

                    let confPending = (balObj?["pending_confirmed"] as? NSNumber)?.doubleValue ?? 0.0
                    let paid = (balObj?["paid"] as? NSNumber)?.doubleValue ?? 0.0
                    let estPending = (estObj?["estimated_pending"] as? NSNumber)?.doubleValue ?? 0.0

                    let totalPendingBNT = (confPending + estPending) / 100_000_000.0
                    let confPendingBNT = confPending / 100_000_000.0
                    let immatureBNT = estPending / 100_000_000.0
                    let paidBNT = paid / 100_000_000.0
                    let progress = min(1.0, max(0.0, confPendingBNT / 0.1)) // 0.1 BNT min threshold

                    DispatchQueue.main.async {
                        self.poolPendingBalance = String(format: "%.6f BNT", totalPendingBNT)
                        self.poolImmatureBalance = String(format: "%.6f BNT", immatureBNT)
                        self.poolTotalPaid = String(format: "%.4f BNT", paidBNT)
                        self.payoutProgress = progress
                    }
                }.resume()
            }

            // 2. Fetch miner stats (hashrate, workers, accepted shares, blocks)
            if let minerUrl = URL(string: "https://bntpool.com/api/miner/\(cleanAddr)") {
                group.enter()
                var req = URLRequest(url: minerUrl)
                req.timeoutInterval = 8.0
                req.cachePolicy = .reloadIgnoringLocalCacheData
                URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                    defer { group.leave() }
                    guard let self = self, let data = data,
                          let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
                    let hr = (dict["hashrate"] as? NSNumber)?.doubleValue ?? 0.0
                    let accepted = (dict["total_accepted"] as? NSNumber)?.intValue ?? 0
                    let rejected = (dict["total_rejected"] as? NSNumber)?.intValue ?? 0
                    let workers = (dict["workers"] as? [Any])?.count ?? 0

                    DispatchQueue.main.async {
                        self.poolActiveWorkers = workers
                        self.poolShares24h = accepted
                        self.poolHashRate = String(format: "%.2f H/s", hr)
                        if self.sharesOK == 0 && accepted > 0 {
                            self.sharesOK = accepted
                        }
                        if self.sharesBad == 0 && rejected > 0 {
                            self.sharesBad = rejected
                        }
                    }
                }.resume()
            }

            // 3. Fetch global stats
            if let statsUrl = URL(string: "https://bntpool.com/api/stats") {
                group.enter()
                var req = URLRequest(url: statsUrl)
                req.timeoutInterval = 8.0
                req.cachePolicy = .reloadIgnoringLocalCacheData
                URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                    defer { group.leave() }
                    guard let self = self, let data = data,
                          let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
                    let chain = dict["chain"] as? [String: Any]
                    let pool = dict["pool"] as? [String: Any]

                    let netHR = (chain?["network_hashrate"] as? NSNumber)?.doubleValue ?? 15770.0
                    let pHR = (pool?["hashrate"] as? NSNumber)?.doubleValue ?? 4000.0
                    let pMiners = (pool?["miners"] as? NSNumber)?.intValue ?? 180

                    DispatchQueue.main.async {
                        self.networkHashRateVal = netHR
                        self.poolTotalHashRateVal = pHR
                        self.poolMinersCount = pMiners
                    }
                }.resume()
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                self.isRefreshingPool = false
                self.lastPoolUpdate = timeStr
            }

        case .zycord:
            guard let url = URL(string: "https://pool.ariabrain.com/zcd-api/wallet/\(cleanAddr)") else {
                DispatchQueue.main.async { self.isRefreshingPool = false }
                return
            }
            pollAriaPoolStandard(url: url, coinSymbol: "ZCD", divisor: 100_000_000.0, timeStr: timeStr)
        }
    }

    private func pollAriaPoolStandard(url: URL, coinSymbol: String, divisor: Double, timeStr: String) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.isRefreshingPool = false } }

            guard let data = data,
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

            let rawBal = (dict["balance"] as? NSNumber)?.doubleValue ?? 0.0
            let rawImm = (dict["immature"] as? NSNumber)?.doubleValue ?? 0.0
            let rawPaid = (dict["total_paid"] as? NSNumber)?.doubleValue ?? 0.0
            let payments = (dict["payments"] as? NSNumber)?.intValue ?? 0
            let activeWorkers = (dict["active_workers"] as? NSNumber)?.intValue ?? 0
            let shares24h = (dict["shares_24h"] as? NSNumber)?.intValue ?? 0
            let poolHr = (dict["hashrate"] as? NSNumber)?.doubleValue ?? 0.0

            let bal = rawBal / divisor
            let imm = rawImm / divisor
            let paid = rawPaid / divisor
            let progress = min(1.0, max(0.0, bal / 1.0))

            DispatchQueue.main.async {
                self.poolPendingBalance = String(format: "%.6f %@", bal, coinSymbol)
                self.poolImmatureBalance = String(format: "%.6f %@", imm, coinSymbol)
                self.poolTotalPaid = String(format: "%.6f %@", paid, coinSymbol)
                self.poolPaymentsCount = payments
                self.poolActiveWorkers = activeWorkers
                self.poolShares24h = shares24h
                self.poolHashRate = String(format: "%.1f H/s", poolHr)
                self.payoutProgress = progress
                self.lastPoolUpdate = timeStr
            }
        }.resume()
    }
}
