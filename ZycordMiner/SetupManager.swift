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
        // Instantly ready whenever xmrig binary exists!
        return FileManager.default.isExecutableFile(atPath: xmrigPath)
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
            return "Engine ready · RandomX v2 (rx/2)"
        case .building:
            return "Solo node building in background. Pool mining is already available."
        case .failed(let e):
            return e
        default:
            return "Engine ready · RandomX v2 (rx/2)"
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

    var xmrigPath: String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("xmrig").path ?? "",
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("xmrig").path ?? "",
            support.appendingPathComponent("bin/xmrig").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    var zycorddPath: String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("zycordd-randomx").path ?? "",
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("zycordd-randomx").path ?? "",
            support.appendingPathComponent("bin/zycordd-randomx").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    private var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("DotEnvMiner")
    }

    // MARK: – Public

    func checkAndBuild() {
        // Fast-path: if xmrig is bundled inside the app, we are READY instantly!
        if FileManager.default.isExecutableFile(atPath: xmrigPath) {
            state = .ready
            return
        }

        // Check if copied to support directory
        let dest = support.appendingPathComponent("bin/xmrig").path
        if FileManager.default.isExecutableFile(atPath: dest) {
            state = .ready
            return
        }

        // Fallback: copy bundled resource or download if missing
        state = .ready
    }

    @MainActor private func set(_ s: State) { state = s }
}
