import AppKit
import Observation

@MainActor
@Observable
public final class AppModel {
    public private(set) var borderPolicy: BorderPolicy = .flash
    public private(set) var borderTrigger: BorderTrigger = .hotkey
    public private(set) var isDimEnabled: Bool = false
    public private(set) var dimOpacity: CGFloat = 0.55
    public private(set) var centerMouseOnFocus: Bool = false
    public private(set) var statusBarVisible: Bool = true
    public private(set) var permissionGranted: Bool = false
    public private(set) var hotkeys: [Direction: HotkeyBinding] = HotkeyBinding.defaults
    public private(set) var launchAtLoginEnabled: Bool = false

    @ObservationIgnored private let focusModeStore = FocusModeStore()
    @ObservationIgnored private let hotkeyManager = HotkeyManager()
    @ObservationIgnored private let windowDiscoveryService = WindowDiscoveryService()
    @ObservationIgnored private let directionalNavigator = DirectionalNavigator()
    @ObservationIgnored private let windowFocusService = WindowFocusService()
    @ObservationIgnored private let overlayManager = OverlayManager()
    @ObservationIgnored private let accessibilityObserverManager = AccessibilityObserverManager()

    @ObservationIgnored private var visualState = FocusVisualState.standard
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var pendingRefreshWorkItem: DispatchWorkItem?
    @ObservationIgnored private var observationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var lastFocusedWindowKey: String?
    @ObservationIgnored private var pendingInitialFlash: Bool = false
    @ObservationIgnored private var pendingHotkeyTrigger: Bool = false
    @ObservationIgnored private var currentFocusViaHotkey: Bool = false
    @ObservationIgnored private let flashDuration: TimeInterval = 0.6

    public init() {}

    public func start() {
        loadFromStore()
        configureCallbacks()
        registerHotkeys()
        installObservers()
        refreshPermissionState()
        applyVisualState()
    }

    private func loadFromStore() {
        borderPolicy = focusModeStore.borderPolicy
        borderTrigger = focusModeStore.borderTrigger
        isDimEnabled = focusModeStore.isDimEnabled
        dimOpacity = focusModeStore.dimOpacity
        hotkeys = focusModeStore.hotkeys
        centerMouseOnFocus = focusModeStore.centerMouseOnFocus
        statusBarVisible = focusModeStore.statusBarVisible
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled

        visualState.isDimEnabled = isDimEnabled
        visualState.dimOpacity = dimOpacity
    }

    private var hasAnyVisual: Bool {
        borderPolicy != .none || isDimEnabled
    }

