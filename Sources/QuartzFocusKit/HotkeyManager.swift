import Carbon
import Foundation

enum HotkeyManagerError: Error {
    case installHandler(OSStatus)
    case registerHotKey(OSStatus, Direction)
}

final class HotkeyManager {
    var onDirection: ((Direction) -> Void)?

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

    func register(bindings: [Direction: HotkeyBinding]) throws {
        try installEventHandlerIfNeeded()
        unregisterHotkeys()

        for direction in Direction.allCases {
            guard let binding = bindings[direction] else { continue }
            let identifier = Self.identifier(for: direction)
            try register(direction: direction, identifier: identifier, binding: binding)
        }
    }

    func suspend() {
        unregisterHotkeys()
    }

    private static func identifier(for direction: Direction) -> UInt32 {
        switch direction {
        case .left: return 1
        case .down: return 2
        case .up: return 3
        case .right: return 4
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

    private func register(direction: Direction, identifier: UInt32, binding: HotkeyBinding) throws {
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
            throw HotkeyManagerError.registerHotKey(status, direction)
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

        guard status == noErr, let direction = direction(for: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }

        onDirection?(direction)
        return noErr
    }

    private func direction(for identifier: UInt32) -> Direction? {
        switch identifier {
        case 1:
            return .left
        case 2:
            return .down
        case 3:
            return .up
        case 4:
            return .right
        default:
            return nil
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
