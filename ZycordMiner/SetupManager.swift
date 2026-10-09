import Foundation
import SwiftUI

/// Downloads XMRig (for pool) and builds zycordd-randomx (for solo) on first run.
final class SetupManager: ObservableObject {

    enum State {
        case idle, checking, downloading, building, ready, failed(String)
    }

    @Published private(set) var state: State = .idle

    var isReady:    Bool { if case .ready    = state { return true }; return false }
    var isBuilding: Bool {
        if case .building = state { return true }
        if case .downloading = state { return true }
        return false
    }
    var needsRetry: Bool { if case .failed   = state { return true }; return false }

    var title: String {
        switch state {
        case .idle:          return "Not checked"
        case .checking:      return "Checking tools…"
        case .downloading:   return "Downloading XMRig…"
        case .building:      return "Building zycordd-randomx from source…"
        case .ready:         return "✓ Ready"
        case .failed(let e): return "Failed: \(e)"
        }
    }

    var detail: String {
        switch state {
        case .building:     return "Building from source — needs Xcode CLI tools + Go \(requiredGo). ~5 min."
        case .downloading:  return "Downloading XMRig binary for macOS…"
        case .ready:        return "XMRig: \(xmrigPath)\nNode: \(zycorddPath)"
        case .failed:       return "Ensure Xcode CLI tools and Go \(requiredGo) are installed, then retry."
        default:            return ""
        }
    }

    var icon: String {
        switch state {
        case .ready:   return "checkmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        default:       return "gearshape.2.fill"
        }
    }

    var iconColor: Color {
        switch state {
        case .ready:  return .green
        case .failed: return .red
        default:      return .orange
        }
    }

    // MARK: – Paths

    private let requiredGo = "go1.26.2"

    // XMRig macOS binary — download from GitHub releases
    // XMRig 6.26+ supports rx/2 natively (no fork/patch needed)
    private let xmrigVersion = "6.22.2"  // latest stable with rx/2 support

    var xmrigPath: String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("xmrig").path ?? "",
            support.appendingPathComponent("bin/xmrig").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    var zycorddPath: String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("zycordd-randomx").path ?? "",
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
        state = .checking
        Task {
            let hasXMRig    = FileManager.default.isExecutableFile(atPath: xmrigPath)
            let hasZycordd  = FileManager.default.isExecutableFile(atPath: zycorddPath)
            if hasXMRig && hasZycordd {
                await set(.ready); return
            }
            if !hasXMRig    { await downloadXMRig() }
            if !hasZycordd  { await buildZycordd() }
            await set(.ready)
        }
    }

    // MARK: – Download XMRig

    private func downloadXMRig() async {
        await set(.downloading)
        let binDir = support.appendingPathComponent("bin")
        let tmpDir = support.appendingPathComponent("tmp")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Determine arch
        let arch = ProcessInfo.processInfo.machineHardwareName.contains("arm") ? "macos-arm64" : "macos-x64"
        let tarName = "xmrig-\(xmrigVersion)-\(arch).tar.gz"
        let urlStr  = "https://github.com/xmrig/xmrig/releases/download/v\(xmrigVersion)/\(tarName)"
        let tarPath = tmpDir.appendingPathComponent(tarName).path
        let dest    = binDir.appendingPathComponent("xmrig").path

        do {
            // Download
            try await shell("curl -fSL -o \(tarPath) \(urlStr)")
            // Extract xmrig binary
            try await shell("tar -xzf \(tarPath) -C \(tmpDir.path) --strip-components=1 xmrig-\(xmrigVersion)/xmrig")
            let extracted = tmpDir.appendingPathComponent("xmrig").path
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.moveItem(atPath: extracted, toPath: dest)
            try await shell("chmod +x \(dest)")
            // Cleanup
            try? FileManager.default.removeItem(atPath: tarPath)
        } catch {
            // XMRig download failed — log it but don't abort (solo still works)
            await MainActor.run {
                self.logLines.append("⚠ XMRig download failed: \(error.localizedDescription)")
                self.logLines.append("  Pool mining unavailable. Solo mining still works.")
            }
        }
    }

    @Published var logLines: [String] = []

    // MARK: – Build zycordd-randomx

    private func buildZycordd() async {
        await set(.building)
        let srcDir = support.appendingPathComponent("src/zycord-node")
        let binDir = support.appendingPathComponent("bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        do {
            if !FileManager.default.fileExists(atPath: srcDir.path) {
                try await shell("git clone --depth 1 https://gitlab.com/zycord-group/zycord-node.git \(srcDir.path)")
            } else {
                try await shell("git -C \(srcDir.path) pull --ff-only")
            }
            try await shell("make -C \(srcDir.path) build-randomx")

            let built = srcDir.appendingPathComponent("bin/zycordd-randomx").path
            let dest  = binDir.appendingPathComponent("zycordd-randomx").path
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: built, toPath: dest)
            try await shell("chmod +x \(dest)")
        } catch {
            await set(.failed(error.localizedDescription))
        }
    }

    // MARK: – Shell helper

    @discardableResult
    private func shell(_ cmd: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", cmd]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/local/go/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = pipe
            p.terminationHandler = { proc in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    cont.resume(throwing: NSError(domain: "ZCD", code: Int(proc.terminationStatus),
                                                  userInfo: [NSLocalizedDescriptionKey: out.suffix(500).description]))
                }
            }
            do    { try p.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    @MainActor private func set(_ s: State) { state = s }
}

// MARK: – Machine hardware name

extension ProcessInfo {
    var machineHardwareName: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { buf in
            String(bytes: buf.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        }
    }
}
