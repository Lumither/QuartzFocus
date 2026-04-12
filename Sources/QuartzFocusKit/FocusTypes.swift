import AppKit
import ApplicationServices

public enum Direction: String, CaseIterable, Codable, Sendable {
    case left
    case down
    case up
    case right
}

public enum BorderPolicy: String, CaseIterable, Codable, Sendable {
    case none
    case flash
    case alwaysOn

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .flash: return "Flash"
        case .alwaysOn: return "Always on"
        }
    }
}

public enum BorderTrigger: String, CaseIterable, Codable, Sendable {
    case anyFocusChange
    case hotkey

    public var displayName: String {
        switch self {
        case .anyFocusChange: return "Any focus change"
        case .hotkey: return "Hotkey only"
        }
    }
}

struct WindowCandidate: Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
    let axWindow: AXUIElement
    let screenID: CGDirectDisplayID?

    static func == (lhs: WindowCandidate, rhs: WindowCandidate) -> Bool {
        lhs.pid == rhs.pid && lhs.windowID == rhs.windowID && lhs.frame == rhs.frame
    }

    func matches(_ other: WindowCandidate) -> Bool {
        guard pid == other.pid else {
            return false
        }

        if windowID != 0, other.windowID != 0 {
            return windowID == other.windowID
        }

        return frame.approximatelyEquals(to: other.frame, tolerance: 4)
    }
}

struct FocusVisualState {
    var borderPolicy: BorderPolicy
    var isDimEnabled: Bool
    var dimOpacity: CGFloat
    var borderWidth: CGFloat
    var cornerRadius: CGFloat
    var insetPadding: CGFloat
    var borderColor: NSColor

    var hasAnyVisual: Bool { borderPolicy != .none || isDimEnabled }

    static var standard: FocusVisualState {
        FocusVisualState(
            borderPolicy: .flash,
            isDimEnabled: false,
            dimOpacity: 0.55,
            borderWidth: 2,
            cornerRadius: 12,
            insetPadding: 0,
            borderColor: NSColor(srgbRed: 0.80, green: 0.92, blue: 1.00, alpha: 1.0)
        )
    }
}

extension CGRect {
    var area: CGFloat {
        width * height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func approximatelyEquals(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