    private func configureCallbacks() {
        hotkeyManager.onDirection = { [weak self] direction in
            Task { @MainActor [weak self] in
                self?.handle(direction: direction)
            }
        }

        accessibilityObserverManager.onEvent = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0.03)
            }
        }
    }

    public func setBorderPolicy(_ policy: BorderPolicy) {
        borderPolicy = policy
        focusModeStore.setBorderPolicy(policy)

        lastFocusedWindowKey = nil
        currentFocusViaHotkey = false
        pendingInitialFlash = (policy == .flash)

        applyVisualState()
    }

    public func setBorderTrigger(_ trigger: BorderTrigger) {
        borderTrigger = trigger
        focusModeStore.setBorderTrigger(trigger)

        currentFocusViaHotkey = false
        scheduleRefresh(delay: 0)
    }

    public func setDim(_ enabled: Bool) {
        isDimEnabled = enabled
        visualState.isDimEnabled = enabled
        focusModeStore.setDimEnabled(enabled)
        applyVisualState()
    }

    public func setDimOpacity(_ opacity: CGFloat) {
        dimOpacity = opacity
        visualState.dimOpacity = opacity
        focusModeStore.setDimOpacity(opacity)
        scheduleRefresh(delay: 0)
    }

    public func setHotkey(_ direction: Direction, _ binding: HotkeyBinding) {
        hotkeys[direction] = binding
        focusModeStore.setHotkeys(hotkeys)
        registerHotkeys()
    }

    public func setHotkeyRecording(_ recording: Bool) {
        if recording {
            hotkeyManager.suspend()
        } else {
            registerHotkeys()
        }
    }

    public func setCenterMouseOnFocus(_ enabled: Bool) {
        centerMouseOnFocus = enabled
        focusModeStore.setCenterMouseOnFocus(enabled)
    }

    public func setStatusBarVisible(_ visible: Bool) {
        statusBarVisible = visible
        focusModeStore.setStatusBarVisible(visible)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = enabled
        } catch {
            fputs("Launch at login error: \(error)\n", stderr)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        }
    }

    public func requestAccessibilityPermission() {
        _ = PermissionManager.isTrusted(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshPermissionState()
                self?.scheduleRefresh(delay: 0)
            }
        }
    }

    private func registerHotkeys() {
        do {
            try hotkeyManager.register(bindings: hotkeys)
        } catch {
            fputs("Failed to register hotkeys: \(error)\n", stderr)
        }
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        addObserver(center: workspaceCenter, name: NSWorkspace.didActivateApplicationNotification) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEnvironmentChange()
            }
        }

        addObserver(center: workspaceCenter, name: NSWorkspace.activeSpaceDidChangeNotification) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEnvironmentChange()
            }
        }

        addObserver(center: workspaceCenter, name: NSWorkspace.didHideApplicationNotification) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0)
            }
        }

        addObserver(center: workspaceCenter, name: NSWorkspace.didUnhideApplicationNotification) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0)
            }
        }

        addObserver(center: .default, name: NSApplication.didChangeScreenParametersNotification) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0)
            }
        }
    }

    private func addObserver(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main, using: handler)
        observationTokens.append((center, token))
    }

    private func handleEnvironmentChange() {
        refreshPermissionState()
        scheduleRefresh(delay: 0)
    }

    private func refreshPermissionState() {
        let isTrusted = PermissionManager.isTrusted()
        permissionGranted = isTrusted

        if isTrusted {
            updateObservationState()
        } else {
            accessibilityObserverManager.detach()
            overlayManager.hideAll()
        }
    }

    private func updateObservationState() {
        guard hasAnyVisual else {
            accessibilityObserverManager.detach()
            return
        }
        accessibilityObserverManager.attachToFrontmostApplication()
    }

    private func applyVisualState() {
        if hasAnyVisual {
            startRefreshTimer()
            refreshPermissionState()
            scheduleRefresh(delay: 0)
        } else {
            stopRefreshTimer()
            accessibilityObserverManager.detach()
            overlayManager.hideAll()
        }
    }

    private func handle(direction: Direction) {
        refreshPermissionState()
        guard permissionGranted else { return }

        guard let currentWindow = windowDiscoveryService.currentFocusedWindow() else { return }

        let candidates = windowDiscoveryService.discoverCandidates()
        guard
            let targetWindow = directionalNavigator.target(
                from: currentWindow, candidates: candidates, direction: direction)
        else { return }

        pendingHotkeyTrigger = true
        _ = windowFocusService.focus(targetWindow)
        if centerMouseOnFocus {
            CGWarpMouseCursorPosition(CGPoint(x: targetWindow.frame.midX, y: targetWindow.frame.midY))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        scheduleRefresh(delay: 0.08)
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisuals()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func scheduleRefresh(delay: TimeInterval) {
        pendingRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshVisuals()
            }
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshVisuals() {
        guard hasAnyVisual else {
            overlayManager.hideAll()
            return
        }
        refreshPermissionState()
        guard permissionGranted else {
            overlayManager.hideAll()
            return
        }
        guard let focusedWindow = windowDiscoveryService.currentFocusedWindow() else {
            overlayManager.hideAll()
            return
        }

        let windowKey = "\(focusedWindow.pid)-\(focusedWindow.windowID)"
        let focusChanged = lastFocusedWindowKey != nil && lastFocusedWindowKey != windowKey
        lastFocusedWindowKey = windowKey

        let hotkeyTriggered = pendingHotkeyTrigger
        pendingHotkeyTrigger = false

        if focusChanged {
            currentFocusViaHotkey = hotkeyTriggered
        }

        let effectivePolicy: BorderPolicy
        switch (borderPolicy, borderTrigger) {
        case (.alwaysOn, .hotkey) where !currentFocusViaHotkey:
            effectivePolicy = .none
        default:
            effectivePolicy = borderPolicy
        }

        visualState.borderPolicy = effectivePolicy
        visualState.isDimEnabled = isDimEnabled
        visualState.dimOpacity = dimOpacity

        overlayManager.update(focusedFrame: focusedWindow.frame, state: visualState)

        let shouldFlashOnChange: Bool
        switch borderTrigger {
        case .anyFocusChange:
            shouldFlashOnChange = focusChanged
        case .hotkey:
            shouldFlashOnChange = focusChanged && hotkeyTriggered
        }

        if borderPolicy == .flash && (shouldFlashOnChange || pendingInitialFlash) {
            overlayManager.triggerBorderFlash(duration: flashDuration)
            pendingInitialFlash = false
        }
    }
}
