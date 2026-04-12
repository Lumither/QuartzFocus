import AppKit
import ApplicationServices

enum PermissionManager {
    static func isTrusted(prompt: Bool = false) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum AccessibilityValue {
    static func rawAttribute(_ uiElement: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(uiElement, attribute, &value)
        guard error == .success else {
            return nil
        }

        return value
    }

    static func string(_ uiElement: AXUIElement, _ attribute: CFString) -> String? {
        rawAttribute(uiElement, attribute) as? String
    }

    static func bool(_ uiElement: AXUIElement, _ attribute: CFString) -> Bool? {
        if let value = rawAttribute(uiElement, attribute) as? Bool {
            return value
        }

        if let value = rawAttribute(uiElement, attribute) as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    static func element(_ uiElement: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = rawAttribute(uiElement, attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ uiElement: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
        rawAttribute(uiElement, attribute) as? [AXUIElement] ?? []
    }

    static func frame(_ uiElement: AXUIElement) -> CGRect? {
        guard
            let positionValue = rawAttribute(uiElement, kAXPositionAttribute as CFString),
            let sizeValue = rawAttribute(uiElement, kAXSizeAttribute as CFString),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)

        var position = CGPoint.zero
        var size = CGSize.zero

        guard
            AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size).standardized
    }

    static func focusedWindow(of applicationElement: AXUIElement) -> AXUIElement? {
        element(applicationElement, kAXFocusedWindowAttribute as CFString)
            ?? element(applicationElement, kAXMainWindowAttribute as CFString)
    }
}

func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    guard
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
    else {
        return nil
    }

    return CGDirectDisplayID(screenNumber.uint32Value)
}

func screenID(for frame: CGRect) -> CGDirectDisplayID? {
    var bestMatch: (displayID: CGDirectDisplayID, area: CGFloat)?

    for screen in NSScreen.screens {
        guard let currentDisplayID = displayID(for: screen) else {
            continue
        }

        let overlapArea = screen.frame.intersection(frame).area
        if bestMatch == nil || overlapArea > bestMatch!.area {
            bestMatch = (currentDisplayID, overlapArea)
        }
    }

    if let bestMatch, bestMatch.area > 0 {
        return bestMatch.displayID
    }

    if let matchingScreen = NSScreen.screens.first(where: { $0.frame.contains(frame.center) }) {
        return displayID(for: matchingScreen)
    }

    return NSScreen.main.flatMap(displayID(for:))
}

func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    abs(lhs.minX - rhs.minX)
        + abs(lhs.minY - rhs.minY)
        + abs(lhs.width - rhs.width)
        + abs(lhs.height - rhs.height)
}

func isLikelyFullscreen(_ frame: CGRect) -> Bool {
    NSScreen.screens.contains { screen in
        frame.approximatelyEquals(to: screen.frame, tolerance: 2)
    }
}
