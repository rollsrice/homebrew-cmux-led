import Foundation
import Combine

struct PanelState: Identifiable, Equatable {
    let id: String
    let index: Int
    let title: String
    let isBusy: Bool
    let isFocused: Bool
}

final class CmuxMonitor: ObservableObject {
    @Published var panels: [PanelState] = []
    @Published var status: String = "starting"
    @Published var connected: Bool = false

    private let queue = DispatchQueue(label: "cmux-led.cmux-monitor")
    private var eventsProc: Process?
    private var snapshotTimer: DispatchSourceTimer?
    private var currentWorkspaceRef: String = "workspace:1"
    private var lastSurfaces: [Surface] = []

    func start() {
        queue.async { [weak self] in
            self?.bootstrap()
        }
    }

    private func bootstrap() {
        let p = CmuxClient.ping()
        DispatchQueue.main.async { [weak self] in
            self?.connected = p
            self?.status = p ? "connected" : "cmux socket blocked — run setup-cmux.sh and restart cmux"
        }
        startSnapshotTimer()
        startEventsStream()
        refreshSnapshot()
    }

    private func startEventsStream() {
        let proc = CmuxClient.streamEvents { [weak self] line in
            self?.handleEvent(line: line)
        }
        self.eventsProc = proc
    }

    private func handleEvent(line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = obj["type"] as? String ?? ""
        guard type == "event" else { return }
        let name = obj["name"] as? String ?? ""
        let interesting = name.hasPrefix("workspace.")
            || name.hasPrefix("surface.")
            || name.hasPrefix("pane.")
            || name == "window.focused"
        if interesting {
            queue.async { [weak self] in self?.refreshSnapshot() }
        }
    }

    private func startSnapshotTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5)
        t.setEventHandler { [weak self] in self?.refreshSnapshot() }
        t.resume()
        snapshotTimer = t
    }

    private func refreshSnapshot() {
        guard CmuxClient.ping() else {
            DispatchQueue.main.async { [weak self] in
                self?.connected = false
                self?.status = "cmux socket blocked"
            }
            return
        }
        let wsId = CmuxClient.currentWorkspaceRef() ?? currentWorkspaceRef
        currentWorkspaceRef = wsId
        let surfaces = CmuxClient.listSurfaces(workspaceRef: wsId)
        lastSurfaces = surfaces
        publishPanels()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.connected { self.connected = true; self.status = "connected" }
        }
    }

    private func publishPanels() {
        let states = lastSurfaces.enumerated().map { (i, s) -> PanelState in
            PanelState(
                id: s.ref,
                index: i,
                title: s.title,
                isBusy: titleSpinnerBusy(s.title),
                isFocused: s.selected
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.panels != states { self.panels = states }
        }
    }

    private func titleSpinnerBusy(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else { return false }
        return (0x2800...0x28FF).contains(first.value)
    }

    func selectSurface(index: Int) {
        guard index >= 0, index < lastSurfaces.count else { return }
        let ref = lastSurfaces[index].ref
        let ws = currentWorkspaceRef
        CmuxClient.focusSurface(workspaceRef: ws, surfaceRef: ref)
    }
}
