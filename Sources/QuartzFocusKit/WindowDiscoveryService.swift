import AppKit
import ApplicationServices

private struct VisibleWindowInfo {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

private struct AXWindowSnapshot {
    let element: AXUIElement
    let frame: CGRect
}

@MainActor
final class WindowDiscoveryService {
    private let frameMatchTolerance: CGFloat = 120

    func currentFocusedWindow() -> WindowCandidate? {
        guard PermissionManager.isTrusted(),
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
        else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        guard let focusedWindow = AccessibilityValue.focusedWindow(of: applicationElement),
            let frame = AccessibilityValue.frame(focusedWindow)
        else {
            return nil
        }

        let windowID =
            visibleWindowID(for: frontmostApplication.processIdentifier, matching: frame) ?? 0
        return WindowCandidate(
            pid: frontmostApplication.processIdentifier,
            windowID: windowID,
            frame: frame,
            axWindow: focusedWindow,
            screenID: screenID(for: frame)
        )
    }

    func discoverCandidates() -> [WindowCandidate] {
        guard PermissionManager.isTrusted() else {
            return []
        }

        let visibleWindows = visibleWindowInfos()
        let groupedWindows = Dictionary(grouping: visibleWindows, by: \.pid)
        var candidates: [WindowCandidate] = []

        for (pid, windows) in groupedWindows {
            let snapshots = windowSnapshots(for: pid)
            guard !snapshots.isEmpty else {
                continue
            }

            var usedIndices = Set<Int>()

            for visibleWindow in windows {
                guard
                    let matchedIndex = bestMatch(for: visibleWindow, among: snapshots, excluding: usedIndices)
                else {
                    continue
                }

                usedIndices.insert(matchedIndex)

                let snapshot = snapshots[matchedIndex]
                candidates.append(
                    WindowCandidate(
                        pid: pid,
                        windowID: visibleWindow.windowID,
                        frame: snapshot.frame,
                        axWindow: snapshot.element,
                        screenID: screenID(for: snapshot.frame)
                    )
                )
            }
        }

        return candidates
    }

    private func windowSnapshots(for pid: pid_t) -> [AXWindowSnapshot] {
        guard let runningApplication = NSRunningApplication(processIdentifier: pid),
            !runningApplication.isHidden
        else {
            return []
        }

        let applicationElement = AXUIElementCreateApplication(pid)
        guard AccessibilityValue.bool(applicationElement, kAXHiddenAttribute as CFString) != true else {
            return []
        }

        return AccessibilityValue.elements(applicationElement, kAXWindowsAttribute as CFString)
            .compactMap { windowElement in
                guard let frame = AccessibilityValue.frame(windowElement),
                    AccessibilityValue.string(windowElement, kAXRoleAttribute as CFString) == kAXWindowRole
                        as String
                else {
                    return nil
                }

                if AccessibilityValue.bool(windowElement, kAXMinimizedAttribute as CFString) == true {
                    return nil
                }

                let subrole = AccessibilityValue.string(windowElement, kAXSubroleAttribute as CFString)
                if let subrole, !subrole.isEmpty, subrole != kAXStandardWindowSubrole as String {
                    return nil
                }

                guard !isLikelyFullscreen(frame) else {
                    return nil
                }

                return AXWindowSnapshot(element: windowElement, frame: frame)
            }
    }

    private func bestMatch(
        for visibleWindow: VisibleWindowInfo,
        among snapshots: [AXWindowSnapshot],
        excluding usedIndices: Set<Int>
    ) -> Int? {
        let bestMatch = snapshots.enumerated()
            .filter { !usedIndices.contains($0.offset) }
            .map { (index: $0.offset, distance: frameDistance(visibleWindow.frame, $0.element.frame)) }
            .min { $0.distance < $1.distance }

        guard let bestMatch else {
            return nil
        }

        if bestMatch.distance <= frameMatchTolerance || snapshots.count == 1 {
            return bestMatch.index
        }

        return nil
    }

    private func visibleWindowID(for pid: pid_t, matching frame: CGRect) -> CGWindowID? {
        visibleWindowInfos()
            .filter { $0.pid == pid }
            .min { frameDistance(frame, $0.frame) < frameDistance(frame, $1.frame) }?
            .windowID
    }

    private func visibleWindowInfos() -> [VisibleWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard
            let rawWindowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return rawWindowList.compactMap { entry in
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else {
                return nil
            }

            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else {
                return nil
            }

            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary
            else {
                return nil
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds),
                bounds.width > 1,
                bounds.height > 1
            else {
                return nil
            }

            return VisibleWindowInfo(
                pid: pid_t(pidNumber.int32Value),
                windowID: CGWindowID(windowNumber.uint32Value),
                frame: bounds.standardized
            )
        }
    }
}
