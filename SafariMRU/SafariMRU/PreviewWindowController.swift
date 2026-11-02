//
//  PreviewWindowController.swift
//  SafariMRU
//
//  A borderless, non-activating overlay that shows tab previews (index, favicon
//  and title) while cycling, with the current selection highlighted. Cards wrap
//  into a grid that is clamped to the screen so it never overflows.
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
        let layout = Self.computeLayout(count: tabs.count)
        previewView.layout = layout
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

    /// Compute a grid that fits within 92% of the screen, shrinking cards only
    /// when there are too many tabs to fit even at the minimum size.
    private static func computeLayout(count: Int) -> PreviewLayout {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = screen.width * 0.92
        let maxH = screen.height * 0.92

        let gap: CGFloat = 10
        let margin: CGFloat = 16
        var cardW: CGFloat = 200
        var cardH: CGFloat = 56

        while true {
            let cols = max(1, min(count, Int((maxW - 2 * margin + gap) / (cardW + gap))))
            let layout = PreviewLayout(columns: cols, cardWidth: cardW, cardHeight: cardH, gap: gap, margin: margin)
            let fits = layout.width(for: count) <= maxW && layout.height(for: count) <= maxH
            if fits || (cardW <= 150 && cardH <= 44) {
                return layout
            }
            cardW = max(150, cardW * 0.9)
            cardH = max(44, cardH * 0.9)
        }
    }
}

final class PreviewView: NSView {
    var layout = PreviewLayout(columns: 1, cardWidth: 200, cardHeight: 56, gap: 10, margin: 16)

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

        // Index label (left)
        let indexAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ]
        let indexStr = "\(index + 1)" as NSString
        let indexSize = indexStr.size(withAttributes: indexAttrs)
        indexStr.draw(at: NSPoint(x: rect.minX + 10, y: rect.midY - indexSize.height / 2), withAttributes: indexAttrs)

        // Favicon
        let faviconSize = min(26, rect.height - 16)
        let faviconRect = NSRect(x: rect.minX + 30, y: rect.midY - faviconSize / 2, width: faviconSize, height: faviconSize)
        if let favicon = favicons[tab.title] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: faviconRect, xRadius: 6, yRadius: 6).fill()
        }

        // Title
        let title = tab.title.isEmpty ? tab.url : tab.title
        let titleRect = NSRect(x: rect.minX + 64, y: rect.minY + (rect.height - 18) / 2, width: rect.width - 72, height: 20)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: attrs)
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
