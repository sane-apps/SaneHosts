#!/usr/bin/swift

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

// Brand colors
let bgColorTop = NSColor(red: 0x1a/255.0, green: 0x27/255.0, blue: 0x44/255.0, alpha: 1.0)
let bgColorBottom = NSColor(red: 0x0d/255.0, green: 0x15/255.0, blue: 0x25/255.0, alpha: 1.0)
let iconColor = NSColor(red: 0x5f/255.0, green: 0xa8/255.0, blue: 0xd3/255.0, alpha: 1.0)

// SF Symbol name
let symbolName = "network.badge.shield.half.filled"

// Output directory
let outputDir = "SaneHosts/Assets.xcassets/AppIcon.appiconset"

// Required sizes: (filename, size in pixels)
let sizes: [(String, Int)] = [
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

func createIcon(px: Int) -> Data? {
    // Use NSBitmapImageRep directly to guarantee exact pixel dimensions
    // (NSImage + lockFocus doubles pixels on Retina displays)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px) // 1:1 point-to-pixel

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    // Draw gradient background
    let gradient = NSGradient(starting: bgColorTop, ending: bgColorBottom)!
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    gradient.draw(in: rect, angle: -45)

    // Get SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.55, weight: .regular)
    if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {

        // Create colored version using a temporary bitmap at 1x
        let symSize = symbolImage.size
        let colorRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(symSize.width),
            pixelsHigh: Int(symSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        colorRep.size = symSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: colorRep)
        iconColor.set()
        let symRect = NSRect(origin: .zero, size: symSize)
        symbolImage.draw(in: symRect)
        symRect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let coloredImage = NSImage(size: symSize)
        coloredImage.addRepresentation(colorRep)

        // Center the symbol in the icon
        let x = (CGFloat(px) - symSize.width) / 2
        let y = (CGFloat(px) - symSize.height) / 2

        coloredImage.draw(in: NSRect(x: x, y: y, width: symSize.width, height: symSize.height),
                         from: NSRect(origin: .zero, size: symSize),
                         operation: .sourceOver,
                         fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()

    // Flatten onto opaque CGContext (no alpha in final PNG)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let opaqueCtx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // Fill with background base color, then composite rendered icon on top
    opaqueCtx.setFillColor(CGColor(red: 0x1a/255.0, green: 0x27/255.0, blue: 0x44/255.0, alpha: 1.0))
    opaqueCtx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    if let cgImg = rep.cgImage {
        // NSBitmapImageRep is flipped (y=0 at top), CGContext is not (y=0 at bottom)
        opaqueCtx.translateBy(x: 0, y: CGFloat(px))
        opaqueCtx.scaleBy(x: 1, y: -1)
        opaqueCtx.draw(cgImg, in: CGRect(x: 0, y: 0, width: px, height: px))
    }

    guard let finalImage = opaqueCtx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: finalImage).representation(using: .png, properties: [:])
}

// Get script directory and construct output path
let scriptPath = CommandLine.arguments[0]
let projectDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().deletingLastPathComponent().path

print("Generating app icons with SF Symbol: \(symbolName)")
print("Project directory: \(projectDir)")

for (filename, size) in sizes {
    let outputPath = "\(projectDir)/\(outputDir)/\(filename)"
    if let pngData = createIcon(px: size) {
        try! pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Created: \(outputPath) (\(size)x\(size) pixels)")
    } else {
        print("Failed: \(filename)")
    }
}

print("\nDone! Generated \(sizes.count) icon files.")
