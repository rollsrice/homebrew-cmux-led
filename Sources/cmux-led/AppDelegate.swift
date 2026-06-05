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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(
            monitor: monitor,
            alwaysOnTop: stateBinding(),
            onSelect: { [weak self] idx in self?.monitor.selectSurface(index: idx) }
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
            .sink { [weak self] count in self?.resizeWindow(forTabCount: count) }
            .store(in: &cancellables)

        resizeWindow(forTabCount: 0)
    }

    private func resizeWindow(forTabCount count: Int) {
        // Layout: N LEDs (22pt each, 8pt gaps) + trailing room for one extra LED.
        // The pattern emoji (only shown when busy/mixed) shares the trailing room.
        // Padding: 12pt inner each side + 8pt outer shadow gutter each side = 40pt.
        let ledSlot: CGFloat = 30   // 22 + 8 spacing
        let trailingEmpty: CGFloat = 30 // room for exactly one extra LED
        let padding: CGFloat = 40
        let width: CGFloat
        if count == 0 {
            width = 200 // status text needs a stable minimum
        } else {
            width = CGFloat(count) * ledSlot - 8 + trailingEmpty + padding
        }
        let height: CGFloat = 56
        let frame = window.frame
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

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }
}
