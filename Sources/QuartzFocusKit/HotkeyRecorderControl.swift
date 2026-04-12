import AppKit

@MainActor
public final class HotkeyRecorderControl: NSControl {
    public var binding: HotkeyBinding? {
        didSet { needsDisplay = true }
    }

    public var onChange: ((HotkeyBinding) -> Void)?
    public var onRecordingChange: ((Bool) -> Void)?

    public private(set) var isRecording = false {
        didSet {
            needsDisplay = true
            onRecordingChange?(isRecording)
            if isRecording {
                installMonitor()
            } else {
                removeMonitor()
            }
        }
    }

    private nonisolated(unsafe) var eventMonitor: Any?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 26) }

    public override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        window?.makeFirstResponder(self)
    }

    public override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        layer?.borderColor =
            isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor

        let text: String
        let color: NSColor
        if isRecording {
            text = "Press keys…"
            color = .secondaryLabelColor
        } else if let binding {
            text = binding.displayString
            color = .labelColor
        } else {
            text = "—"
            color = .tertiaryLabelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        string.draw(at: origin)
    }

    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let isEscape = event.keyCode == 53
            let candidate = HotkeyBinding(event: event)

            MainActor.assumeIsolated {
                guard let self else { return }
                if isEscape {
                    self.isRecording = false
                } else if let candidate {
                    self.binding = candidate
                    self.onChange?(candidate)
                    self.isRecording = false
                }
            }

            return nil
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
