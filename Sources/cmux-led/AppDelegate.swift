import AppKit
import SwiftUI
import Combine

final class WindowState: ObservableObject {
    @Published var alwaysOnTop: Bool = true
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let monitor = CmuxMonitor()
    let state = WindowState()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var surfacesMenuItem: NSMenuItem?
    private var workspacesMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(
            monitor: monitor,
            alwaysOnTop: stateBinding(),
            onSelect: { [weak self] idx in self?.monitor.select(index: idx) }
        ).environmentObject(state)

        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 280, height: 56),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = host
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.makeKeyAndOrderFront(nil)

        applyAlwaysOnTop(state.alwaysOnTop)
        state.$alwaysOnTop
            .sink { [weak self] v in self?.applyAlwaysOnTop(v) }
            .store(in: &cancellables)

        installStatusItem()
        monitor.start()

        monitor.$panels
            .map { $0.count }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        monitor.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshModeMenu()
                self?.relayout()
            }
            .store(in: &cancellables)

        relayout()
    }

    private func relayout() {
        let count = monitor.panels.count
        let axis: Axis = monitor.mode == .workspaces ? .vertical : .horizontal
        resizeWindow(forCount: count, axis: axis)
    }

    private func resizeWindow(forCount count: Int, axis: Axis) {
        // Stack axis: N LED slots (22 + 8 spacing) + one trailing empty LED slot + padding.
        // Cross axis: single LED column/row thickness.
        let ledSlot: CGFloat = 30
        let trailingEmpty: CGFloat = 30
        let padding: CGFloat = 40
        let stackExtent = count == 0 ? 200 : CGFloat(count) * ledSlot - 8 + trailingEmpty + padding

        let width: CGFloat
        let height: CGFloat
        if count == 0 {
            // Empty/status text always shows as a small horizontal pill.
            width = 200
            height = 56
        } else if axis == .vertical {
            width = 62           // one LED + horizontal padding
            height = stackExtent
        } else {
            width = stackExtent
            height = 56
        }

        let frame = window.frame
        // Keep the top-left anchored: top edge fixed, grow down; left edge fixed.
        let newOrigin = NSPoint(x: frame.origin.x, y: frame.origin.y + (frame.height - height))
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: width, height: height))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func stateBinding() -> Binding<Bool> {
        Binding(
            get: { self.state.alwaysOnTop },
            set: { self.state.alwaysOnTop = $0 }
        )
    }

    private func applyAlwaysOnTop(_ on: Bool) {
        window.level = on ? NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) - 1) : .normal
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "●"
        let menu = NSMenu()
        let pinItem = NSMenuItem(title: "Always on top", action: #selector(togglePin(_:)), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = state.alwaysOnTop ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        let surfacesItem = NSMenuItem(title: "LEDs: Surfaces", action: #selector(setSurfacesMode), keyEquivalent: "")
        surfacesItem.target = self
        menu.addItem(surfacesItem)
        let workspacesItem = NSMenuItem(title: "LEDs: Workspaces", action: #selector(setWorkspacesMode), keyEquivalent: "")
        workspacesItem.target = self
        menu.addItem(workspacesItem)
        self.surfacesMenuItem = surfacesItem
        self.workspacesMenuItem = workspacesItem
        refreshModeMenu()
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show window", action: #selector(showWindow), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        state.$alwaysOnTop
            .sink { [weak pinItem] v in pinItem?.state = v ? .on : .off }
            .store(in: &cancellables)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        state.alwaysOnTop.toggle()
    }

    @objc private func setSurfacesMode() { monitor.mode = .surfaces }
    @objc private func setWorkspacesMode() { monitor.mode = .workspaces }

    private func refreshModeMenu() {
        surfacesMenuItem?.state = monitor.mode == .surfaces ? .on : .off
        workspacesMenuItem?.state = monitor.mode == .workspaces ? .on : .off
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }
}
