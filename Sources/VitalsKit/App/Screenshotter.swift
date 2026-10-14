import AppKit

/// Renders the app's own views to PNG files without needing Screen Recording permission.
/// Triggered by launching with `-Screenshot <directory>`; the app quits afterwards.
@MainActor
enum Screenshotter {
    static func run(into directory: String, statusItem: StatusItemController) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSLog("Screenshotter: writing to \(dir.path)")

        if let button = statusItem.statusButton {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                button.appearance = NSAppearance(named: appearance)
                statusItem.refresh()
                button.layoutSubtreeIfNeeded()
                let backdrop = appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.13, alpha: 1)
                if let data = render(button, backdrop: backdrop) {
                    write(data, to: dir.appendingPathComponent("indicator-\(name).png"))
                } else {
                    NSLog("Screenshotter: indicator render failed (\(name)), bounds \(button.bounds)")
                }
            }
            button.appearance = nil
        } else {
            NSLog("Screenshotter: no status button")
        }

        statusItem.showPanel()
        NSLog("Screenshotter: panel shown, visible=\(statusItem.panelWindow.isVisible) frame=\(statusItem.panelWindow.frame)")
        // Give SwiftUI a moment to lay out charts before capturing, then do the same for settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capturePanel(statusItem, prefix: "panel", into: dir)
            statusItem.panelHost.showingSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capturePanel(statusItem, prefix: "settings", into: dir)
                NSLog("Screenshotter: done")
                NSApp.terminate(nil)
            }
        }
    }

    private static func capturePanel(_ statusItem: StatusItemController, prefix: String, into dir: URL) {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let window = statusItem.panelWindow
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let backdrop = appearance == .aqua ? NSColor(white: 0.82, alpha: 1) : NSColor(white: 0.22, alpha: 1)
            if let view = window.contentView, let data = render(view, backdrop: backdrop) {
                write(data, to: dir.appendingPathComponent("\(prefix)-\(name).png"))
            } else {
                NSLog("Screenshotter: \(prefix) render failed (\(name)), bounds \(window.contentView?.bounds ?? .zero)")
            }
        }
    }

    /// Caches the view's display at 2x, then composites it over a solid backdrop with Core
    /// Graphics so translucent regions are visible in the PNG.
    private static func render(_ view: NSView, backdrop: NSColor) -> Data? {
        let bounds = view.bounds
        let scale: CGFloat = 2
        guard bounds.width > 0, bounds.height > 0, let contentImage = capture(view) else { return nil }

        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(backdrop.usingColorSpace(.sRGB)?.cgColor ?? backdrop.cgColor)
        ctx.fill(target)
        ctx.interpolationQuality = .high
        ctx.draw(contentImage, in: target)
        guard let result = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: result)
        NSLog("Screenshotter: rendered \(width)x\(height)px for \(bounds.size)")
        return rep.representation(using: .png, properties: [:])
    }

    /// Renders the view's layer tree at 2x. SwiftUI content is layer-backed, so this captures
    /// what the window shows (minus window-server effects like the glass blur).
    private static func capture(_ view: NSView) -> CGImage? {
        let bounds = view.bounds
        let scale: CGFloat = 2
        if let layer = view.layer,
           let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                               bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.scaleBy(x: scale, y: scale)
            if layer.isGeometryFlipped || view.isFlipped {
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            layer.render(in: ctx)
            if let image = ctx.makeImage() {
                NSLog("Screenshotter: layer render \(image.width)x\(image.height) (flipped: \(view.isFlipped))")
                return image
            }
        }
        NSLog("Screenshotter: layer render unavailable, using cacheDisplay")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
            NSLog("Screenshotter: wrote \(url.lastPathComponent) (\(data.count) bytes)")
        } catch {
            NSLog("Screenshotter: failed to write \(url.lastPathComponent): \(error)")
        }
    }
}
