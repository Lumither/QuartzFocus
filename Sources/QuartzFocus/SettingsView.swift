import QuartzFocusKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))

                Toggle(
                    "Show menu bar icon",
                    isOn: Binding(
                        get: { model.statusBarVisible },
                        set: { model.setStatusBarVisible($0) }
                    ))

                Toggle(
                    "Center mouse on focused window",
                    isOn: Binding(
                        get: { model.centerMouseOnFocus },
                        set: { model.setCenterMouseOnFocus($0) }
                    ))
            } header: {
                Text("General")
            }

            Section {
                Picker(
                    "Focused window border",
                    selection: Binding(
                        get: { model.borderPolicy },
                        set: { model.setBorderPolicy($0) }
                    )
                ) {
                    ForEach(BorderPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                if model.borderPolicy != .none {
                    Picker(
                        "Show border on",
                        selection: Binding(
                            get: { model.borderTrigger },
                            set: { model.setBorderTrigger($0) }
                        )
                    ) {
                        ForEach(BorderTrigger.allCases, id: \.self) { trigger in
                            Text(trigger.displayName).tag(trigger)
                        }
                    }
                }

                Toggle(
                    "Dim unfocused windows",
                    isOn: Binding(
                        get: { model.isDimEnabled },
                        set: { model.setDim($0) }
                    ))

                LabeledContent("Dim level") {
                    Slider(
                        value: Binding(
                            get: { Double(model.dimOpacity) },
                            set: { model.setDimOpacity(CGFloat($0)) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .disabled(!model.isDimEnabled)
                }
            } header: {
                Text("Visuals")
            }

            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(actionTitle(action))
                        Spacer()
                        HotkeyRecorderView(
                            binding: model.hotkeys[action],
                            onChange: { model.setHotkey(action, $0) },
                            onRecordingChange: { model.setHotkeyRecording($0) }
                        )
                        .frame(width: 160, height: 24)
                    }
                }
            } header: {
                Text("Hotkeys")
            }

            if !model.permissionGranted {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility permission required")
                                .font(.body.weight(.medium))
                            Text(
                                "QuartzFocus needs Accessibility permission to read and control window positions."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Button("Grant Accessibility Permission…") {
                                model.requestAccessibilityPermission()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionTitle(_ action: HotkeyAction) -> String {
        switch action {
        case .focusLeft: return "Focus left"
        case .focusDown: return "Focus down"
        case .focusUp: return "Focus up"
        case .focusRight: return "Focus right"
        case .workspaceNext: return "Next workspace"
        case .workspacePrevious: return "Previous workspace"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        }
    }
}
