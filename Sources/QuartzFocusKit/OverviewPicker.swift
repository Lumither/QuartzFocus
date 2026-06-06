import AppKit
import ApplicationServices
import Carbon
@preconcurrency import CoreGraphics
import Darwin
import QuartzCore

private typealias AXGetWindowIDFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private typealias SLSMainConnectionIDFn = @convention(c) () -> Int32
private typealias SLSGetActiveSpaceFn = @convention(c) (Int32) -> UInt64
private typealias SLSCopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
private typealias SLSCopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

private func skyLightSymbol<T>(_ name: String, as type: T.Type) -> T? {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    if let ptr = dlsym(rtldDefault, name) {
        return unsafeBitCast(ptr, to: T.self)
    }
    let candidates = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
    ]
    for path in candidates {
        guard let handle = dlopen(path, RTLD_NOW) else { continue }
        if let ptr = dlsym(handle, name) {
            return unsafeBitCast(ptr, to: T.self)
        }
    }
    return nil
}

private let axGetWindowID: AXGetWindowIDFn? = {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(rtldDefault, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(ptr, to: AXGetWindowIDFn.self)
}()

private let slsMainConnectionID: SLSMainConnectionIDFn? =
    skyLightSymbol("SLSMainConnectionID", as: SLSMainConnectionIDFn.self)
private let slsGetActiveSpace: SLSGetActiveSpaceFn? =
    skyLightSymbol("SLSGetActiveSpace", as: SLSGetActiveSpaceFn.self)
private let slsCopyManagedDisplaySpaces: SLSCopyManagedDisplaySpacesFn? =
    skyLightSymbol("SLSCopyManagedDisplaySpaces", as: SLSCopyManagedDisplaySpacesFn.self)
private let slsCopySpacesForWindows: SLSCopySpacesForWindowsFn? =
    skyLightSymbol("SLSCopySpacesForWindows", as: SLSCopySpacesForWindowsFn.self)

@MainActor
public final class OverviewPicker {
    private static let hintAlphabet: [Character] = Array("asdfghjkl;")
    private static let layoutSettleDelay: TimeInterval = 0.25
    private static let clickPostDelay: TimeInterval = 0.05

    public enum Mode {
        case missionControl
        case appExpose
    }

    private let dockNotifier: DockNotifier
    private let windowDiscoveryService: WindowDiscoveryService
    private let windowFocusService: WindowFocusService
    private let workspaceSwitcher: WorkspaceSwitcher

    private var state: State = .idle
    private var activeMode: Mode?
    private var capturedFrontPID: pid_t?
    private var overlayWindows: [CGDirectDisplayID: PickerOverlayWindow] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingStart: DispatchWorkItem?

    private var entries: [HintEntry] = []
    private var ownAppPID: pid_t = ProcessInfo.processInfo.processIdentifier

    init(
        dockNotifier: DockNotifier,
        windowDiscoveryService: WindowDiscoveryService,
        windowFocusService: WindowFocusService,
        workspaceSwitcher: WorkspaceSwitcher
    ) {
        self.dockNotifier = dockNotifier
        self.windowDiscoveryService = windowDiscoveryService
        self.windowFocusService = windowFocusService
        self.workspaceSwitcher = workspaceSwitcher
    }

    public func toggle(_ mode: Mode) {
        switch state {
        case .idle:
            beginOpen(mode: mode)
        default:
            cancel()
        }
    }

    private func beginOpen(mode: Mode) {
        let snapshot: [WindowCandidate]
        switch mode {
        case .missionControl:
            capturedFrontPID = nil
            let all = windowDiscoveryService.discoverCandidates()
            snapshot = all.filter { $0.pid != ownAppPID }
        case .appExpose:
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                pid != ownAppPID
            else { return }
            capturedFrontPID = pid
            snapshot = axWindowsForApp(pid: pid)
        }
        guard !snapshot.isEmpty || mode == .appExpose else { return }

        activeMode = mode
        state = .waitingForLayout(snapshot: snapshot)
        sendOpenNotification(mode: mode)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeOpen()
            }
        }
        pendingStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.layoutSettleDelay, execute: workItem)
    }

    private func axWindowsForApp(pid: pid_t) -> [WindowCandidate] {
        guard let getWindowID = axGetWindowID else { return [] }
        let appElement = AXUIElementCreateApplication(pid)
        let axWindows = AccessibilityValue.elements(appElement, kAXWindowsAttribute as CFString)

        var result: [WindowCandidate] = []
        for axWindow in axWindows {
            guard AccessibilityValue.string(axWindow, kAXRoleAttribute as CFString) == kAXWindowRole as String
            else { continue }
            if AccessibilityValue.bool(axWindow, kAXMinimizedAttribute as CFString) == true { continue }
            let subrole = AccessibilityValue.string(axWindow, kAXSubroleAttribute as CFString)
            if let subrole, !subrole.isEmpty, subrole != kAXStandardWindowSubrole as String { continue }

            var windowID: CGWindowID = 0
            guard getWindowID(axWindow, &windowID) == .success, windowID != 0 else { continue }

            let frame = AccessibilityValue.frame(axWindow) ?? .zero
            result.append(
                WindowCandidate(
                    pid: pid,
                    windowID: windowID,
                    frame: frame,
                    axWindow: axWindow,
                    screenID: screenID(for: frame)
                )
            )
        }
        return result
    }



    private func sendOpenNotification(mode: Mode) {
        switch mode {
        case .missionControl: dockNotifier.showMissionControl()
        case .appExpose: dockNotifier.showAppExpose()
        }
    }

    private func sendCloseNotification() {
        guard let mode = activeMode else { return }
        switch mode {
        case .missionControl: dockNotifier.showMissionControl()
        case .appExpose: dockNotifier.showAppExpose()
        }
    }

    private func completeOpen() {
        guard case .waitingForLayout(let snapshot) = state else { return }
        pendingStart = nil

        let frames = transformedFrames()
        entries = buildEntries(snapshot: snapshot, frames: frames)

        guard !entries.isEmpty else {
            tearDown(closeOverview: true)
            return
        }

        showOverlay(mode: .hint(prefix: ""))
        installEventTap()
        state = .hint(prefix: "")
    }


    private func buildEntries(
        snapshot: [WindowCandidate], frames: [CGWindowID: CGRect]
    ) -> [HintEntry] {
        var seen: Set<CGWindowID> = []
        var pairs: [(candidate: WindowCandidate?, windowID: CGWindowID, pid: pid_t, frame: CGRect, title: String)] = []

        for c in snapshot {
            guard let frame = frames[c.windowID] else { continue }
            pairs.append((c, c.windowID, c.pid, frame, titleFor(c)))
            seen.insert(c.windowID)
        }

        if activeMode == .appExpose, let frontPID = capturedFrontPID {
            let cgInfo = cgWindowInfo(filterPID: frontPID)
            for (windowID, info) in cgInfo where !seen.contains(windowID) {
                guard let frame = frames[windowID] else { continue }
                pairs.append((nil, windowID, info.pid, frame, info.title))
            }
        }

        let hints = generateHints(count: pairs.count)
        return zip(hints, pairs).map { hint, p in
            HintEntry(
                hint: hint,
                candidate: p.candidate,
                windowID: p.windowID,
                pid: p.pid,
                mcFrame: p.frame,
                title: p.title
            )
        }
    }

    private func cgWindowInfo(filterPID: pid_t) -> [CGWindowID: (frame: CGRect, title: String, pid: pid_t)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var result: [CGWindowID: (frame: CGRect, title: String, pid: pid_t)] = [:]
        for entry in raw {
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
            else { continue }
            let pid = pid_t(pidNumber.int32Value)
            if pid != filterPID { continue }
            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds),
                bounds.width > 1, bounds.height > 1
            else { continue }
            let title = (entry[kCGWindowName as String] as? String) ?? ""
            result[CGWindowID(windowNumber.uint32Value)] = (bounds, title, pid)
        }
        return result
    }

    private func refreshFrames() {
        let frames = transformedFrames()
        entries = entries.compactMap { entry in
            guard let updated = frames[entry.windowID] else { return nil }
            return HintEntry(
                hint: entry.hint,
                candidate: entry.candidate,
                windowID: entry.windowID,
                pid: entry.pid,
                mcFrame: updated,
                title: entry.title
            )
        }
    }

    private func transformedFrames() -> [CGWindowID: CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var result: [CGWindowID: CGRect] = [:]
        for entry in raw {
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                pid_t(pidNumber.int32Value) != ownAppPID,
                let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary
            else { continue }
            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds),
                bounds.width > 1, bounds.height > 1
            else { continue }
            result[CGWindowID(windowNumber.uint32Value)] = bounds
        }
        return result
    }

    private func titleFor(_ candidate: WindowCandidate) -> String {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(candidate.axWindow, kAXTitleAttribute as CFString, &titleRef)
            == .success,
            let title = titleRef as? String
        {
            return title
        }
        return ""
    }

    private func generateHints(count: Int) -> [String] {
        let letters = Self.hintAlphabet
        if count <= letters.count {
            return letters.prefix(count).map { String($0) }
        }
        var result: [String] = []
        outer: for a in letters {
            for b in letters {
                result.append("\(a)\(b)")
                if result.count == count { break outer }
            }
        }
        return result
    }

    private func showOverlay(mode: PickerOverlayMode) {
        let screens = NSScreen.screens
        let currentDisplayIDs = Set(screens.compactMap(displayID(for:)))
        for (id, window) in overlayWindows where !currentDisplayIDs.contains(id) {
            window.close()
            overlayWindows.removeValue(forKey: id)
        }

        for screen in screens {
            guard let id = displayID(for: screen) else { continue }
            let window = overlayWindows[id] ?? makeOverlayWindow(for: screen, displayID: id)
            overlayWindows[id] = window
            window.update(entries: entries, mode: mode, screen: screen)
            window.orderFrontRegardless()
        }
    }

    private func hideOverlay() {
        for window in overlayWindows.values { window.orderOut(nil) }
    }

    private func makeOverlayWindow(for screen: NSScreen, displayID: CGDirectDisplayID)
        -> PickerOverlayWindow
    {
        PickerOverlayWindow(screen: screen, displayID: displayID)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    func handleKey(_ event: CGEvent) -> CGEvent? {
        if event.type == .leftMouseDown {
            switch state {
            case .idle, .waitingForLayout: return event
            default:
                tearDown(closeOverview: false)
                return event
            }
        }
        guard event.type == .keyDown else { return event }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch state {
        case .idle, .waitingForLayout:
            return event
        case .hint(let prefix):
            return handleHintKey(prefix: prefix, keyCode: keyCode, event: event)
        case .search(let query):
            return handleSearchKey(query: query, keyCode: keyCode, event: event)
        }
    }

    private func handleHintKey(prefix: String, keyCode: Int, event: CGEvent) -> CGEvent? {
        if keyCode == kVK_Escape {
            tearDown(closeOverview: true)
            return nil
        }
        if keyCode == kVK_Delete {
            guard !prefix.isEmpty else { return nil }
            let newPrefix = String(prefix.dropLast())
            state = .hint(prefix: newPrefix)
            showOverlay(mode: .hint(prefix: newPrefix))
            return nil
        }
        let char = characterFor(event: event)

        if char == "/" {
            refreshFrames()
            state = .search(query: "")
            showOverlay(mode: .search(query: ""))
            return nil
        }

        guard let char, Self.hintAlphabet.contains(char) else {
            return event
        }

        let newPrefix = prefix + String(char)
        let matches = entries.filter { $0.hint.hasPrefix(newPrefix) }

        if matches.count == 1, matches[0].hint == newPrefix {
            commit(matches[0])
            return nil
        }
        if matches.isEmpty {
            return nil
        }
        state = .hint(prefix: newPrefix)
        showOverlay(mode: .hint(prefix: newPrefix))
        return nil
    }

    private func handleSearchKey(query: String, keyCode: Int, event: CGEvent) -> CGEvent? {
        if keyCode == kVK_Escape {
            state = .hint(prefix: "")
            showOverlay(mode: .hint(prefix: ""))
            return nil
        }
        if keyCode == kVK_Delete {
            let newQuery = String(query.dropLast())
            state = .search(query: newQuery)
            showOverlay(mode: .search(query: newQuery))
            return nil
        }
        if keyCode == kVK_Return {
            let matches = entries.filter {
                $0.title.range(of: query, options: .caseInsensitive) != nil
            }
            if matches.count == 1 { commit(matches[0]) }
            return nil
        }

        guard let char = characterFor(event: event), char.isASCII, !char.isNewline else {
            return event
        }
        let newQuery = query + String(char)
        state = .search(query: newQuery)
        showOverlay(mode: .search(query: newQuery))
        return nil
    }

    private func characterFor(event: CGEvent) -> Character? {
        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: &chars)
        guard actualLength > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: actualLength)
        return s.first
    }

    private func commit(_ entry: HintEntry) {
        if let candidate = entry.candidate {
            tearDown(closeOverview: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickPostDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    _ = self?.windowFocusService.focus(candidate)
                }
            }
        } else {
            navigateAndFocus(windowID: entry.windowID, pid: entry.pid)
        }
    }

    private func navigateAndFocus(windowID: CGWindowID, pid: pid_t) {
        guard let swipe = computeSwipe(for: windowID) else {
            tearDown(closeOverview: true)
            return
        }

        tearDown(closeOverview: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if swipe.count > 0 {
                    self.workspaceSwitcher.move(
                        swipe.direction, count: swipe.count, velocity: WorkspaceSwitcher.instantVelocity
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Task { @MainActor [weak self] in
                        self?.focusAfterSwipe(windowID: windowID, pid: pid)
                    }
                }
            }
        }
    }

    private func focusAfterSwipe(windowID: CGWindowID, pid: pid_t) {
        let candidates = windowDiscoveryService.discoverCandidates()
        if let match = candidates.first(where: { $0.windowID == windowID }) {
            _ = windowFocusService.focus(match)
            return
        }
        if let match = candidates.first(where: { $0.pid == pid }) {
            _ = windowFocusService.focus(match)
        }
    }

    private func computeSwipe(for windowID: CGWindowID) -> (direction: WorkspaceMove, count: Int)? {
        guard
            let mainConnection = slsMainConnectionID,
            let getActiveSpace = slsGetActiveSpace,
            let copyDisplaySpaces = slsCopyManagedDisplaySpaces,
            let copySpacesForWindows = slsCopySpacesForWindows
        else { return nil }

        let cid = mainConnection()
        let currentSpace = getActiveSpace(cid)

        let windowList = [windowID] as CFArray
        guard let unmanagedSpaces = copySpacesForWindows(cid, 0x7, windowList) else { return nil }
        let spacesForWindow = unmanagedSpaces.takeRetainedValue() as? [NSNumber] ?? []
        guard let targetSpace = spacesForWindow.first?.uint64Value else { return nil }
        if targetSpace == currentSpace { return (.next, 0) }

        guard let unmanagedDisplays = copyDisplaySpaces(cid) else { return nil }
        let displays = unmanagedDisplays.takeRetainedValue() as? [[String: Any]] ?? []

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids: [UInt64] = spaces.compactMap {
                ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value
                    ?? ($0["id64"] as? NSNumber)?.uint64Value
            }
            guard
                let currentIdx = ids.firstIndex(of: currentSpace),
                let targetIdx = ids.firstIndex(of: targetSpace)
            else { continue }
            let delta = targetIdx - currentIdx
            if delta == 0 { return (.next, 0) }
            return (delta > 0 ? .next : .previous, abs(delta))
        }
        return nil
    }

    private func cancel() {
        tearDown(closeOverview: true)
    }

    private func tearDown(closeOverview: Bool) {
        pendingStart?.cancel()
        pendingStart = nil
        removeEventTap()
        hideOverlay()
        entries = []
        if closeOverview {
            sendCloseNotification()
        }
        activeMode = nil
        capturedFrontPID = nil
        state = .idle
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: pickerEventTapCallback,
                userInfo: userInfo
            )
        else {
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    enum State {
        case idle
        case waitingForLayout(snapshot: [WindowCandidate])
        case hint(prefix: String)
        case search(query: String)
    }
}

struct HintEntry {
    let hint: String
    let candidate: WindowCandidate?
    let windowID: CGWindowID
    let pid: pid_t
    let mcFrame: CGRect
    let title: String
}

enum PickerOverlayMode {
    case hint(prefix: String)
    case search(query: String)
}

private let pickerEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let picker = Unmanaged<OverviewPicker>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }

    let result = MainActor.assumeIsolated { picker.handleKey(event) }
    if let result {
        return Unmanaged.passUnretained(result)
    }
    return nil
}
