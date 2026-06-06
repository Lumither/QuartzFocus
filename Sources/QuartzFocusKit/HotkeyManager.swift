import Carbon
import Foundation

enum HotkeyManagerError: Error {
    case installHandler(OSStatus)
    case registerHotKey(OSStatus, HotkeyAction)
}

final class HotkeyManager {
    var onAction: ((HotkeyAction) -> Void)?

    private static let signature: OSType = 0x5146_4F43  // "QFOC"
    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKeyEvent(event)
    }

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    deinit {
        unregisterAll()
    }

    func register(bindings: [HotkeyAction: HotkeyBinding]) throws {
        try installEventHandlerIfNeeded()
        unregisterHotkeys()

        for action in HotkeyAction.allCases {
            guard let binding = bindings[action] else { continue }
            let identifier = Self.identifier(for: action)
            try register(action: action, identifier: identifier, binding: binding)
        }
    }

    func suspend() {
        unregisterHotkeys()
    }

    private static func identifier(for action: HotkeyAction) -> UInt32 {
        switch action {
        case .focusLeft: return 1
        case .focusDown: return 2
        case .focusUp: return 3
        case .focusRight: return 4
        case .workspaceNext: return 5
        case .workspacePrevious: return 6
        case .missionControl: return 7
        case .appExpose: return 8
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotkeyManagerError.installHandler(status)
        }
    }

    private func register(action: HotkeyAction, identifier: UInt32, binding: HotkeyBinding) throws {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)

        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotkeyManagerError.registerHotKey(status, action)
        }

        hotKeyRefs[identifier] = hotKeyRef
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, let action = action(for: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }

        onAction?(action)
        return noErr
    }

    private func action(for identifier: UInt32) -> HotkeyAction? {
        switch identifier {
        case 1: return .focusLeft
        case 2: return .focusDown
        case 3: return .focusUp
        case 4: return .focusRight
        case 5: return .workspaceNext
        case 6: return .workspacePrevious
        case 7: return .missionControl
        case 8: return .appExpose
        default: return nil
        }
    }

    private func unregisterHotkeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
    }

    private func unregisterAll() {
        unregisterHotkeys()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
