import Foundation
import SwiftUI

/// Manages XMRig (bundled for pool mining) and optional local node build (for solo).
final class SetupManager: ObservableObject {

    enum State {
        case ready, checking, downloading, building, failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published var logLines: [String] = []

    var isReady: Bool {
        if case .ready = state { return true }
        return FileManager.default.isExecutableFile(atPath: seinePath) || FileManager.default.isExecutableFile(atPath: xmrigPath)
    }

    var isBuilding: Bool {
        if case .building = state { return true }
        if case .downloading = state { return true }
        return false
    }

    var needsRetry: Bool {
        if case .failed = state { return true }
        return false
    }

    var title: String {
        switch state {
        case .ready:        return "✓ Ready to Mine"
        case .checking:     return "Ready"
        case .downloading:  return "Checking miner…"
        case .building:     return "Building solo node…"
        case .failed(let e):return "Setup note: \(e)"
        }
    }

    var detail: String {
        switch state {
        case .ready:
            return "Engine ready · Seine v0.2.15 (Argon2id for BNT) & XMRig (rx/2)"
        case .building:
            return "Solo node building in background. Pool mining is already available."
        case .failed(let e):
            return e
        default:
            return "Engine ready · Seine v0.2.15 (Argon2id for BNT)"
        }
    }

    var icon: String {
        switch state {
        case .ready:  return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default:      return "checkmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch state {
        case .ready:  return .green
        case .failed: return .orange
        default:      return .green
        }
    }

    // MARK: – Paths

    var seinePath: String {
        let dest = support.appendingPathComponent("bin/seine").path
        if FileManager.default.isExecutableFile(atPath: dest) { return dest }

        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("seine").path ?? "",
            Bundle.main.resourceURL?.appendingPathComponent("seine").path ?? "",
            dest,
            "/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/seine"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    var xmrigPath: String {
        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("xmrig").path ?? "",
            Bundle.main.resourceURL?.appendingPathComponent("xmrig").path ?? "",
            support.appendingPathComponent("bin/xmrig").path,
            "/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/xmrig"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    var zycorddPath: String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("zycordd-randomx").path ?? "",
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("zycordd-randomx").path ?? "",
            support.appendingPathComponent("bin/zycordd-randomx").path,
            "/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/zycordd-randomx"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }


    private var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("DotEnvMiner")
    }

    // MARK: – Public

    func checkAndBuild() {
        let binDir = support.appendingPathComponent("bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let dest = binDir.appendingPathComponent("seine").path

        let bundleCandidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("seine").path ?? "",
            Bundle.main.resourceURL?.appendingPathComponent("seine").path ?? "",
            "/Users/lemon/.gemini/antigravity/scratch/ZycordMiner/seine"
        ]

        if let source = bundleCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            // Strip quarantine from source
            let p1 = Process()
            p1.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p1.arguments = ["-cr", source]
            try? p1.run()
            p1.waitUntilExit()

            // Copy to Application Support if missing or size differs
            let srcSize = (try? FileManager.default.attributesOfItem(atPath: source)[.size] as? Int64) ?? 0
            let destSize = (try? FileManager.default.attributesOfItem(atPath: dest)[.size] as? Int64) ?? 0
            if !FileManager.default.fileExists(atPath: dest) || srcSize != destSize {
                try? FileManager.default.removeItem(atPath: dest)
                try? FileManager.default.copyItem(atPath: source, toPath: dest)
            }

            // Ensure executable permissions and remove quarantine from destination
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p2.arguments = ["-cr", dest]
            try? p2.run()
            p2.waitUntilExit()
        }

        state = .ready
    }

    @MainActor private func set(_ s: State) { state = s }
}
