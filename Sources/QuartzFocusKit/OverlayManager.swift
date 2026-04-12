import AppKit
import QuartzCore

@MainActor
final class OverlayManager {
    private var windows: [CGDirectDisplayID: FocusOverlayWindow] = [:]

    func update(focusedFrame: CGRect, state: FocusVisualState) {
        guard state.hasAnyVisual else {
            hideAll()
            return
        }

        let screens = NSScreen.screens
        let currentDisplayIDs = Set(screens.compactMap(displayID(for:)))

        for (displayID, window) in windows where !currentDisplayIDs.contains(displayID) {
            window.close()
            windows.removeValue(forKey: displayID)
        }

        for screen in screens {
            guard let currentDisplayID = displayID(for: screen) else {
                continue
            }

            let window = overlayWindow(for: screen, displayID: currentDisplayID)
            window.render(focusedFrame: focusedFrame, state: state, screenFrame: screen.frame)
            window.orderFrontRegardless()
        }
    }

    func triggerBorderFlash(duration: TimeInterval) {
        for window in windows.values {
            window.triggerBorderFlash(duration: duration)
        }
    }

    func hideAll() {
        for window in windows.values {
            window.orderOut(nil)
        }
    }

    private func overlayWindow(for screen: NSScreen, displayID: CGDirectDisplayID)
        -> FocusOverlayWindow
    {
        if let window = windows[displayID] {
            return window
        }

        let window = FocusOverlayWindow(screen: screen, displayID: displayID)
        windows[displayID] = window
        return window
    }
}

@MainActor
private final class FocusOverlayWindow: NSWindow {
    private let overlayView: FocusOverlayView
    private let displayID: CGDirectDisplayID

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.overlayView = FocusOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        backgroundColor = .clear
        level = .screenSaver
        isOpaque = false
        ignoresMouseEvents = true
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.stationary, .moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]

        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func render(focusedFrame: CGRect, state: FocusVisualState, screenFrame: CGRect) {
        if frame != screenFrame {
            setFrame(screenFrame, display: true)
        }

        overlayView.frame = CGRect(origin: .zero, size: screenFrame.size)
        overlayView.render(focusedFrame: focusedFrame, state: state, screenFrame: screenFrame)
    }

    func triggerBorderFlash(duration: TimeInterval) {
        overlayView.triggerBorderFlash(duration: duration)
    }
}

@MainActor
private final class FocusOverlayView: NSView {
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.cgColor

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineJoin = .round

        layer?.addSublayer(dimLayer)
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        dimLayer.frame = bounds
        borderLayer.frame = bounds
    }

    func render(focusedFrame globalFocusedFrame: CGRect, state: FocusVisualState, screenFrame: CGRect) {
        let paddedFocusFrame = globalFocusedFrame.insetBy(
            dx: -state.insetPadding, dy: -state.insetPadding)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let localFocusFrame = CGRect(
            x: paddedFocusFrame.minX - screenFrame.minX,
            y: primaryScreenHeight - paddedFocusFrame.maxY - screenFrame.minY,
            width: paddedFocusFrame.width,
            height: paddedFocusFrame.height
        )

        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)

        if bounds.intersects(localFocusFrame) {
            dimPath.addPath(
                CGPath(
                    roundedRect: localFocusFrame,
                    cornerWidth: state.cornerRadius,
                    cornerHeight: state.cornerRadius,
                    transform: nil
                )
            )
        }

        if state.isDimEnabled {
            dimLayer.path = dimPath
            dimLayer.fillColor = NSColor.black.withAlphaComponent(state.dimOpacity).cgColor
        } else {
            dimLayer.path = nil
        }

        let shouldDrawBorder = state.borderPolicy != .none && bounds.intersects(localFocusFrame)
        if shouldDrawBorder {
            borderLayer.path = CGPath(
                roundedRect: localFocusFrame,
                cornerWidth: state.cornerRadius,
                cornerHeight: state.cornerRadius,
                transform: nil
            )
            borderLayer.strokeColor = state.borderColor.cgColor
            borderLayer.lineWidth = state.borderWidth
        } else {
            borderLayer.path = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch state.borderPolicy {
        case .none:
            borderLayer.opacity = 0
            borderLayer.removeAnimation(forKey: "flash")
        case .alwaysOn:
            borderLayer.opacity = 1
            borderLayer.removeAnimation(forKey: "flash")
        case .flash:
            if borderLayer.animation(forKey: "flash") == nil {
                borderLayer.opacity = 0
            }
        }
        CATransaction.commit()
    }

    func triggerBorderFlash(duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.removeAnimation(forKey: "flash")
        borderLayer.opacity = 0
        CATransaction.commit()

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1.0, 1.0, 0.0]
        animation.keyTimes = [0.0, 0.25, 1.0]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeOut),
        ]
        animation.duration = duration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = true
        borderLayer.add(animation, forKey: "flash")
    }
}
