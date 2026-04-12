import AppKit
import QuartzFocusKit
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        Text(model.permissionGranted ? "Accessibility: Granted" : "Accessibility: Required")

        Divider()

        Menu("Border") {
            Picker(
                selection: Binding(
                    get: { model.borderPolicy },
                    set: { model.setBorderPolicy($0) }
                )
            ) {
                ForEach(BorderPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }

        Toggle(
            "Dim",
            isOn: Binding(
                get: { model.isDimEnabled },
                set: { model.setDim($0) }
            ))

        Divider()

        Button("Settings…") { onOpenSettings() }
            .keyboardShortcut(",", modifiers: .command)

        if !model.permissionGranted {
            Button("Grant Accessibility Permission") {
                model.requestAccessibilityPermission()
            }
        }

        Divider()

        Button("Quit QuartzFocus") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
