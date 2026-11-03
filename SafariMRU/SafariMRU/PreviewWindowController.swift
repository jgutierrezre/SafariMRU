//
//  PreviewWindowController.swift
//  SafariMRU
//
//  Borderless overlay showing tab previews while cycling. Cards wrap into a
//  screen-clamped grid. With thumbnails enabled, each card shows a captured
//  page preview; otherwise a compact favicon + title layout.
//

import Cocoa

struct PreviewLayout {
    let columns: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let gap: CGFloat
    let margin: CGFloat

    func usedColumns(for count: Int) -> Int { max(1, min(columns, count)) }

    func rows(for count: Int) -> Int {
        let cols = usedColumns(for: count)
        return max(1, Int(ceil(Double(count) / Double(cols))))
    }

    func width(for count: Int) -> CGFloat {
        let cols = usedColumns(for: count)
        return CGFloat(cols) * cardWidth + CGFloat(max(0, cols - 1)) * gap + margin * 2
    }

    func height(for count: Int) -> CGFloat {
        let r = rows(for: count)
        return CGFloat(r) * cardHeight + CGFloat(max(0, r - 1)) * gap + margin * 2
    }
}

final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private let panel: NSPanel
    private let previewView = PreviewView()

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
        let thumbnails = Settings.thumbnailsEnabled
        let layout = Self.computeLayout(count: tabs.count, thumbnails: thumbnails)
        previewView.layout = layout
        previewView.showThumbnails = thumbnails
        previewView.tabs = tabs
        previewView.selectedIndex = selected
        previewView.needsDisplay = true

        let width = layout.width(for: tabs.count)
        let height = layout.height(for: tabs.count)
        panel.setContentSize(NSSize(width: width, height: height))

        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.midY - height / 2))

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private static func computeLayout(count: Int, thumbnails: Bool) -> PreviewLayout {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = screen.width * 0.92
        let maxH = screen.height * 0.92

        let gap: CGFloat = 10
        let margin: CGFloat = 16
        var cardW: CGFloat = thumbnails ? 180 : 200
        var cardH: CGFloat = thumbnails ? 150 : 56

        while true {
            let cols = max(1, min(count, Int((maxW - 2 * margin + gap) / (cardW + gap))))
            let layout = PreviewLayout(columns: cols, cardWidth: cardW, cardHeight: cardH, gap: gap, margin: margin)
            let fits = layout.width(for: count) <= maxW && layout.height(for: count) <= maxH
            if fits || (cardW <= 130 && cardH <= 60) {
                return layout
            }
            cardW = max(130, cardW * 0.9)
            cardH = max(60, cardH * 0.9)
        }
    }
}

final class PreviewView: NSView {
    var layout = PreviewLayout(columns: 1, cardWidth: 200, cardHeight: 56, gap: 10, margin: 16)
    var showThumbnails = false
    var tabs: [TabPreview] = [] {
        didSet {
            needsDisplay = true
            loadMissingFavicons()
        }
    }
    var selectedIndex = 0

    private var favicons: [String: NSImage] = [:]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cols = layout.usedColumns(for: tabs.count)
        let rows = layout.rows(for: tabs.count)
        let totalW = CGFloat(cols) * layout.cardWidth + CGFloat(max(0, cols - 1)) * layout.gap
        let totalH = CGFloat(rows) * layout.cardHeight + CGFloat(max(0, rows - 1)) * layout.gap
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        for (i, tab) in tabs.enumerated() {
            let row = i / cols
            let col = i % cols
            let rect = NSRect(
                x: startX + CGFloat(col) * (layout.cardWidth + layout.gap),
                y: startY + CGFloat(row) * (layout.cardHeight + layout.gap),
                width: layout.cardWidth,
                height: layout.cardHeight
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

        if showThumbnails {
            drawThumbnailCard(tab, index: index, in: rect)
        } else {
            drawCompactCard(tab, index: index, in: rect)
        }
    }

    private func drawThumbnailCard(_ tab: TabPreview, index: Int, in rect: NSRect) {
        let thumbRect = NSRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: rect.height - 42)

        if let thumb = ThumbnailStore.shared.image(for: tab.title) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: thumbRect, xRadius: 6, yRadius: 6).addClip()
            // Aspect-fill: scale to cover the thumbnail area, then clip the overflow.
            let iw = max(1, thumb.size.width)
            let ih = max(1, thumb.size.height)
            let scale = max(thumbRect.width / iw, thumbRect.height / ih)
            let dw = iw * scale
            let dh = ih * scale
            let dest = NSRect(x: thumbRect.midX - dw / 2, y: thumbRect.midY - dh / 2, width: dw, height: dh)
            thumb.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else if let favicon = favicons[tab.title] {
            let s: CGFloat = 44
            let r = NSRect(x: thumbRect.midX - s / 2, y: thumbRect.midY - s / 2, width: s, height: s)
            favicon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: thumbRect, xRadius: 6, yRadius: 6).fill()
        }

        // Bottom row: index + favicon + title
        let rowY = rect.maxY - 30
        drawIndex(index, x: rect.minX + 10, centerY: rowY + 12)

        let faviconSize: CGFloat = 16
        let faviconRect = NSRect(x: rect.minX + 24, y: rowY + 4, width: faviconSize, height: faviconSize)
        if let favicon = favicons[tab.title] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        drawTitle(tab, x: rect.minX + 46, y: rowY + 2, width: rect.width - 54)
    }

    private func drawCompactCard(_ tab: TabPreview, index: Int, in rect: NSRect) {
        drawIndex(index, x: rect.minX + 10, centerY: rect.midY)

        let faviconSize = min(26, rect.height - 16)
        let faviconRect = NSRect(x: rect.minX + 30, y: rect.midY - faviconSize / 2, width: faviconSize, height: faviconSize)
        if let favicon = favicons[tab.title] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: faviconRect, xRadius: 6, yRadius: 6).fill()
        }

        drawTitle(tab, x: rect.minX + 64, y: rect.minY + (rect.height - 18) / 2, width: rect.width - 72)
    }

    private func drawIndex(_ index: Int, x: CGFloat, centerY: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ]
        let str = "\(index + 1)" as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: x, y: centerY - size.height / 2), withAttributes: attrs)
    }

    private func drawTitle(_ tab: TabPreview, x: CGFloat, y: CGFloat, width: CGFloat) {
        let title = tab.title.isEmpty ? tab.url : tab.title
        let rect = NSRect(x: x, y: y, width: width, height: 20)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func loadMissingFavicons() {
        let missing = tabs.map { $0.title }.filter { !$0.isEmpty && favicons[$0] == nil }
        guard !missing.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let all = SafariAX.faviconDataByTitle()
            var loaded: [String: NSImage] = [:]
            for title in missing {
                if let data = all[title], let img = NSImage(data: data) {
                    loaded[title] = img
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (title, img) in loaded { self.favicons[title] = img }
                self.needsDisplay = true
            }
        }
    }
}
