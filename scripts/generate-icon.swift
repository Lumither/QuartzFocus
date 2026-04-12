#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptURL.deletingLastPathComponent()
let iconsetURL = repoRoot.appendingPathComponent("App/AppIcon.iconset")
let icnsURL = repoRoot.appendingPathComponent("App/AppIcon.icns")

func renderIcon(pixelSize: Int) -> CGImage? {
    let size = CGFloat(pixelSize)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

    guard
        let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    // Clip to a rounded-rect (squircle approximation, 18.05% corner radius matches macOS Big Sur grid).
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.18055
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(bgPath)
    context.clip()

    let topColor = CGColor(srgbRed: 0.10, green: 0.18, blue: 0.33, alpha: 1.0)
    let bottomColor = CGColor(srgbRed: 0.04, green: 0.09, blue: 0.20, alpha: 1.0)
    guard
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [topColor, bottomColor] as CFArray,
            locations: [0.0, 1.0]
        )
    else { return nil }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    let weight: NSFont.Weight = pixelSize <= 64 ? .medium : .regular
    let baseConfig = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [
        NSColor(srgbRed: 0.80, green: 0.92, blue: 1.00, alpha: 1.0)
    ])
    let mergedConfig = baseConfig.applying(paletteConfig)

    guard
        let baseSymbol = NSImage(systemSymbolName: "scope", accessibilityDescription: nil),
        let symbol = baseSymbol.withSymbolConfiguration(mergedConfig)
    else {
        return context.makeImage()
    }

    var imageRect = CGRect(origin: .zero, size: symbol.size)
    guard let symbolCGImage = symbol.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    else {
        return context.makeImage()
    }

    let symbolFraction: CGFloat = 0.72
    let maxDimension = size * symbolFraction
    let symbolWidth = CGFloat(symbolCGImage.width)
    let symbolHeight = CGFloat(symbolCGImage.height)
    let fitScale = min(maxDimension / symbolWidth, maxDimension / symbolHeight, 1.0)
    let drawWidth = symbolWidth * fitScale
    let drawHeight = symbolHeight * fitScale

    let drawRect = CGRect(
        x: (size - drawWidth) / 2,
        y: (size - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )
    context.interpolationQuality = .high
    context.draw(symbolCGImage, in: drawRect)

    return context.makeImage()
}

func writePNG(_ cgImage: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = NSSize(width: cgImage.width, height: cgImage.height)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "generate-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"]
        )
    }
    try data.write(to: url, options: .atomic)
}

do {
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    print("==> Rendering icons")
    for (name, pixels) in sizes {
        guard let image = renderIcon(pixelSize: pixels) else {
            fputs("error: failed to render \(name) at \(pixels)px\n", stderr)
            exit(1)
        }
        let outURL = iconsetURL.appendingPathComponent(name)
        try writePNG(image, to: outURL)
        print("    \(name) (\(pixels)x\(pixels))")
    }

    print("==> Building AppIcon.icns via iconutil")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()

    guard iconutil.terminationStatus == 0 else {
        fputs("error: iconutil exited with status \(iconutil.terminationStatus)\n", stderr)
        exit(Int32(iconutil.terminationStatus))
    }

    try FileManager.default.removeItem(at: iconsetURL)

    print("")
    print("Wrote: \(icnsURL.path)")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
