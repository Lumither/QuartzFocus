import Foundation

final class FocusModeStore {
    private enum Keys {
        static let borderEnabled = "borderEnabled"
        static let borderPolicy = "borderPolicy"
        static let borderTrigger = "borderTrigger"
        static let centerMouseOnFocus = "centerMouseOnFocus"
        static let dimEnabled = "dimEnabled"
        static let dimOpacity = "dimOpacity"
        static let hotkeys = "hotkeys"
        static let statusBarVisible = "statusBarVisible"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var borderPolicy: BorderPolicy {
        if let raw = defaults.string(forKey: Keys.borderPolicy),
            let policy = BorderPolicy(rawValue: raw)
        {
            return policy
        }
        // Legacy migration: old boolean toggle → alwaysOn or flash.
        if defaults.object(forKey: Keys.borderEnabled) != nil {
            return defaults.bool(forKey: Keys.borderEnabled) ? .alwaysOn : .flash
        }
        return .flash
    }

    func setBorderPolicy(_ policy: BorderPolicy) {
        defaults.set(policy.rawValue, forKey: Keys.borderPolicy)
    }

    var borderTrigger: BorderTrigger {
        if let raw = defaults.string(forKey: Keys.borderTrigger),
            let trigger = BorderTrigger(rawValue: raw)
        {
            return trigger
        }
        return .hotkey
    }

    func setBorderTrigger(_ trigger: BorderTrigger) {
        defaults.set(trigger.rawValue, forKey: Keys.borderTrigger)
    }

    var isDimEnabled: Bool {
        defaults.bool(forKey: Keys.dimEnabled)
    }

    func setDimEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.dimEnabled)
    }

    var dimOpacity: CGFloat {
        let value = defaults.double(forKey: Keys.dimOpacity)
        return value > 0 ? CGFloat(value) : FocusVisualState.standard.dimOpacity
    }

    func setDimOpacity(_ opacity: CGFloat) {
        defaults.set(Double(opacity), forKey: Keys.dimOpacity)
    }

    var hotkeys: [HotkeyAction: HotkeyBinding] {
        var result = HotkeyBinding.defaults
        guard let data = defaults.data(forKey: Keys.hotkeys),
            let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data)
        else {
            return result
        }
        for (key, value) in decoded {
            if let action = HotkeyAction(rawValue: key) {
                result[action] = value
            } else if let direction = Direction(rawValue: key) {
                result[HotkeyAction.direction(direction)] = value
            }
        }
        return result
    }

    func setHotkeys(_ hotkeys: [HotkeyAction: HotkeyBinding]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stringKeyed) else { return }
        defaults.set(data, forKey: Keys.hotkeys)
    }

    var centerMouseOnFocus: Bool {
        defaults.bool(forKey: Keys.centerMouseOnFocus)
    }

    func setCenterMouseOnFocus(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.centerMouseOnFocus)
    }

    var statusBarVisible: Bool {
        if defaults.object(forKey: Keys.statusBarVisible) == nil { return true }
        return defaults.bool(forKey: Keys.statusBarVisible)
    }

    func setStatusBarVisible(_ visible: Bool) {
        defaults.set(visible, forKey: Keys.statusBarVisible)
    }
}
