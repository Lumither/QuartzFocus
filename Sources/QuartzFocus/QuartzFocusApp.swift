import AppKit
import QuartzFocusKit
import SwiftUI

private let showSettingsNotification = Notification.Name("com.lumither.QuartzFocus.showSettings")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()

        DistributedNotificationCenter.default().addObserver(
            forName: showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettings()
            }
        }

        if !model.statusBarVisible {
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(model: model).frame(width: 460)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "QuartzFocus Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
struct QuartzFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.handleSecondaryLaunchIfNeeded()
    }

    private static func handleSecondaryLaunchIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }

        guard !others.isEmpty else { return }

        DistributedNotificationCenter.default().postNotificationName(
            showSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra(
            "QuartzFocus",
            systemImage: "scope",
            isInserted: Binding(
                get: { appDelegate.model.statusBarVisible },
                set: { appDelegate.model.setStatusBarVisible($0) }
            )
        ) {
            MenuBarContent(
                model: appDelegate.model,
                onOpenSettings: { appDelegate.openSettings() }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
