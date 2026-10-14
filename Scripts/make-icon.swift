#!/usr/bin/env swift
// Generates Resources/AppIcon.icns: a rounded blue gradient tile with the three-bar indicator motif.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns

import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("RunCatIcon-\(UUID().uuidString)")
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // macOS icon grid: the tile occupies ~80% of the canvas with a continuous corner radius.
    let inset = size * 0.1
    let tile = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.56, blue: 1.0, alpha: 1),
                                       NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.85, alpha: 1)])!
    gradient.draw(in: path, angle: -90)

    // Subtle top highlight.
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: path, angle: -90)

    // Three bars, mirroring the menu bar indicator.
    let barWidth = tile.width * 0.13
    let gap = tile.width * 0.08
    let heights: [CGFloat] = [0.38, 0.72, 0.52]
    let maxHeight = tile.height * 0.52
    let totalWidth = barWidth * 3 + gap * 2
    var x = tile.midX - totalWidth / 2
    let baseline = tile.midY - maxHeight / 2
    for h in heights {
        let track = NSBezierPath(roundedRect: NSRect(x: x, y: baseline, width: barWidth, height: maxHeight),
                                 xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor.white.withAlphaComponent(0.22).setFill()
        track.fill()
        let fill = NSBezierPath(roundedRect: NSRect(x: x, y: baseline, width: barWidth, height: maxHeight * h),
                                xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor.white.setFill()
        fill.fill()
        x += barWidth + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let rep = draw(size: CGFloat(points * scale))
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(task.terminationStatus == 0 ? "wrote \(output)" : "iconutil failed")
exit(task.terminationStatus)
