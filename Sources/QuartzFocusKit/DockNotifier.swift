import CoreFoundation
import Darwin
import Foundation

private typealias CoreDockSendNotificationFn = @convention(c) (CFString, Int32) -> Int32

private let coreDockSendNotification: CoreDockSendNotificationFn? = {
    let symbolName = "CoreDockSendNotification"
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    if let ptr = dlsym(rtldDefault, symbolName) {
        return unsafeBitCast(ptr, to: CoreDockSendNotificationFn.self)
    }

    let candidates = [
        "/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock",
        "/System/Library/PrivateFrameworks/CoreDock.framework/Versions/A/CoreDock",
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        "/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox",
    ]

    for path in candidates {
        guard let handle = dlopen(path, RTLD_NOW) else { continue }
        if let ptr = dlsym(handle, symbolName) {
            return unsafeBitCast(ptr, to: CoreDockSendNotificationFn.self)
        }
    }
    return nil
}()

final class DockNotifier {
    func showMissionControl() {
        send("com.apple.expose.awake")
    }

    func showAppExpose() {
        send("com.apple.expose.front.awake")
    }

    private func send(_ notification: String) {
        guard let fn = coreDockSendNotification else {
            fputs("DockNotifier: CoreDockSendNotification unavailable\n", stderr)
            return
        }
        _ = fn(notification as CFString, 0)
    }
}
