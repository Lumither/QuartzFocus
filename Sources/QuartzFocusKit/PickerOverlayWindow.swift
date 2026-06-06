import AppKit
import QuartzCore

@MainActor
final class PickerOverlayWindow: NSWindow {
    private let overlayView: PickerOverlayView
    private let displayID: CGDirectDisplayID

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.overlayView = PickerOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(entries: [HintEntry], mode: PickerOverlayMode, screen: NSScreen) {
        if frame != screen.frame { setFrame(screen.frame, display: true) }
        overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
        overlayView.update(entries: entries, mode: mode, screen: screen)
    }
}

@MainActor
private final class PickerOverlayView: NSView {
    private let dimLayer = CAShapeLayer()
    private let hintsLayer = CALayer()
    private let searchBarLayer = CATextLayer()
    private let searchBackdropLayer = CALayer()
    private var hintLabelLayers: [CALayer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.55).cgColor

        searchBackdropLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        searchBackdropLayer.cornerRadius = 8

        searchBarLayer.foregroundColor = NSColor.white.cgColor
        searchBarLayer.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        searchBarLayer.fontSize = 18
        searchBarLayer.alignmentMode = .left
        searchBarLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        layer?.addSublayer(dimLayer)
        layer?.addSublayer(hintsLayer)
        layer?.addSublayer(searchBackdropLayer)
        layer?.addSublayer(searchBarLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(entries: [HintEntry], mode: PickerOverlayMode, screen: NSScreen) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        clearHintLabels()

        switch mode {
        case .hint(let prefix):
            dimLayer.path = nil
            searchBackdropLayer.isHidden = true
            searchBarLayer.isHidden = true
            renderHints(entries: entries, prefix: prefix, screen: screen)
        case .search(let query):
            renderSearchDim(entries: entries, query: query, screen: screen)
            renderSearchBar(query: query, screen: screen)
        }
    }

    private func clearHintLabels() {
        for layer in hintLabelLayers { layer.removeFromSuperlayer() }
        hintLabelLayers.removeAll()
    }

    private func renderHints(entries: [HintEntry], prefix: String, screen: NSScreen) {
        for entry in entries {
            guard entry.hint.hasPrefix(prefix) else { continue }
            guard
                let pos = local(point: CGPoint(x: entry.mcFrame.midX, y: entry.mcFrame.midY), screen: screen)
            else { continue }
            let label = makeHintLabel(text: entry.hint, prefix: prefix)
            let labelSize = label.bounds.size
            label.frame = CGRect(
                x: pos.x - labelSize.width / 2,
                y: pos.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            hintsLayer.addSublayer(label)
            hintLabelLayers.append(label)
        }
    }

    private func makeHintLabel(text: String, prefix: String) -> CALayer {
        let container = CALayer()
        let font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 8
        container.frame = CGRect(
            x: 0, y: 0,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        container.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.cornerRadius = 6
        container.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        container.borderWidth = 1.5

        let textLayer = CATextLayer()
        textLayer.string = attributedHintString(text: text, prefix: prefix, font: font)
        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.frame = CGRect(
            x: padding, y: padding / 2,
            width: size.width, height: size.height
        )
        container.addSublayer(textLayer)
        return container
    }

    private func attributedHintString(text: String, prefix: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let matchedColor = NSColor(srgbRed: 0.50, green: 0.80, blue: 0.50, alpha: 1.0)
        let remainingColor = NSColor.white
        for (i, ch) in text.enumerated() {
            let color = i < prefix.count ? matchedColor : remainingColor
            result.append(
                NSAttributedString(
                    string: String(ch),
                    attributes: [
                        .font: font, .foregroundColor: color,
                    ]))
        }
        return result
    }

    private func renderSearchDim(entries: [HintEntry], query: String, screen: NSScreen) {
        let path = CGMutablePath()
        path.addRect(bounds)
        for entry in entries {
            guard !query.isEmpty,
                entry.title.range(of: query, options: .caseInsensitive) != nil
            else { continue }
            guard let localFrame = local(rect: entry.mcFrame, screen: screen) else { continue }
            path.addPath(CGPath(roundedRect: localFrame, cornerWidth: 10, cornerHeight: 10, transform: nil))
        }
        dimLayer.path = path
    }

    private func renderSearchBar(query: String, screen: NSScreen) {
        searchBackdropLayer.isHidden = false
        searchBarLayer.isHidden = false
        let displayText = "/\(query)"
        searchBarLayer.string = displayText

        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        let size = (displayText as NSString).size(withAttributes: [.font: font])
        let padding: CGFloat = 12
        let backdropWidth = max(size.width + padding * 2, 200)
        let backdropHeight = size.height + padding
        let originX = (bounds.width - backdropWidth) / 2
        let originY: CGFloat = bounds.height - backdropHeight - 60

        searchBackdropLayer.frame = CGRect(
            x: originX, y: originY, width: backdropWidth, height: backdropHeight)
        searchBarLayer.frame = CGRect(
            x: originX + padding, y: originY + padding / 2,
            width: backdropWidth - padding * 2, height: size.height
        )
    }

    private func primaryScreenHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? bounds.height
    }

    private func local(point: CGPoint, screen: NSScreen) -> CGPoint? {
        guard screen.frame.contains(point.flippedToAppKit(primaryHeight: primaryScreenHeight())) else {
            let cgScreen = screen.frame.cgRectInCGCoords(primaryHeight: primaryScreenHeight())
            guard cgScreen.contains(point) else { return nil }
            return localPoint(forCGPoint: point, screen: screen)
        }
        return localPoint(forCGPoint: point, screen: screen)
    }

    private func localPoint(forCGPoint cg: CGPoint, screen: NSScreen) -> CGPoint {
        let primaryH = primaryScreenHeight()
        let appKitY = primaryH - cg.y
        return CGPoint(
            x: cg.x - screen.frame.minX,
            y: appKitY - screen.frame.minY
        )
    }

    private func local(rect cgRect: CGRect, screen: NSScreen) -> CGRect? {
        let primaryH = primaryScreenHeight()
        let appKitFrame = CGRect(
            x: cgRect.minX,
            y: primaryH - cgRect.maxY,
            width: cgRect.width,
            height: cgRect.height
        )
        guard screen.frame.intersects(appKitFrame) else { return nil }
        return CGRect(
            x: appKitFrame.minX - screen.frame.minX,
            y: appKitFrame.minY - screen.frame.minY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}

private extension CGPoint {
    func flippedToAppKit(primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: x, y: primaryHeight - y)
    }
}

private extension CGRect {
    func cgRectInCGCoords(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
