//
//  PreviewWindowController.swift
//  SafariMRU
//
//  A borderless, non-activating overlay that shows tab previews (favicon +
//  title) while cycling, with the current selection highlighted.
//

import Cocoa

final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private let panel: NSPanel
    private let previewView = PreviewView()

    fileprivate static let cardWidth: CGFloat = 200
    fileprivate static let cardHeight: CGFloat = 56
    fileprivate static let gap: CGFloat = 10
    fileprivate static let margin: CGFloat = 16

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 88),
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
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2 + frame.height * 0.12
            ))
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
    var tabs: [TabPreview] = [] {
        didSet {
            favicons.removeAll()
            needsDisplay = true
            loadFavicons()
        }
    }
    var selectedIndex = 0

    private var favicons: [Int: NSImage] = [:]

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

        let bg = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.55)).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = selected ? 2.5 : 1
        (selected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.3)).setStroke()
        border.stroke()

        // Favicon
        let faviconRect = NSRect(x: rect.minX + 10, y: rect.minY + (rect.height - 28) / 2, width: 28, height: 28)
        if let favicon = favicons[index] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: faviconRect, xRadius: 6, yRadius: 6).fill()
        }

        // Title
        let title = tab.title.isEmpty ? tab.url : tab.title
        let titleRect = NSRect(x: rect.minX + 46, y: rect.minY + (rect.height - 18) / 2, width: rect.width - 54, height: 20)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: attrs)
    }

    private func loadFavicons() {
        let titles = tabs.map { $0.title }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let favicons = SafariAX.faviconDataByTitle()
            var images: [Int: NSImage] = [:]
            for (i, title) in titles.enumerated() {
                if let data = favicons[title], let img = NSImage(data: data) {
                    images[i] = img
                }
            }
            DispatchQueue.main.async {
                self?.favicons = images
                self?.needsDisplay = true
            }
        }
    }
}
