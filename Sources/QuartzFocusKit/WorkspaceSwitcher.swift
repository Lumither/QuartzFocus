import CoreGraphics
import Foundation

@_silgen_name("CGEventSetIntegerValueField")
private func CGEventSetIntegerValueFieldRaw(_ event: CGEvent, _ field: UInt32, _ value: Int64)

@_silgen_name("CGEventSetDoubleValueField")
private func CGEventSetDoubleValueFieldRaw(_ event: CGEvent, _ field: UInt32, _ value: Double)

private enum DockSwipe {
    static let eventTypeField: UInt32 = 55
    static let gestureHIDTypeField: UInt32 = 110
    static let swipeMotionField: UInt32 = 123
    static let swipeProgressField: UInt32 = 124
    static let swipeVelocityXField: UInt32 = 129
    static let phaseField: UInt32 = 132

    static let dockControlEventType: Int64 = 30
    static let dockSwipeHIDType: Int64 = 23
    static let horizontalMotion: Int64 = 1
    static let phaseBegan: Int64 = 1
    static let phaseEnded: Int64 = 4

    static let velocityMagnitude: Double = 20.0
}

final class WorkspaceSwitcher {
    static let instantVelocity: Double = 9999.0

    func move(_ direction: WorkspaceMove, count: Int = 1, velocity: Double? = nil) {
        guard count > 0 else { return }
        let sign: Double = direction == .next ? 1.0 : -1.0
        let velocityMagnitude = velocity ?? DockSwipe.velocityMagnitude

        guard let event = CGEvent(source: nil) else {
            fputs("WorkspaceSwitcher: failed to create CGEvent\n", stderr)
            return
        }

        CGEventSetIntegerValueFieldRaw(event, DockSwipe.eventTypeField, DockSwipe.dockControlEventType)
        CGEventSetIntegerValueFieldRaw(event, DockSwipe.gestureHIDTypeField, DockSwipe.dockSwipeHIDType)
        CGEventSetIntegerValueFieldRaw(event, DockSwipe.swipeMotionField, DockSwipe.horizontalMotion)
        CGEventSetDoubleValueFieldRaw(event, DockSwipe.swipeProgressField, sign)
        CGEventSetDoubleValueFieldRaw(event, DockSwipe.swipeVelocityXField, sign * velocityMagnitude)

        for _ in 0..<count {
            CGEventSetIntegerValueFieldRaw(event, DockSwipe.phaseField, DockSwipe.phaseBegan)
            event.post(tap: .cgSessionEventTap)
            CGEventSetIntegerValueFieldRaw(event, DockSwipe.phaseField, DockSwipe.phaseEnded)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
