import QuartzFocusKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    let binding: HotkeyBinding?
    let onChange: (HotkeyBinding) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl(frame: .zero)
        control.binding = binding
        control.onChange = onChange
        control.onRecordingChange = onRecordingChange
        return control
    }

    func updateNSView(_ nsView: HotkeyRecorderControl, context: Context) {
        if nsView.binding != binding {
            nsView.binding = binding
        }
        nsView.onChange = onChange
        nsView.onRecordingChange = onRecordingChange
    }
}
