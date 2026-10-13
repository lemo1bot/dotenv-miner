import SwiftUI

// MARK: – UI State

final class UIState: ObservableObject {
    @Published var selectedCoin: SupportedCoin = .zycord {
        didSet {
            UserDefaults.standard.set(selectedCoin.rawValue, forKey: "saved_selected_coin")
            loadAddressForCoin()
            updatePresetForCoin()
        }
    }

    @Published var userAddress: String = "" {
        didSet {
            UserDefaults.standard.set(userAddress, forKey: "saved_addr_\(selectedCoin.rawValue)")
        }
    }

    @Published var workerName: String {
        didSet { UserDefaults.standard.set(workerName, forKey: "saved_worker_name") }
    }

    @Published var addressError = ""
    @Published var miningMode: MiningMode = .pool
    @Published var selectedPreset: PoolPreset = PoolPreset.ariabrain
    @Published var customHost: String = ""
    @Published var customPort: String = "3343"
    @Published var customAlgo: String = "rx/2"
    @Published var showFeeSheet: Bool = false

    // Wallet Generation State
    @Published var showWalletGenSheet: Bool = false
    @Published var generatedWallet: GeneratedWallet? = nil
    @Published var showPrivateKey: Bool = false

    init() {
        if let savedCoin = UserDefaults.standard.string(forKey: "saved_selected_coin"),
           let coin = SupportedCoin(rawValue: savedCoin) {
            self.selectedCoin = coin
        } else {
            self.selectedCoin = .zycord
        }
        self.workerName = UserDefaults.standard.string(forKey: "saved_worker_name") ?? "mac"
        loadAddressForCoin()
        updatePresetForCoin()
    }

    func loadAddressForCoin() {
        let key = "saved_addr_\(selectedCoin.rawValue)"
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        self.userAddress = saved
        self.addressError = ""
    }

