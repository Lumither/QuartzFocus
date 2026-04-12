import AppKit
import ApplicationServices

@MainActor
final class AccessibilityObserverManager {
    var onEvent: (() -> Void)?

    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else {
            return
        }

        let manager = Unmanaged<AccessibilityObserverManager>.fromOpaque(refcon).takeUnretainedValue()
        let notificationName = notification as String

        DispatchQueue.main.async {
            manager.handleNotification(notificationName)
        }
    }

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedApplication: AXUIElement?
    private var observedWindow: AXUIElement?

    func attachToFrontmostApplication() {
        guard PermissionManager.isTrusted(),
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
        else {
            detach()
            return
        }

        if observedPID == frontmostApplication.processIdentifier, observer != nil {
            trackFocusedWindow()
            return
        }

        attach(to: frontmostApplication.processIdentifier)
    }

    func detach() {
        guard let observer else {
            observedPID = nil
            observedApplication = nil
            observedWindow = nil
            return
        }

        removeObservedWindowNotifications()

        if let observedApplication {
            removeNotification(kAXFocusedWindowChangedNotification, from: observedApplication)
            removeNotification(kAXMainWindowChangedNotification, from: observedApplication)
            removeNotification(kAXWindowCreatedNotification, from: observedApplication)
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        self.observer = nil
        observedPID = nil
        observedApplication = nil
        observedWindow = nil
    }

    private func attach(to pid: pid_t) {
        detach()

        var observer: AXObserver?
        let error = AXObserverCreate(pid, Self.callback, &observer)
        guard error == .success, let observer else {
            return
        }

        let applicationElement = AXUIElementCreateApplication(pid)

        self.observer = observer
        observedPID = pid
        observedApplication = applicationElement

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        addNotification(kAXFocusedWindowChangedNotification, to: applicationElement)
        addNotification(kAXMainWindowChangedNotification, to: applicationElement)
        addNotification(kAXWindowCreatedNotification, to: applicationElement)

        trackFocusedWindow()
    }

    private func trackFocusedWindow() {
        guard let observedApplication else {
            return
        }

        let currentFocusedWindow = AccessibilityValue.focusedWindow(of: observedApplication)

        if let observedWindow, let currentFocusedWindow, CFEqual(observedWindow, currentFocusedWindow) {
            return
        }

        removeObservedWindowNotifications()
        observedWindow = currentFocusedWindow

        guard let currentFocusedWindow else {
            return
        }

        addNotification(kAXWindowMovedNotification, to: currentFocusedWindow)
        addNotification(kAXWindowResizedNotification, to: currentFocusedWindow)
        addNotification(kAXWindowMiniaturizedNotification, to: currentFocusedWindow)
        addNotification(kAXWindowDeminiaturizedNotification, to: currentFocusedWindow)
        addNotification(kAXUIElementDestroyedNotification, to: currentFocusedWindow)
    }

    private func removeObservedWindowNotifications() {
        guard let observedWindow else {
            return
        }

        removeNotification(kAXWindowMovedNotification, from: observedWindow)
        removeNotification(kAXWindowResizedNotification, from: observedWindow)
        removeNotification(kAXWindowMiniaturizedNotification, from: observedWindow)
        removeNotification(kAXWindowDeminiaturizedNotification, from: observedWindow)
        removeNotification(kAXUIElementDestroyedNotification, from: observedWindow)
    }

    private func addNotification(_ notification: String, to element: AXUIElement) {
        guard let observer else {
            return
        }

        let result = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        switch result {
        case .success, .notificationAlreadyRegistered, .notificationUnsupported:
            return
        default:
            return
        }
    }

    private func removeNotification(_ notification: String, from element: AXUIElement) {
        guard let observer else {
            return
        }

        _ = AXObserverRemoveNotification(observer, element, notification as CFString)
    }

    private func handleNotification(_ notificationName: String) {
        switch notificationName {
        case kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification:
            trackFocusedWindow()
        case kAXUIElementDestroyedNotification:
            observedWindow = nil
            trackFocusedWindow()
        default:
            break
        }

        onEvent?()
    }
}
