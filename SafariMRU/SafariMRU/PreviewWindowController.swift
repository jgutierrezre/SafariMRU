//
//  PreviewWindowController.swift
//  SafariMRU
//
//  A borderless, non-activating overlay that shows tab previews (thumbnail +
//  title) while cycling, with the current selection highlighted.
//

import Cocoa

final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private let panel: NSPanel
    private let previewView = PreviewView()

    fileprivate static let cardWidth: CGFloat = 200
    fileprivate static let cardHeight: CGFloat = 160
    fileprivate static let gap: CGFloat = 12
    fileprivate static let margin: CGFloat = 20

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = previewView
    }

    func show(tabs: [TabPreview], selected: Int) {
        previewView.tabs = tabs
        previewView.selectedIndex = selected
        previewView.needsDisplay = true

        let count = max(1, tabs.count)
        let width = CGFloat(count) * Self.cardWidth + CGFloat(count - 1) * Self.gap + Self.margin * 2
        let height = Self.cardHeight + Self.margin * 2
        panel.setContentSize(NSSize(width: width, height: height))

        if let screen = NSScreen.main {
            let frame = screen.frame
            let origin = NSPoint(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2 + frame.height * 0.12
            )
            panel.setFrameOrigin(origin)
        }

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class PreviewView: NSView {
    var tabs: [TabPreview] = []
    var selectedIndex = 0

    private var imageCache: [Int: NSImage] = [:]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalWidth = CGFloat(tabs.count) * PreviewWindowController.cardWidth
            + CGFloat(max(0, tabs.count - 1)) * PreviewWindowController.gap
        let startX = (bounds.width - totalWidth) / 2
        let topY = PreviewWindowController.margin

        for (i, tab) in tabs.enumerated() {
            let rect = NSRect(
                x: startX + CGFloat(i) * (PreviewWindowController.cardWidth + PreviewWindowController.gap),
                y: topY,
                width: PreviewWindowController.cardWidth,
                height: PreviewWindowController.cardHeight
            )
            drawCard(tab, index: i, in: rect)
        }
    }

    private func drawCard(_ tab: TabPreview, index: Int, in rect: NSRect) {
        let selected = index == selectedIndex

        // Background
        let bg = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let fill = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.55)
        fill.setFill()
        bg.fill()

        // Border
        let border = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        border.lineWidth = selected ? 3 : 1
        (selected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.3)).setStroke()
        border.stroke()

        // Thumbnail
        let imageRect = NSRect(
            x: rect.minX + 8,
            y: rect.minY + 8,
            width: rect.width - 16,
            height: rect.height - 36
        )
        if let image = image(for: tab, index: index) {
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: imageRect, xRadius: 6, yRadius: 6).fill()
        }

        // Title
        let title = tab.title.isEmpty ? tab.url : tab.title
        let titleRect = NSRect(
            x: rect.minX + 8,
            y: rect.maxY - 26,
            width: rect.width - 16,
            height: 20
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: attrs)
    }

    private func image(for tab: TabPreview, index: Int) -> NSImage? {
        if let cached = imageCache[index] { return cached }
        guard !tab.thumbnail.isEmpty,
              let comma = tab.thumbnail.firstIndex(of: ","),
              let data = Data(base64Encoded: String(tab.thumbnail[tab.thumbnail.index(after: comma)...])),
              let image = NSImage(data: data) else {
            return nil
        }
        imageCache[index] = image
        return image
    }
}
