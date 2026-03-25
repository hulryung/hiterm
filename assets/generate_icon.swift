#!/usr/bin/env swift

import AppKit
import Foundation

let size = 1024
let nsSize = NSSize(width: size, height: size)

let image = NSImage(size: nsSize, flipped: false) { rect in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // --- Background: dark terminal-style rounded rect ---
    let cornerRadius: CGFloat = CGFloat(size) * 0.22 // macOS squircle-ish
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient: dark charcoal to slightly lighter
    let gradient = NSGradient(
        starting: NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
        ending: NSColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: -45)

    // --- Subtle border ---
    let borderColor = NSColor(white: 1.0, alpha: 0.08)
    borderColor.setStroke()
    bgPath.lineWidth = 4
    bgPath.stroke()

    // --- Terminal prompt ">_" ---
    let promptFont = NSFont.monospacedSystemFont(ofSize: CGFloat(size) * 0.22, weight: .bold)
    let promptAttrs: [NSAttributedString.Key: Any] = [
        .font: promptFont,
        .foregroundColor: NSColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 0.85)
    ]
    let promptStr = NSAttributedString(string: ">_", attributes: promptAttrs)
    let promptSize = promptStr.size()
    let promptX = CGFloat(size) * 0.12
    let promptY = CGFloat(size) * 0.12
    promptStr.draw(at: NSPoint(x: promptX, y: promptY))

    // --- Waving hand emoji ---
    let emojiFont = NSFont.systemFont(ofSize: CGFloat(size) * 0.48)
    let emojiAttrs: [NSAttributedString.Key: Any] = [
        .font: emojiFont,
    ]
    let emojiStr = NSAttributedString(string: "👋", attributes: emojiAttrs)
    let emojiSize = emojiStr.size()
    let emojiX = (CGFloat(size) - emojiSize.width) / 2 + CGFloat(size) * 0.08
    let emojiY = (CGFloat(size) - emojiSize.height) / 2 + CGFloat(size) * 0.08
    emojiStr.draw(at: NSPoint(x: emojiX, y: emojiY))

    return true
}

// Export as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon saved to \(outputPath)")
