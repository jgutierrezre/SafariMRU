//
//  ThumbnailStore.swift
//  SafariMRU
//
//  Periodically captures the currently-visible Safari tab via ScreenCaptureKit
//  while the preview overlay is closed, so the overlay never appears in a
//  thumbnail and the current tab's preview stays reasonably fresh. Cached per
//  tab. Requires Screen Recording permission.
//

import Cocoa
import CoreGraphics
import ScreenCaptureKit

final class ThumbnailStore: @unchecked Sendable {
    static let shared = ThumbnailStore()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var timer: DispatchSourceTimer?
    private var capturing = false
    private let interval: TimeInterval = 3.0

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.performCaptureIfAllowed() }
        t.resume()
        timer = t
    }

    /// Request a capture after a short debounce (e.g. after a tab becomes active).
    func requestCapture(after delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performCaptureIfAllowed()
        }
    }

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

    private func performCaptureIfAllowed() {
        guard !capturing else { return }
        guard Settings.thumbnailsEnabled, CGPreflightScreenCaptureAccess() else { return }
        guard !PreviewWindowController.shared.isVisible else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari" else { return }
        guard let title = MRUTracker.shared.currentActiveTitle,
              let frame = SafariAX.webContentFrame(), frame.width > 20, frame.height > 20 else {
            return
        }
        capturing = true
        capture(webRect: frame, title: title)
    }

    private func capture(webRect: CGRect, title: String) {
        // Read the preview window id on the main thread — creating the NSPanel
        // off the main thread would crash.
        let previewWindowID = PreviewWindowController.shared.windowNumber

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let center = CGPoint(x: webRect.midX, y: webRect.minY + 10)
                guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
                    self.finishCapture()
                    return
                }

                // The AX web area reports the full scrollable content height; clamp
                // to the visible display area.
                let visible = webRect.intersection(display.frame)
                guard visible.width > 20, visible.height > 20 else {
                    self.finishCapture()
                    return
                }

                // Belt-and-suspenders: never include our own preview overlay.
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
                DispatchQueue.main.async {
                    self.capturing = false
                    PreviewWindowController.shared.refresh()
                }
            } catch {
                self.finishCapture()
            }
        }
    }

    private func store(_ image: NSImage, for title: String) {
        lock.lock()
        cache[title] = image
        lock.unlock()
    }

    private func finishCapture() {
        DispatchQueue.main.async {
            self.capturing = false
        }
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
