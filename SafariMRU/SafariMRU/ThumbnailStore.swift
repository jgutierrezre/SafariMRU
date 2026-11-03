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
import CoreImage
import ScreenCaptureKit

final class ThumbnailStore: @unchecked Sendable {
    static let shared = ThumbnailStore()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var timer: DispatchSourceTimer?
    private var capturing = false
    private var warnedAboutScreenRecording = false
    private let interval: TimeInterval = 3.0

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.performCaptureIfAllowed() }
        t.resume()
        timer = t

        // Thumbnails are already enabled but the grant was lost (e.g. the app
        // was updated or the permission was removed). Ask again once per launch.
        if Settings.thumbnailsEnabled && !CGPreflightScreenCaptureAccess() {
            requestScreenRecordingAccess()
        }
    }

    /// Ask for Screen Recording and make a real ScreenCaptureKit call. The
    /// prompt alone does not always add the app to the privacy list — only an
    /// actual capture attempt does.
    func requestScreenRecordingAccess() {
        // The system only adds an app to the Screen Recording list when it is
        // active and actually attempts a capture.
        NSApp.activate(ignoringOtherApps: true)
        CGRequestScreenCaptureAccess()
        Task.detached(priority: .utility) {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }

        // On macOS 27 the request alone does not reliably add the app to the
        // privacy list, so if the permission is still missing, tell the user
        // exactly where to add it instead of silently showing no thumbnails.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self,
                  Settings.thumbnailsEnabled,
                  !CGPreflightScreenCaptureAccess(),
                  !self.warnedAboutScreenRecording else { return }
            self.warnedAboutScreenRecording = true
            self.showScreenRecordingAlert()
        }
    }

    private func showScreenRecordingAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            Tab thumbnails need Screen Recording access.

            Open System Settings → Privacy & Security → Screen & Audio Recording, \
            enable Safari MRU (or add it with “+”), then quit and reopen Safari MRU.
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Request a capture after a short debounce (e.g. after a tab becomes active).
    func requestCapture(after delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performCaptureIfAllowed()
        }
    }

    /// Capture right away when a tab becomes active, then again once it has
    /// settled (catches late paints). Both skip if the preview is open.
    func captureAfterActivation() {
        requestCapture(after: 0.05)
        requestCapture(after: 0.5)
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

                // SCScreenshotManager is macOS 14+; fall back to a one-frame
                // SCStream capture on Ventura.
                let image: CGImage
                if #available(macOS 14.0, *) {
                    image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                } else {
                    // The stream path does not reliably honour sourceRect, so
                    // take the whole display and crop the page area ourselves.
                    let fullConfig = SCStreamConfiguration()
                    fullConfig.showsCursor = false
                    fullConfig.width = display.width
                    fullConfig.height = display.height
                    let full = try await Self.captureSingleFrame(filter: filter, configuration: fullConfig)
                    image = Self.crop(full, displayFrame: display.frame, to: visible) ?? full
                }
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

    /// One-shot capture for macOS 13, where `SCScreenshotManager` is not
    /// available: start an `SCStream`, grab the first frame, stop it again.
    @available(macOS 12.3, *)
    private static func captureSingleFrame(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let box = FrameBox()
        try stream.addStreamOutput(box, type: .screen, sampleHandlerQueue: box.queue)
        try await stream.startCapture()

        // Give the stream up to ~1 s to deliver a frame.
        for _ in 0..<100 {
            if let image = box.captured {
                try? await stream.stopCapture()
                return image
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try? await stream.stopCapture()
        throw CaptureError.noFrame
    }

    private enum CaptureError: Error {
        case noFrame
    }

    /// Crop a full-display frame down to `visible` (both in display points).
    private static func crop(_ image: CGImage, displayFrame: CGRect, to visible: CGRect) -> CGImage? {
        let scale = CGFloat(image.width) / max(1, displayFrame.width)
        let rect = CGRect(
            x: (visible.minX - displayFrame.minX) * scale,
            y: (visible.minY - displayFrame.minY) * scale,
            width: visible.width * scale,
            height: visible.height * scale
        ).integral
        return image.cropping(to: rect)
    }

    /// Collects the first frames a stream delivers.
    @available(macOS 12.3, *)
    private final class FrameBox: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "com.jgutierrezre.SafariMRU.frames")
        private let lock = NSLock()
        private let context = CIContext()
        private var image: CGImage?

        var captured: CGImage? {
            lock.lock()
            defer { lock.unlock() }
            return image
        }

        func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of type: SCStreamOutputType
        ) {
            guard type == .screen else { return }
            lock.lock()
            let haveImage = image != nil
            lock.unlock()
            guard !haveImage, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let ci = CIImage(cvPixelBuffer: buffer)
            guard let frame = context.createCGImage(ci, from: ci.extent) else { return }
            lock.lock()
            image = frame
            lock.unlock()
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
