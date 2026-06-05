import Foundation

enum LEDMode: String {
    case surfaces
    case workspaces

    static let defaultsKey = "ledMode"

    static func load(from defaults: UserDefaults = .standard) -> LEDMode {
        guard let raw = defaults.string(forKey: defaultsKey),
              let mode = LEDMode(rawValue: raw) else {
            return .workspaces
        }
        return mode
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: LEDMode.defaultsKey)
    }
}
