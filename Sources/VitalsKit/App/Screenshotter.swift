import AppKit
import SwiftUI

/// Renders the app's own UI to PNG files without needing Screen Recording permission.
/// Triggered by launching with `-Screenshot <directory>`; the app quits afterwards.
///
/// Views are captured from their live layer trees. That comes back empty on some displays, so
/// the panel is moved across screens until a capture has content; if none does, the panel is
/// rendered offline with `ImageRenderer`, which stubs AppKit-backed controls with placeholders.
@MainActor
enum Screenshotter {
    static func run(into directory: String, statusItem: StatusItemController, monitor: Monitor, settings: Settings) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSLog("Screenshotter: writing to \(dir.path)")

        if let button = statusItem.statusButton {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                button.appearance = NSAppearance(named: appearance)
                statusItem.refresh()
                button.layoutSubtreeIfNeeded()
                let backdrop = appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.13, alpha: 1)
                if let image = captureLayer(button), let data = composite(image, backdrop: backdrop) {
                    write(data, to: dir.appendingPathComponent("indicator-\(name).png"))
                } else {
                    NSLog("Screenshotter: indicator render failed (\(name))")
                }
            }
            button.appearance = nil
        }

        statusItem.showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            capturePanel(statusItem, monitor: monitor, settings: settings, showSettings: false, prefix: "panel", into: dir)
            statusItem.panelHost.showingSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capturePanel(statusItem, monitor: monitor, settings: settings, showSettings: true, prefix: "settings", into: dir)
                NSLog("Screenshotter: done")
                NSApp.terminate(nil)
            }
        }
    }

    private static func capturePanel(_ statusItem: StatusItemController, monitor: Monitor, settings: Settings,
                                     showSettings: Bool, prefix: String, into dir: URL) {
        let window = statusItem.panelWindow
        for (name, appearance, scheme) in [("light", NSAppearance.Name.aqua, ColorScheme.light), ("dark", .darkAqua, .dark)] {
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let backdrop = scheme == .light ? NSColor(white: 0.82, alpha: 1) : NSColor(white: 0.22, alpha: 1)

            var image: CGImage?
            if let view = window.contentView {
                image = captureLayer(view)
                if image.map(isBlank) ?? true {
                    NSLog("Screenshotter: layer render blank, trying cacheDisplay")
                    image = captureCache(view)
                }
            }
            if image.map(isBlank) ?? true {
                NSLog("Screenshotter: live capture blank, rendering \(prefix) offline (controls will be placeholders)")
                let host = PanelHost()
                host.showingSettings = showSettings
                let renderer = ImageRenderer(content: PanelRoot(monitor: monitor, settings: settings, host: host)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                image = renderer.cgImage
            }
            if let image, let data = composite(image, backdrop: backdrop) {
                write(data, to: dir.appendingPathComponent("\(prefix)-\(name).png"))
            } else {
                NSLog("Screenshotter: \(prefix) render failed (\(name))")
            }
        }
    }

    /// Renders a view's layer tree at 2x.
    private static func captureLayer(_ view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let layer = view.layer,
              let ctx = CGContext(data: nil, width: Int(bounds.width * 2), height: Int(bounds.height * 2),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: 2, y: 2)
        if layer.isGeometryFlipped || view.isFlipped {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    /// AppKit's own display cache of the view hierarchy.
    private static func captureCache(_ view: NSView) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// True when no sampled pixel has any alpha, i.e. the layer render produced nothing.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let stride = image.bytesPerRow, bpp = image.bitsPerPixel / 8
        var y = 0
        while y < image.height {
            var x = 0
            while x < image.width {
                if bytes[y * stride + x * bpp + 3] != 0 { return false }
                x += 8
            }
            y += 8
        }
        return true
    }

    /// Composites an image over a solid backdrop so translucent regions are visible.
    private static func composite(_ image: CGImage, backdrop: NSColor) -> Data? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(backdrop.usingColorSpace(.sRGB)?.cgColor ?? backdrop.cgColor)
        ctx.fill(target)
        ctx.draw(image, in: target)
        guard let result = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
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
