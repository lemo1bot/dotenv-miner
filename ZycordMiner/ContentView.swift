import SwiftUI

final class UIState: ObservableObject {
    @Published var userAddress = ""
    @Published var workerName  = ""
    @Published var addressError = ""
    @Published var miningMode: MiningMode = .pool
    @Published var selectedPreset = PoolPreset.ariabrain
    @Published var customHost     = ""
    @Published var customPort     = "3343"
    @Published var customAlgo     = "rx/2"
    @Published var showFeeSheet   = false
}

// MARK: – Realtime Sparkline Chart View

struct LiveHashChart: View {
    let history: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = max(history.max() ?? 100.0, 10.0)

            ZStack {
                // Background grid lines
                VStack(spacing: 0) {
                    Divider().opacity(0.15)
                    Spacer()
                    Divider().opacity(0.15)
                    Spacer()
                    Divider().opacity(0.15)
                }

                // Area gradient fill
                Path { path in
                    guard history.count > 1 else { return }
                    for (i, val) in history.enumerated() {
                        let x = CGFloat(i) / CGFloat(history.count - 1) * w
                        let y = h - (CGFloat(val) / CGFloat(maxVal) * (h - 8)) - 4
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.35), Color.green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Neon stroke line
                Path { path in
                    guard history.count > 1 else { return }
                    for (i, val) in history.enumerated() {
                        let x = CGFloat(i) / CGFloat(history.count - 1) * w
                        let y = h - (CGFloat(val) / CGFloat(maxVal) * (h - 8)) - 4
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.green.opacity(0.8), radius: 5)
            }
        }
    }
}

// MARK: – Main ContentView

struct ContentView: View {

