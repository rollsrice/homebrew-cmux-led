import SwiftUI
import AppKit

private let cornerR: CGFloat = 14

enum BarPattern {
    case empty
    case allBusy
    case allIdle
    case mixed

    static func from(_ panels: [PanelState]) -> BarPattern {
        if panels.isEmpty { return .empty }
        let busy = panels.contains(where: { $0.isBusy })
        let idle = panels.contains(where: { !$0.isBusy })
        if busy && idle { return .mixed }
        if busy { return .allBusy }
        return .allIdle
    }
}

struct ContentView: View {
    @ObservedObject var monitor: CmuxMonitor
    @Binding var alwaysOnTop: Bool
    var onSelect: (Int) -> Void

    var body: some View {
        Group {
            if monitor.panels.isEmpty {
                HStack(spacing: 8) {
                    Text(monitor.status)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                    Spacer(minLength: 0)
                }
            } else if monitor.mode == .workspaces {
                VStack(spacing: 8) {
                    ForEach(monitor.panels) { p in
                        LEDDot(isBusy: p.isBusy, isFocused: p.isFocused, title: p.title, index: p.index) {
                            onSelect(p.index)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(monitor.panels) { p in
                        LEDDot(isBusy: p.isBusy, isFocused: p.isFocused, title: p.title, index: p.index) {
                            onSelect(p.index)
                        }
                    }
                    PatternEmoji(pattern: BarPattern.from(monitor.panels))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedVisualEffect(cornerRadius: cornerR))
        .overlay(
            RoundedRectangle(cornerRadius: cornerR)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
        .padding(8)
        .contextMenu {
            Toggle("Always on top", isOn: $alwaysOnTop)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

struct PatternEmoji: View {
    let pattern: BarPattern

    var body: some View {
        Group {
            switch pattern {
            case .allBusy:
                AssetImage(name: "chili-calyx", size: CGSize(width: 32, height: 28))
            case .mixed:
                AssetImage(name: "tree-top-star", size: CGSize(width: 40, height: 28))
            case .allIdle, .empty:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: pattern)
    }
}

struct AssetImage: View {
    let name: String
    let size: CGSize

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }
}

struct LEDDot: View {
    let isBusy: Bool
    let isFocused: Bool
    let title: String
    let index: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isBusy ? Color.red : Color.green)
                    .frame(width: 14, height: 14)
                    .shadow(color: (isBusy ? Color.red : Color.green).opacity(0.7), radius: 3)
                if isFocused {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title.isEmpty ? "tab \(index + 1)" : "\(index + 1): \(title)")
    }
}

struct RoundedVisualEffect: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
    }
}
