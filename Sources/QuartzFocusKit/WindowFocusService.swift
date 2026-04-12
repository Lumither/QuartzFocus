import AppKit
import ApplicationServices

@MainActor
final class WindowFocusService {
    @discardableResult
    func focus(_ candidate: WindowCandidate) -> Bool {
        let applicationElement = AXUIElementCreateApplication(candidate.pid)
        let runningApplication = NSRunningApplication(processIdentifier: candidate.pid)
        let truthy = kCFBooleanTrue!

        _ = AXUIElementSetAttributeValue(applicationElement, kAXFrontmostAttribute as CFString, truthy)
        _ = AXUIElementSetAttributeValue(candidate.axWindow, kAXMainAttribute as CFString, truthy)
        _ = AXUIElementSetAttributeValue(candidate.axWindow, kAXFocusedAttribute as CFString, truthy)

        runningApplication?.activate(options: [.activateAllWindows])
        let raiseResult = AXUIElementPerformAction(candidate.axWindow, kAXRaiseAction as CFString)

        return raiseResult == .success || runningApplication?.isActive == true
    }
}