    func updatePresetForCoin() {
        let presets = PoolPreset.presets(for: selectedCoin)
        self.selectedPreset = presets.first ?? PoolPreset.ariabrain
        self.customHost = ""
        self.customPort = "\(selectedCoin.defaultPort)"
        self.customAlgo = selectedCoin.defaultAlgo
    }
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
                    coinSelectorBar
                    feeDisclosureBanner
                    setupCard
                    walletCard
                    if ui.miningMode == .pool { earningsCard }
                    modeCard
                    if ui.miningMode == .pool { poolCard }
                    threadsCard
                    if miner.isRunning        { realtimeHashDashboard }
                    logCard
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 580, idealWidth: 860, maxWidth: .infinity,
               minHeight: 480, idealHeight: 780, maxHeight: .infinity)
        .background(WindowAccessor())
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setup.checkAndBuild()
            if !ui.userAddress.isEmpty && ui.addressError.isEmpty {
                miner.fetchPoolStats(coin: ui.selectedCoin, address: ui.userAddress)
            }
        }

        .sheet(isPresented: $ui.showWalletGenSheet) {
            walletGenerationSheet
        }
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
                HStack(spacing: 6) {
                    Text(".env")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                    Text("One Click Miner")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text("\(ui.selectedCoin.name) (\(ui.selectedCoin.symbol)) · macOS Apple Silicon")
                    .font(.caption2)
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
            Text(miner.isRunning ? "Mining \(miner.activeCoin.symbol)" : "Idle")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(miner.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.green.opacity(miner.isRunning ? 0.5 : 0.2)))
    }

    // MARK: – Coin Selector Bar

    private var coinSelectorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SELECT MINING COIN / TOKEN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Active: \(ui.selectedCoin.name) (\(ui.selectedCoin.symbol))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)
            }

            ScrollViewReader { scrollProxy in
                HStack(spacing: 6) {
                    // Left Scroll Option
                    Button {
                        withAnimation(.easeInOut) {
                            if let prev = previousCoin(before: ui.selectedCoin) {
                                scrollProxy.scrollTo(prev.id, anchor: .center)
                                if !miner.isRunning { ui.selectedCoin = prev }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.green)
                            .frame(width: 26, height: 46)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll to previous token")

                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(SupportedCoin.allCases) { coin in
                                let isSelected = ui.selectedCoin == coin
                                Button {
                                    guard !miner.isRunning else { return }
                                    ui.selectedCoin = coin
                                    withAnimation(.easeInOut) {
                                        scrollProxy.scrollTo(coin.id, anchor: .center)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(coinIcon(for: coin))
                                            .font(.system(size: 16))
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 4) {
                                                Text(coin.name)
                                                    .font(.system(size: 12, weight: .bold))
                                                Text("(\(coin.symbol))")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(isSelected ? Color.green : .secondary)
                                            }
                                            Text(coin.tag)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(isSelected ? Color.green.opacity(0.9) : .secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        isSelected ? Color.green.opacity(0.15) : Color.white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSelected ? Color.green : Color.white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(miner.isRunning)
                                .id(coin.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Right Scroll Option
                    Button {
                        withAnimation(.easeInOut) {
                            if let next = nextCoin(after: ui.selectedCoin) {
                                scrollProxy.scrollTo(next.id, anchor: .center)
                                if !miner.isRunning { ui.selectedCoin = next }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.green)
                            .frame(width: 26, height: 46)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll to next token")
                }
                .onChange(of: ui.selectedCoin) { newCoin in
                    withAnimation(.easeInOut) {
                        scrollProxy.scrollTo(newCoin.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func previousCoin(before current: SupportedCoin) -> SupportedCoin? {
        let all = SupportedCoin.allCases
        guard let idx = all.firstIndex(of: current) else { return all.first }
        if idx > 0 { return all[idx - 1] }
        return all.last
    }

    private func nextCoin(after current: SupportedCoin) -> SupportedCoin? {
        let all = SupportedCoin.allCases
        guard let idx = all.firstIndex(of: current) else { return all.first }
        if idx + 1 < all.count { return all[idx + 1] }
        return all.first
    }


    private func coinIcon(for coin: SupportedCoin) -> String {
        switch coin {
        case .zycord:        return "⚡"
        case .connectcoin:   return "🔗"
        case .commonfoundry: return "⚙️"
        case .truenorth:     return "🧭"
        case .pulsemining:   return "🏦"
        case .blocknet:      return "📦"
        case .parano1d:      return "👁️"
        }
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
                Text("This app mines **1 %** of the time to the developer's address. The remaining **99 %** goes to you. This fee supports the continuous development of .env multi-coin miner.")
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
            infoRow("Active Coin", "\(ui.selectedCoin.name) (\(ui.selectedCoin.symbol))")
            infoRow("Method", "Time-based: 36 seconds per hour (1 % of 3,600 s)")
            infoRow("Dev address", ui.selectedCoin.devPayoutAddress)
            infoRow("Transparency", "Shown in app UI and log at all times. Bypassed if you are the dev.")
            Spacer()
            Button("Close") { ui.showFeeSheet = false }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(24)
        .frame(width: 540)
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
            Label("Engine Setup", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.bold())
        }
    }

    // MARK: – Wallet card with One-Click Generation

    private var walletCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header with Coin Title & 1-Click Generation Button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ui.selectedCoin.name) (\(ui.selectedCoin.symbol)) Payout Address")
                            .font(.subheadline.bold())
                        Text(walletPlaceholderTip(for: ui.selectedCoin))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        ui.generatedWallet = WalletGenerator.shared.generateWallet(for: ui.selectedCoin)
                        ui.showWalletGenSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text("1-Click Generate Wallet")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }

                HStack {
                    TextField(walletPlaceholder(for: ui.selectedCoin), text: $ui.userAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: ui.userAddress) { v in
                            ui.addressError = validateAddress(v, for: ui.selectedCoin)
                            if ui.addressError.isEmpty && !v.isEmpty {
                                miner.fetchPoolStats(coin: ui.selectedCoin, address: v)
                            }
                        }
                    Button {
                        if let s = NSPasteboard.general.string(forType: .string) {
                            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            ui.userAddress = trimmed
                            ui.addressError = validateAddress(trimmed, for: ui.selectedCoin)
                            if ui.addressError.isEmpty && !trimmed.isEmpty {
                                miner.fetchPoolStats(coin: ui.selectedCoin, address: trimmed)
                            }
                        }
                    } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Paste from clipboard")
                }

                if !ui.addressError.isEmpty {
                    Label(ui.addressError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                // Zycord-specific Persistent vs Temporary guidance
                if ui.selectedCoin == .zycord {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zycord Address Types: **Fix (02…)** vs **Temporary (01…)**")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                            Text("• **Fix (starts with 02)**: Your permanent mining wallet. Mining payouts must be sent to this address.\n• **Temporary (starts with 01)**: One-shot stealth address for receiving single private payments. Do not use for mining pools.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Text("Worker name:")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("mac", text: $ui.workerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .font(.system(.caption, design: .monospaced))

                    Spacer()

                    Link(destination: URL(string: ui.selectedCoin.officialUrl)!) {
                        HStack(spacing: 3) {
                            Text("Official Website")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption2)
                        .foregroundStyle(.green)
                    }
                }
            }
        } label: {
            Label("\(ui.selectedCoin.name) Wallet", systemImage: "wallet.pass")
                .font(.subheadline.bold())
        }
    }

    // MARK: – 1-Click Wallet Generation Sheet

    private var walletGenerationSheet: some View {
        guard let wallet = ui.generatedWallet else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text(coinIcon(for: wallet.coin))
                        .font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(wallet.coin.name) (\(wallet.coin.symbol)) Wallet Generated")
                            .font(.title3.bold())
                        Text("100% Client-Side · Cryptographically Secure CSPRNG")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close") { ui.showWalletGenSheet = false }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Divider()

                // Security Notice Banner (MANDATORY non-custodial disclosure)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("🔒 Non-Custodial & 100% Private (No Cloud Storage)")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                        Text("We **DO NOT store, save, or transmit** your private key or recovery phrase to any server. These keys are generated locally in memory. **Please write down your 12-word recovery phrase and private key on paper.** If lost, funds cannot be recovered.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.35)))

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Primary Address (or Fix address for Zycord)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(wallet.coin == .zycord ? "FIX / PERMANENT MINING ADDRESS (02…)" : "PUBLIC MINING ADDRESS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.green)
                                Spacer()
                                copyButton(text: wallet.publicAddress, label: "Copy")
                            }
                            Text(wallet.publicAddress)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.green.opacity(0.3)))
                                .textSelection(.enabled)
                            Text(wallet.addressTypeDescription)
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        // 2. Zycord Temporary Address (if Zycord)
                        if wallet.coin == .zycord, let temp = wallet.secondaryAddress {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("TEMPORARY / STEALTH RECEIVE ADDRESS (01…)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.orange)
                                    Spacer()
                                    copyButton(text: temp, label: "Copy")
                                }
                                Text(temp)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange.opacity(0.3)))
                                    .textSelection(.enabled)
                                Text("⚠️ One-shot address for private transfers only. Do not use for mining pools.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        Divider().opacity(0.3)

                        // 3. 12-Word Recovery Phrase
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("12-WORD BIP-39 RECOVERY PHRASE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                copyButton(text: wallet.mnemonicPhrase, label: "Copy Phrase")
                            }

                            let words = wallet.mnemonicPhrase.components(separatedBy: " ")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                                    HStack(spacing: 4) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(word)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }

                        Divider().opacity(0.3)

                        // 4. Private Key (Hex)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("PRIVATE KEY (32-BYTE HEX)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(ui.showPrivateKey ? "Hide" : "Reveal") {
                                    ui.showPrivateKey.toggle()
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                copyButton(text: wallet.privateKeyHex, label: "Copy Key")
                            }

                            Text(ui.showPrivateKey ? wallet.privateKeyHex : "••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••")
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15)))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Action Bar
                HStack {
                    Button {
                        ui.userAddress = wallet.publicAddress
                        ui.showWalletGenSheet = false
                    } label: {
                        Label("Use Address for Mining & Close", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Spacer()

                    Button("Done") { ui.showWalletGenSheet = false }
                        .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .frame(width: 580, height: 600)
            .background(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func copyButton(text: String, label: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    // MARK: – Earnings & Pool Balances Card (AriaPool ZCD)

    private var earningsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Header with live indicator & refresh button
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green, radius: 4)
                        Text("\(ui.selectedCoin.name) Pool Telemetry (\(ui.selectedCoin.symbol))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }

                    Spacer()

                    if !miner.lastPoolUpdate.isEmpty && miner.lastPoolUpdate != "–" {
                        Text("Updated \(miner.lastPoolUpdate)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        miner.fetchPoolStats(coin: ui.selectedCoin, address: ui.userAddress)
                    } label: {
                        HStack(spacing: 4) {
                            if miner.isRefreshingPool {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text("Refresh")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(miner.isRefreshingPool || ui.userAddress.isEmpty)
                }

                // Balance summary tiles: 3 columns
                HStack(spacing: 10) {
                    balanceTile(
                        title: "PENDING BALANCE",
                        amount: miner.poolPendingBalance,
                        caption: "Ready for next payout",
                        icon: "creditcard.fill",
                        tint: .green
                    )

                    balanceTile(
                        title: "IMMATURE BALANCE",
                        amount: miner.poolImmatureBalance,
                        caption: "Locked confirmations",
                        icon: "lock.circle.fill",
                        tint: .orange
                    )

                    balanceTile(
                        title: "TOTAL PAID OUT",
                        amount: miner.poolTotalPaid,
                        caption: "\(miner.poolPaymentsCount) payout(s) done",
                        icon: "checkmark.seal.fill",
                        tint: .cyan
                    )
                }

                Divider().opacity(0.2)

                // Payout Progress Bar (Min payout 1.00 token)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("PAYOUT PROGRESS (MIN 1.00 \(ui.selectedCoin.symbol))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f %%", miner.payoutProgress * 100.0))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.8), Color.green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geo.size.width * CGFloat(miner.payoutProgress), geo.size.width)), height: 8)
                                .shadow(color: Color.green.opacity(0.6), radius: 3)
                        }
                    }
                    .frame(height: 8)
                }

                // Worker & Pool stats row
                HStack {
                    metricItem("Pool Workers", "\(miner.poolActiveWorkers) active", miner.poolActiveWorkers > 0 ? .green : .secondary)
                    Spacer()
                    metricItem("24h Shares", "\(miner.poolShares24h)", .primary)
                    Spacer()
                    metricItem("Pool Hashrate", miner.poolHashRate, .green)
                    Spacer()
                    Button {
                        var clean = ui.userAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                        if clean.hasPrefix("0x") || clean.hasPrefix("0X") { clean = String(clean.dropFirst(2)) }
                        let urlStr: String = {
                            switch ui.selectedCoin {
                            case .zycord:        return clean.isEmpty ? "https://pool.ariabrain.com/zcd.html" : "https://pool.ariabrain.com/zcd.html#\(clean)"
                            case .connectcoin:   return clean.isEmpty ? "https://pool.ariabrain.com/conn.html" : "https://pool.ariabrain.com/conn.html#\(clean)"
                            case .truenorth:     return clean.isEmpty ? "https://pool.ariabrain.com/north.html" : "https://pool.ariabrain.com/north.html#\(clean)"
                            case .pulsemining:   return clean.isEmpty ? "https://pool.ariabrain.com/pbc.html" : "https://pool.ariabrain.com/pbc.html#\(clean)"
                            case .blocknet:      return clean.isEmpty ? "https://bntpool.com" : "https://bntpool.com/#/miner/\(clean)"
                            case .commonfoundry: return "https://commonfoundry.ai"
                            case .parano1d:      return "https://parano1d.org"
                            }
                        }()
                        if let u = URL(string: urlStr) {
                            NSWorkspace.shared.open(u)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("Open Pool Web")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.green)
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(4)
        } label: {
            Label("\(ui.selectedCoin.name) Earnings Telemetry", systemImage: "banknote.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Color.green)
        }
    }

    private func balanceTile(title: String, amount: String, caption: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(amount)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.25)))
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
                 ? "Pool mining: shared hashrate for steady payouts."
                 : "Solo mining: block rewards paid directly to your wallet.")
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
                    ForEach(PoolPreset.presets(for: ui.selectedCoin)) { p in
                        Text(p.name).tag(p)
                    }
                }
                .disabled(miner.isRunning)

                if !ui.selectedPreset.id.hasPrefix("custom") {
                    HStack {
                        poolDetail("Host", ui.selectedPreset.host)
                        Spacer()
                        poolDetail("Port", "\(ui.selectedPreset.port)")
                        Spacer()
                        poolDetail("Algo", ui.selectedPreset.algo)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Text("Connected to \(ui.selectedCoin.name) stratum. 1% app developer fee disclosed.")
                        .font(.caption2).foregroundStyle(.secondary)

                    if ui.selectedCoin == .commonfoundry {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Common Foundry (CMFD) GPU FORGEMATRIX Notice")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                Text("CMFD utilizes AI forward-pass inference proof-of-work (aria-energy-cmfd) with TLS certificate pinning requiring 8 GB+ VRAM. For Mac CPU mining, Zycord (ZCD), TrueNorth (TNC), PBC, Blocknet (BNT) and Parano1d (NOID) are recommended.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host").font(.caption2).foregroundStyle(.secondary)
                            TextField(ui.selectedCoin.defaultHost, text: $ui.customHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port").font(.caption2).foregroundStyle(.secondary)
                            TextField("\(ui.selectedCoin.defaultPort)", text: $ui.customPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Algorithm").font(.caption2).foregroundStyle(.secondary)
                            TextField(ui.selectedCoin.defaultAlgo, text: $ui.customAlgo)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .disabled(miner.isRunning)
                    Text("Standard XMRig stratum protocol. Algorithm: \(ui.selectedCoin.defaultAlgo)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("\(ui.selectedCoin.name) Pool Settings", systemImage: "network").font(.subheadline.bold())
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
            Label("CPU Threads Allocation", systemImage: "cpu.fill").font(.subheadline.bold())
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

                // Real-Time Token Earnings Estimates
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ESTIMATED REALTIME TOKEN EARNINGS (\(ui.selectedCoin.symbol))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Live calc · diff & block reward")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        earningTile(
                            period: "1 HOUR",
                            amount: String(format: "%.4f %@", miner.estimatedEarningsPerHour(coin: ui.selectedCoin), ui.selectedCoin.symbol),
                            tint: .green
                        )
                        earningTile(
                            period: "24 HOURS (DAILY)",
                            amount: String(format: "%.3f %@", miner.estimatedEarningsPerDay(coin: ui.selectedCoin), ui.selectedCoin.symbol),
                            tint: .green
                        )
                        earningTile(
                            period: "30 DAYS (MONTHLY)",
                            amount: String(format: "%.1f %@", miner.estimatedEarningsPerMonth(coin: ui.selectedCoin), ui.selectedCoin.symbol),
                            tint: .cyan
                        )
                    }
                }

                Divider().opacity(0.2)

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
            Label("Realtime Mining Telemetry & Earnings", systemImage: "waveform.path.ecg")
                .font(.subheadline.bold())
                .foregroundStyle(Color.green)
        }
    }

    private func earningTile(period: String, amount: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(period)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.2)))
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
                    .frame(minHeight: 180, idealHeight: 240, maxHeight: 450)

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
                            Label("Start Mining \(ui.selectedCoin.symbol)", systemImage: "play.fill")
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
        ui.selectedPreset.id.hasPrefix("custom") ? ui.customHost : ui.selectedPreset.host
    }

    private func startMining() {
        let dir = nodeDataDir()
        switch ui.miningMode {
        case .pool:
            miner.startPool(
                coin: ui.selectedCoin,
                userAddress: ui.userAddress,
                pool: ui.selectedPreset,
                customHost: ui.customHost,
                customPort: Int(ui.customPort) ?? ui.selectedCoin.defaultPort,
                customAlgo: ui.customAlgo.isEmpty ? ui.selectedCoin.defaultAlgo : ui.customAlgo,
                workerName: ui.workerName,
                xmrigPath: setup.xmrigPath,
                pbcminerPath: setup.pbcminerPath,
                seinePath: setup.seinePath,
                parano1dPath: setup.parano1dPath
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

    // MARK: – Helpers & Validation

    private func validateAddress(_ a: String, for coin: SupportedCoin) -> String {
        guard !a.isEmpty else { return "" }
        let s = a.trimmingCharacters(in: .whitespacesAndNewlines)
        switch coin {
        case .zycord:
            let clean = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
            if !clean.allSatisfy({ $0.isHexDigit }) { return "Must be a hex ZCD address" }
            if clean.count < 40 { return "Address looks too short" }
            if !clean.hasPrefix("02") { return "Mining address must start with 02 (persistent address)" }
            return ""
        case .connectcoin:
            if !s.lowercased().hasPrefix("cc1") && !s.hasPrefix("c") {
                return "ConnectCoin address should start with cc1… (Bech32m) or c…"
            }
            if s.count < 15 { return "Address looks too short" }
            return ""
        case .commonfoundry:
            let clean = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
            if !clean.allSatisfy({ $0.isHexDigit }) { return "Must be a 64-hex CMFD address" }
            if clean.count < 30 { return "Address looks too short" }
            return ""
        case .truenorth:
            if !s.lowercased().hasPrefix("north1") && !s.hasPrefix("T") && !s.hasPrefix("1") {
                return "TrueNorth address should start with north1z… (Bech32m)"
            }
            if s.count < 15 { return "Address looks too short" }
            return ""
        case .pulsemining:
            if !s.hasPrefix("Pb") && !s.hasPrefix("4") && !s.hasPrefix("8") {
                return "PBC address must start with Pbc… (or Pb…)"
            }
            if s.count < 60 { return "PBC address looks too short (expected ~97 chars)" }
            return ""
        case .blocknet:
            let b58Set = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            if s.rangeOfCharacter(from: b58Set.inverted) != nil {
                return "Blocknet address must be valid Base58"
            }
            if s.count < 80 || s.count > 105 {
                return "Blocknet address should be ~93 characters (68-byte stealth address)"
            }
            return ""
        case .parano1d:
            if !s.lowercased().hasPrefix("o1") {
                return "Parano1d address must start with o1…"
            }
            if s.count < 50 || s.count > 70 {
                return "Parano1d address should be 60 characters (Bech32m)"
            }
            return ""
        }
    }

    private func walletPlaceholder(for coin: SupportedCoin) -> String {
        switch coin {
        case .zycord:        return "027f… (64 hex characters, starts with 02)"
        case .connectcoin:   return "cc1p… (ConnectCoin Bech32m address)"
        case .commonfoundry: return "028a… (64 hex characters)"
        case .truenorth:     return "north1z… (TrueNorth Bech32m address, 65 chars)"
        case .pulsemining:   return "Pbc… (97-character CryptoNote Base58 address)"
        case .blocknet:      return "7pew… or SEiNE… (68-byte Base58 stealth address, ~93 chars)"
        case .parano1d:      return "o1kw… (60-character Bech32m address starting with o1)"
        }
    }

    private func walletPlaceholderTip(for coin: SupportedCoin) -> String {
        switch coin {
        case .zycord:        return "Persistent Fix Address starts with 02 (required for mining rewards)"
        case .connectcoin:   return "Pay-to-Connect Bech32m witness-v1 mainnet address"
        case .commonfoundry: return "Mainnet 64-hexadecimal inference mining address"
        case .truenorth:     return "Native SegWit P2QRH Bech32m address (starts with north1z…)"
        case .pulsemining:   return "CryptoNote private banking address (starts with Pbc…)"
        case .blocknet:      return "Blocknet Ristretto255 stealth address (~93 chars Base58)"
        case .parano1d:      return "Proof-native Bech32m address (60 chars, starts with o1…)"
        }
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

// MARK: – Window Resizability & Fullscreen Enabler

final class WindowHelperView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        window.styleMask.insert([.resizable, .miniaturizable, .closable, .titled])
        window.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.minSize = NSSize(width: 520, height: 400)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.showsResizeIndicator = true
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return WindowHelperView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.styleMask.insert([.resizable, .miniaturizable, .closable, .titled])
            window.showsResizeIndicator = true
        }
    }
}


