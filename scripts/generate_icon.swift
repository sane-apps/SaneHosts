#!/usr/bin/swift

import AppKit

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

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Draw gradient background
    let gradient = NSGradient(starting: bgColorTop, ending: bgColorBottom)!
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    gradient.draw(in: rect, angle: -45)

    // Get SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.55, weight: .regular)
    if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {

        // Create colored version
        let coloredImage = NSImage(size: symbolImage.size)
        coloredImage.lockFocus()
        iconColor.set()
        let imageRect = NSRect(origin: .zero, size: symbolImage.size)
        symbolImage.draw(in: imageRect)
        imageRect.fill(using: .sourceAtop)
        coloredImage.unlockFocus()

        // Center the symbol
        let symbolSize = coloredImage.size
        let x = (CGFloat(size) - symbolSize.width) / 2
        let y = (CGFloat(size) - symbolSize.height) / 2

        coloredImage.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                         from: NSRect(origin: .zero, size: symbolSize),
                         operation: .sourceOver,
                         fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

// Get script directory and construct output path
let scriptPath = CommandLine.arguments[0]
let projectDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().deletingLastPathComponent().path

print("Generating app icons with SF Symbol: \(symbolName)")
print("Project directory: \(projectDir)")

for (filename, size) in sizes {
    let icon = createIcon(size: size)
    let outputPath = "\(projectDir)/\(outputDir)/\(filename)"
    savePNG(image: icon, to: outputPath)
}

print("\nDone! Generated \(sizes.count) icon files.")
