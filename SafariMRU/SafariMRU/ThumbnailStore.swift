//
//  ThumbnailStore.swift
//  SafariMRU
//
//  Captures a preview of the visible Safari tab via ScreenCaptureKit, cropping
//  to the web-content area and clamping to the visible display. Cached per tab.
//  The preview overlay is excluded from the capture so it never appears in a
//  thumbnail. Requires Screen Recording permission.
//

import Cocoa
import CoreGraphics
import ScreenCaptureKit

final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]

    func image(for title: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[title]
    }

    func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Capture the currently-visible tab, cached under `title`.
    /// `delay` gives a freshly-switched tab time to render (0 for the current tab).
    func captureActiveTab(title: String, delay: TimeInterval = 0.2) {
        guard Settings.thumbnailsEnabled else { return }
        guard CGPreflightScreenCaptureAccess() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let frame = SafariAX.webContentFrame(), frame.width > 20, frame.height > 20 else { return }
            self.capture(webRect: frame, title: title)
        }
    }

    private func capture(webRect: CGRect, title: String) {
        // Read the preview window id on the calling (main) thread — creating the
        // NSPanel off the main thread would crash.
        let previewWindowID = PreviewWindowController.shared.windowNumber

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let center = CGPoint(x: webRect.midX, y: webRect.minY + 10)
                guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
                    return
                }

                // The AX web area reports the full scrollable content height (often
                // far taller than the screen). Clamp to the visible display area.
                let visible = webRect.intersection(display.frame)
                guard visible.width > 20, visible.height > 20 else { return }

                // Exclude our own preview overlay so it never appears in a thumbnail.
                let excluding = content.windows.filter { Int($0.windowID) == previewWindowID }
                let filter = SCContentFilter(display: display, excludingWindows: excluding)

                let config = SCStreamConfiguration()
                config.showsCursor = false
                let scale = CGFloat(display.width) / max(1, display.frame.width)
                config.width = max(1, Int(visible.width * scale))
                config.height = max(1, Int(visible.height * scale))
                config.sourceRect = CGRect(
                    x: visible.minX - display.frame.minX,
                    y: visible.minY - display.frame.minY,
                    width: visible.width,
                    height: visible.height
                )

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let final = Self.downscale(image, maxWidth: 320) ?? image
                let nsImage = NSImage(cgImage: final, size: NSSize(width: final.width, height: final.height))

                self.store(nsImage, for: title)
            } catch {
                // Permission not granted or capture failed; skip.
            }
        }
    }

    private func store(_ image: NSImage, for title: String) {
        lock.lock()
        cache[title] = image
        lock.unlock()
    }

    private static func downscale(_ cg: CGImage, maxWidth: Int) -> CGImage? {
        if cg.width <= maxWidth { return cg }
        let scale = Double(maxWidth) / Double(cg.width)
        let w = maxWidth
        let h = max(1, Int(Double(cg.height) * scale))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
