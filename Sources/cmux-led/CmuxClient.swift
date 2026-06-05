import AppKit
import Foundation

struct Surface: Equatable {
    let ref: String
    let title: String
    let selected: Bool
}

enum CmuxClient {
    static let binary = "/Applications/cmux.app/Contents/Resources/bin/cmux"

    static func runText(_ args: [String], timeout: TimeInterval = 2.0) -> (out: String, err: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ("", "spawn failed", -1) }

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = group.wait(timeout: .now() + 0.3)
            if p.isRunning {
                kill(p.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 0.3)
            }
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
            return ("", "timeout", -1)
        }
        p.waitUntilExit()
        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            p.terminationStatus
        )
    }

    static func ping() -> Bool {
        runText(["ping"], timeout: 1.0).out.uppercased().contains("PONG")
    }

    static func currentWorkspaceRef() -> String? {
        let r = runText(["current-workspace"], timeout: 1.0)
        guard r.code == 0 else { return nil }
        let trimmed = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let first = trimmed.split(separator: "\n").first {
            return String(first).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    static func listSurfaces(workspaceRef: String) -> [Surface] {
        let r = runText(["list-pane-surfaces", "--workspace", workspaceRef], timeout: 1.5)
        guard r.code == 0 else { return [] }
        return parseRefLines(r.out, prefix: "surface:")
    }

    static func listWorkspaces() -> [Surface] {
        let r = runText(["workspace", "list"], timeout: 1.5)
        guard r.code == 0 else { return [] }
        return parseRefLines(r.out, prefix: "workspace:")
    }

    /// A title is "busy" when it starts with a braille spinner glyph (U+2800–U+28FF).
    /// The `✳` (U+2733) prefix is a sticky task label left after a run, not a live spinner.
    static func isSpinnerBusy(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else { return false }
        return (0x2800...0x28FF).contains(first.value)
    }

    /// Refs of workspaces that have at least one busy surface.
    ///
    /// Named workspaces keep their user-given name as the workspace title (no
    /// spinner glyph), so a workspace's busy state can't be read from its own
    /// title — it must come from the surfaces nested under it in `tree --all`.
    static func busyWorkspaceRefs() -> Set<String> {
        let r = runText(["tree", "--all"], timeout: 1.5)
        guard r.code == 0 else { return [] }
        return parseBusyWorkspaceRefs(r.out)
    }

    static func parseBusyWorkspaceRefs(_ tree: String) -> Set<String> {
        let drawing: Set<Character> = ["│", "├", "└", "─", " ", "\t"]
        var busy: Set<String> = []
        var current: String?
        for raw in tree.split(separator: "\n", omittingEmptySubsequences: true) {
            let node = String(String(raw).drop(while: { drawing.contains($0) }))
            if node.hasPrefix("workspace ") {
                let toks = node.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                current = toks.count >= 2 ? String(toks[1]) : nil
                if let ws = current, let title = quotedTitle(node), isSpinnerBusy(title) {
                    busy.insert(ws)
                }
            } else if node.hasPrefix("surface "), let ws = current,
                      let title = quotedTitle(node), isSpinnerBusy(title) {
                busy.insert(ws)
            }
        }
        return busy
    }

    private static func quotedTitle(_ s: String) -> String? {
        guard let f = s.firstIndex(of: "\""), let l = s.lastIndex(of: "\""), f < l else { return nil }
        return String(s[s.index(after: f)..<l])
    }

    static func selectWorkspace(ref: String) {
        DispatchQueue.global().async {
            _ = runText(["select-workspace", "--workspace", ref], timeout: 1.0)
            DispatchQueue.main.async {
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.cmuxterm.app")
                    .first?
                    .activate(options: [.activateAllWindows])
            }
        }
    }

    static func parseRefLines(_ text: String, prefix: String) -> [Surface] {
        var out: [Surface] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            let selected = line.hasPrefix("*")
            var rest = line
            if line.count >= 2 {
                rest = String(line.dropFirst(2))
            }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            guard let spaceIdx = trimmed.firstIndex(of: " ") else {
                if trimmed.hasPrefix(prefix) {
                    out.append(Surface(ref: trimmed, title: "", selected: selected))
                }
                continue
            }
            let ref = String(trimmed[..<spaceIdx])
            guard ref.hasPrefix(prefix) else { continue }
            var title = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            if title.hasSuffix("[selected]") {
                title = String(title.dropLast("[selected]".count)).trimmingCharacters(in: .whitespaces)
            }
            out.append(Surface(ref: ref, title: title, selected: selected))
        }
        return out
    }

    static func readScreen(workspaceRef: String, surfaceRef: String, lines: Int = 12) -> String {
        let r = runText(["read-screen", "--workspace", workspaceRef, "--surface", surfaceRef, "--lines", "\(lines)"], timeout: 1.0)
        return r.out
    }

    static func focusSurface(workspaceRef: String, surfaceRef: String) {
        DispatchQueue.global().async {
            _ = runText(["focus-panel", "--panel", surfaceRef, "--workspace", workspaceRef], timeout: 1.0)
            DispatchQueue.main.async {
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.cmuxterm.app")
                    .first?
                    .activate(options: [.activateAllWindows])
            }
        }
    }

    static func streamEvents(onLine: @escaping (String) -> Void) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["events", "--reconnect", "--category", "workspace", "--category", "surface", "--category", "pane", "--category", "window"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        let maxBuffer = 1 << 20
        handle.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            if buffer.count > maxBuffer {
                buffer.removeAll(keepingCapacity: false)
                return
            }
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                if let s = String(data: line, encoding: .utf8), !s.isEmpty {
                    onLine(s)
                }
            }
        }
        do { try p.run() } catch {
            FileHandle.standardError.write(Data("cmux-led: events stream spawn failed: \(error)\n".utf8))
            return p
        }
        return p
    }
}
