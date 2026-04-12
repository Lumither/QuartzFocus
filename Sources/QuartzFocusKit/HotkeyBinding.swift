import AppKit
import Carbon

public struct HotkeyBinding: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var character: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, character: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.character = character
    }

    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        guard carbon != 0 else { return nil }

        let chars = event.charactersIgnoringModifiers ?? ""
        guard !chars.isEmpty else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
        self.character = chars
    }

    public var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyDisplayString
        return result
    }

    private var keyDisplayString: String {
        if let special = Self.specialKeyNames[keyCode] {
            return special
        }
        return character.uppercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_Return): "⏎",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "␣",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
    ]
}

extension HotkeyBinding {
    public static let defaults: [Direction: HotkeyBinding] = [
        .left: HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_H),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey),
            character: "h"
        ),
        .down: HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_J),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey),
            character: "j"
        ),
        .up: HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey),
            character: "k"
        ),
        .right: HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_L),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey),
            character: "l"
        ),
    ]
}