    @StateObject private var miner = MinerManager()
    @StateObject private var setup = SetupManager()
    @StateObject private var ui    = UIState()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    feeDisclosureBanner
                    setupCard
                    walletCard
                    modeCard
                    if ui.miningMode == .pool   { poolCard }
                    threadsCard
                    if miner.isRunning          { realtimeHashDashboard }
                    logCard
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { setup.checkAndBuild() }
    }

    // MARK: – Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: {
                if let path = Bundle.main.path(forResource: "Logo", ofType: "png"),
                   let img = NSImage(contentsOfFile: path) {
                    return img
                }
                if let img = NSImage(named: "AppIcon") { return img }
                return NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)!
            }())
            .resizable()
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.green.opacity(0.4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(".env")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)
                Text("Zycord (ZCD) Miner · macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(miner.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .shadow(color: miner.isRunning ? .green : .clear, radius: 4)
            Text(miner.isRunning ? "Mining" : "Idle")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(miner.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.green.opacity(miner.isRunning ? 0.5 : 0.2)))
    }

    // MARK: – Fee disclosure

    private var feeDisclosureBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("1 % Developer Fee — Fully Transparent")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                Text("This app mines **1 %** of the time (or 1 % of threads in solo mode) to the developer's address. The remaining **99 %** goes to you. This fee supports the development of .env miner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("View details & dev address") { ui.showFeeSheet = true }
                    .font(.caption)
                    .buttonStyle(.link)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.35)))
        .sheet(isPresented: $ui.showFeeSheet) { feeDetailSheet }
    }

    // MARK: – Fee detail sheet

    private var feeDetailSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "percent")
                    .foregroundStyle(.green)
                Text("Developer Fee Details")
                    .font(.title2.bold())
            }
            Divider()
            infoRow("Fee", "\(MinerManager.devFeePercent) %")
            infoRow("Method (pool)", "Time-based: 36 seconds per hour (1 % of 3,600 s)")
            infoRow("Method (solo)", "Thread-based: 1 % of CPU threads minimum 1")
            infoRow("Dev address", MinerManager.devAddress)
            infoRow("Transparency", "Shown in app UI and log at all times")
            Spacer()
            Button("Close") { ui.showFeeSheet = false }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(24)
        .frame(width: 520)
        .background(Color.black.opacity(0.9))
    }

    // MARK: – Setup card

    private var setupCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: setup.icon)
                    .foregroundStyle(setup.iconColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(setup.title)
                        .font(.subheadline.bold())
                    Text(setup.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if setup.isBuilding { ProgressView().scaleEffect(0.75) }
                else if setup.needsRetry {
                    Button("Retry") { setup.checkAndBuild() }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                }
            }
        } label: {
            Label("Setup", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.bold())
        }
    }

    // MARK: – Wallet card

    private var walletCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your ZCD persistent address (starts with 02…)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("0x027f…  (64 hex chars, starts with 02)", text: $ui.userAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: ui.userAddress) { v in ui.addressError = validateAddress(v) }
                    Button {
                        if let s = NSPasteboard.general.string(forType: .string) {
                            ui.userAddress = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Paste from clipboard")
                }
                if !ui.addressError.isEmpty {
                    Label(ui.addressError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text("Worker name (optional):")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("rig1", text: $ui.workerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .font(.system(.caption, design: .monospaced))
                }
                Text("⚠️ Must be a persistent (0x02) address — one-shot addresses silently lose mining rewards.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } label: {
            Label("Payout Wallet", systemImage: "wallet.pass").font(.subheadline.bold())
        }
    }

    // MARK: – Mode picker

    private var modeCard: some View {
        GroupBox {
            Picker("", selection: $ui.miningMode) {
                ForEach(MiningMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(miner.isRunning)

            Text(ui.miningMode == .pool
                 ? "Pool mining: more consistent earnings, shares effort with other miners."
                 : "Solo mining: if you find a block you keep it all — but harder solo on a new chain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mining Mode", systemImage: "arrow.triangle.branch").font(.subheadline.bold())
        }
    }

    // MARK: – Pool config card

    private var poolCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Pool", selection: $ui.selectedPreset) {
                    ForEach(PoolPreset.allPresets) { p in
                        Text(p.name).tag(p)
                    }
                }
                .disabled(miner.isRunning)

                if ui.selectedPreset.id != "custom" {
                    HStack {
                        poolDetail("Host", ui.selectedPreset.host)
                        Spacer()
                        poolDetail("Port", "\(ui.selectedPreset.port)")
                        Spacer()
                        poolDetail("Algo", ui.selectedPreset.algo)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Text("Pool fee: 1% (AriaPool PPLNS) — separate from the 1% app dev fee. Payments after 240 confirmations (~2 h).")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host").font(.caption2).foregroundStyle(.secondary)
                            TextField("pool.example.com", text: $ui.customHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port").font(.caption2).foregroundStyle(.secondary)
                            TextField("3343", text: $ui.customPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Algorithm").font(.caption2).foregroundStyle(.secondary)
                            TextField("rx/2", text: $ui.customAlgo)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .disabled(miner.isRunning)
                    Text("Use rx/2 for Zycord (RandomX v2). Standard XMRig stratum protocol.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Pool", systemImage: "network").font(.subheadline.bold())
        }
    }

    // MARK: – Threads card (Pool & Solo)

    private var threadsCard: some View {
        let total = miner.totalCores
        let devT  = max(1, Int(Double(total) * 0.01))
        let userT = miner.userThreads

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your threads:")
                    Spacer()
                    Text("\(userT) / \(total) cores").monospacedDigit().bold().foregroundStyle(.green)
                }
                Slider(value: Binding(
                    get: { Double(miner.userThreads) },
                    set: { miner.userThreads = Int($0) }
                ), in: 1 ... Double(max(1, total - devT)), step: 1)
                .disabled(miner.isRunning)
                .tint(.green)

                HStack {
                    Label("Dev fee threads: \(devT) (≈1 %)", systemImage: "percent")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                }

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(0 ..< total, id: \.self) { i in
                            let isDev = i >= (total - devT)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDev ? Color.orange : (i < userT ? Color.green : Color.gray.opacity(0.25)))
                                .frame(height: 14)
                        }
                    }
                }
                .frame(height: 14)

                HStack(spacing: 16) {
                    dot(.green, "Your threads (\(userT))")
                    dot(.orange, "Dev (\(devT), 1 %)")
                }.font(.caption2)
            }
        } label: {
            Label("CPU Threads", systemImage: "cpu.fill").font(.subheadline.bold())
        }
    }

    // MARK: – Realtime Hashrate & Mining Telemetry Dashboard

    private var realtimeHashDashboard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Top Live Banner: Big Hashrate + Status
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT HASHRATE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(miner.hashRate)
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.green)
                                .shadow(color: Color.green.opacity(0.6), radius: 8)
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .shadow(color: .green, radius: 4)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("MINING UPTIME")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(miner.uptimeFormatted)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }

                // Realtime Hashrate Sparkline Chart
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("REALTIME HASH PERFORMANCE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Peak: \(miner.maxHashRate)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    LiveHashChart(history: miner.hashRateHistory)
                        .frame(height: 55)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.green.opacity(0.25)))
                }

                // Speed Breakdown: 10s / 60s / 15m
                HStack(spacing: 8) {
                    speedPill("10s Avg", miner.speed10s + " H/s")
                    speedPill("60s Avg", miner.speed60s + " H/s")
                    speedPill("15m Avg", miner.speed15m + " H/s")
                }

                Divider().opacity(0.2)

                // Live Block / Job Telemetry Grid
                VStack(spacing: 8) {
                    HStack {
                        metricItem("Target Diff", miner.currentDifficulty)
                        Spacer()
                        metricItem("Block Height", miner.blockHeight)
                        Spacer()
                        metricItem("Share Latency", miner.lastShareLatency)
                    }

                    HStack {
                        metricItem("Accepted Shares", "\(miner.sharesOK)", .green)
                        Spacer()
                        metricItem("Rejected", "\(miner.sharesBad)", miner.sharesBad > 0 ? .red : .secondary)
                        Spacer()
                        metricItem("Total Hashes", formatHashes(miner.totalHashes))
                    }
                }

                // Live Job Hash bar
                if miner.currentJobHash != "–" {
                    HStack(spacing: 6) {
                        Text("JOB:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(miner.currentJobHash)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(miner.currentJobHash, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy current job hash")
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(4)
        } label: {
            Label("Realtime Hash Telemetry", systemImage: "waveform.path.ecg")
                .font(.subheadline.bold())
                .foregroundStyle(Color.green)
        }
    }

    private func speedPill(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
    }

    private func metricItem(_ label: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private func formatHashes(_ h: UInt64) -> String {
        if h > 1_000_000_000 {
            return String(format: "%.2f GH", Double(h) / 1_000_000_000.0)
        } else if h > 1_000_000 {
            return String(format: "%.2f MH", Double(h) / 1_000_000.0)
        } else if h > 1_000 {
            return String(format: "%.1f kH", Double(h) / 1_000.0)
        }
        return "\(h) H"
    }

    // MARK: – Log + Start/Stop

    private var logCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(miner.logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(logColor(for: line))
                                    .textSelection(.enabled)
                                    .id(line + "\(miner.logLines.count)")
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.3)))
                    .onChange(of: miner.logLines.count) { _ in
                        if let last = miner.logLines.last {
                            proxy.scrollTo(last + "\(miner.logLines.count)", anchor: .bottom)
                        }
                    }
                }

                HStack {
                    Button {
                        miner.logLines.removeAll()
                    } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if !miner.isRunning {
                        Button { startMining() } label: {
                            Label("Start Mining", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!canStart)
                    } else {
                        Button { miner.stop() } label: {
                            Label("Stop Mining", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
        } label: {
            Label("Log", systemImage: "terminal").font(.subheadline.bold())
        }
    }

    // MARK: – Actions

    private var canStart: Bool {
        setup.isReady && !ui.userAddress.isEmpty && ui.addressError.isEmpty
        && (ui.miningMode == .solo || !currentPoolHost.isEmpty)
    }

    private var currentPoolHost: String {
        ui.selectedPreset.id == "custom" ? ui.customHost : ui.selectedPreset.host
    }

    private func startMining() {
        let dir = nodeDataDir()
        switch ui.miningMode {
        case .pool:
            miner.startPool(
                userAddress: ui.userAddress,
                pool: ui.selectedPreset,
                customHost: ui.customHost,
                customPort: Int(ui.customPort) ?? 3343,
                customAlgo: ui.customAlgo.isEmpty ? "rx/2" : ui.customAlgo,
                workerName: ui.workerName,
                xmrigPath: setup.xmrigPath
            )
        case .solo:
            miner.startSolo(
                userAddress: ui.userAddress,
                zycorddPath: setup.zycorddPath,
                nodeDataDir: dir
            )
        }
    }

    private func nodeDataDir() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("DotEnvMiner/node").path
    }

    // MARK: – Helpers

    private func validateAddress(_ a: String) -> String {
        guard !a.isEmpty else { return "" }
        let s = a.hasPrefix("0x") ? String(a.dropFirst(2)) : a
        if !s.allSatisfy({ $0.isHexDigit }) { return "Must be a hex ZCD address" }
        if s.count < 40 { return "Address looks too short" }
        if !s.hasPrefix("02") { return "Persistent address must start with 02" }
        return ""
    }

    private func logColor(for line: String) -> Color {
        if line.contains("ERROR") || line.contains("rejected") { return .red }
        if line.contains("Dev") || line.contains("dev") || line.contains("1 %") { return .orange }
        if line.contains("accepted") || line.contains("speed") || line.contains("hashrate") { return .green }
        if line.contains("╔") || line.contains("║") || line.contains("╚") { return .green }
        return .green.opacity(0.7)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":").foregroundStyle(.secondary).frame(width: 140, alignment: .trailing)
            Text(value).textSelection(.enabled).font(.system(.body, design: .monospaced))
        }
    }

    private func poolDetail(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced)).bold()
        }
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
