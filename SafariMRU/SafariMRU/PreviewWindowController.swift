//
//  PreviewWindowController.swift
//  SafariMRU
//
//  Borderless overlay showing tab previews while cycling. Cards wrap into a
//  screen-clamped grid. With thumbnails enabled, each card shows a captured
//  page preview; otherwise a compact favicon + title layout. Cards are clickable.
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

    var windowNumber: Int { panel.windowNumber }
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar so the whole screen is covered and no pointer
        // event reaches the app underneath while the switcher is open.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = previewView

        previewView.onCardClicked = { index in
            MRUSwitcher.shared.commitToIndex(index)
        }
        previewView.onOutsideClick = {
            MRUSwitcher.shared.cancel()
        }
    }

    func show(tabs: [TabPreview], selected: Int) {
        let thumbnails = Settings.thumbnailsEnabled
        let layout = Self.computeLayout(count: tabs.count, thumbnails: thumbnails)
        previewView.layout = layout
        previewView.showThumbnails = thumbnails
        previewView.tabs = tabs
        previewView.selectedIndex = selected
        previewView.needsDisplay = true

        // Cover the entire screen: the overlay owns the pointer while visible,
        // so hovering/clicking cannot interact with the app behind it.
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(screenFrame, display: true)

        if !panel.isVisible {
            panel.orderFront(nil)
            // The pointer may be resting on an interactive element. Nudge one
            // mouse-move so the app underneath gets its mouse-exited and the
            // cursor is recomputed for the overlay.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.panel.isVisible else { return }
                guard let location = CGEvent(source: nil)?.location else { return }
                self.pointerMoved(to: self.cocoaPoint(fromCG: location))
                // A real (1 px) move is required: macOS only re-evaluates the
                // window under the cursor when the pointer moves, which is what
                // clears the previous app's hover and applies our cursor rects.
                self.postNudge(at: CGPoint(x: location.x + 1, y: location.y))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    guard let self = self, self.panel.isVisible else { return }
                    self.postNudge(at: location)
                }
            }
        }
    }

    func hide() {
        previewView.updateHover(at: nil)
        NSCursor.arrow.set()
        panel.orderOut(nil)
    }

    /// Pointer tracking is driven by the event tap, so the background app
    /// never sees mouse moves while the overlay is open.
    func pointerMoved(to screenPoint: NSPoint) {
        guard panel.isVisible else { return }
        let point = viewPoint(for: screenPoint)
        previewView.updateHover(at: point)
        if previewView.cardIndex(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// A click while the overlay is open: a card switches to that tab,
    /// anywhere else dismisses the switcher. The tap swallows the event.
    func click(at screenPoint: NSPoint) {
        guard panel.isVisible else { return }
        let point = viewPoint(for: screenPoint)
        if let index = previewView.cardIndex(at: point) {
            MRUSwitcher.shared.commitToIndex(index)
        } else {
            MRUSwitcher.shared.cancel()
        }
    }


    /// A synthetic move the tap lets through (marked) so the window server
    /// recomputes the window under the pointer.
    private func postNudge(at point: CGPoint) {
        guard let nudge = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        nudge.setIntegerValueField(.eventSourceUserData, value: ShortcutInterceptor.overlayNudgeMarker)
        nudge.post(tap: .cghidEventTap)
    }

    private func cocoaPoint(fromCG location: CGPoint) -> NSPoint {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        return NSPoint(x: location.x, y: (primary?.frame.maxY ?? 0) - location.y)
    }

    private func viewPoint(for screenPoint: NSPoint) -> NSPoint {
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        return previewView.convert(windowPoint, from: nil)
    }

    func refresh() {
        guard panel.isVisible else { return }
        previewView.needsDisplay = true
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

    var onCardClicked: ((Int) -> Void)?
    var onOutsideClick: (() -> Void)?

    private var favicons: [String: NSImage] = [:]
    private var cardRects: [(index: Int, rect: NSRect)] = []
    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// Cursor rects work for an inactive window, so they back up the manual
    /// cursor updates while the switcher owns the pointer.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        for entry in cardRects {
            addCursorRect(entry.rect, cursor: .pointingHand)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        if hoveredIndex != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Index of the card under `point` (view coordinates), if any.
    func cardIndex(at point: NSPoint) -> Int? {
        cardRects.first(where: { $0.rect.contains(point) })?.index
    }

    /// Update the hover highlight for a point in view coordinates.
    func updateHover(at point: NSPoint?) {
        let idx = point.flatMap { cardIndex(at: $0) }
        if idx != hoveredIndex {
            hoveredIndex = idx
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
        }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in cardRects where rect.contains(point) {
            onCardClicked?(index)
            return
        }
        // Click on the backdrop: dismiss the switcher.
        onOutsideClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cols = layout.usedColumns(for: tabs.count)
        let rows = layout.rows(for: tabs.count)
        let totalW = CGFloat(cols) * layout.cardWidth + CGFloat(max(0, cols - 1)) * layout.gap
        let totalH = CGFloat(rows) * layout.cardHeight + CGFloat(max(0, rows - 1)) * layout.gap
        let startX = (bounds.width - totalW) / 2
        let startY = (bounds.height - totalH) / 2

        cardRects.removeAll()

        for (i, tab) in tabs.enumerated() {
            let row = i / cols
            let col = i % cols
            let rect = NSRect(
                x: startX + CGFloat(col) * (layout.cardWidth + layout.gap),
                y: startY + CGFloat(row) * (layout.cardHeight + layout.gap),
                width: layout.cardWidth,
                height: layout.cardHeight
            )
            cardRects.append((index: i, rect: rect))
            drawCard(tab, index: i, in: rect)
        }

        window?.invalidateCursorRects(for: self)
    }

    private func drawCard(_ tab: TabPreview, index: Int, in rect: NSRect) {
        let selected = index == selectedIndex

        let bg = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.55)).setFill()
        bg.fill()

        let hovered = index == hoveredIndex && !selected

        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = selected ? 2.5 : (hovered ? 1.5 : 1)
        let strokeColor: NSColor = selected
            ? NSColor.controlAccentColor
            : (hovered ? NSColor.white.withAlphaComponent(0.65) : NSColor.white.withAlphaComponent(0.3))
        strokeColor.setStroke()
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
        let indexX = rect.minX + 10
        let indexW = drawIndex(index, x: indexX, centerY: rowY + 12)

        let faviconSize: CGFloat = 16
        let faviconX = indexX + indexW + 8
        let faviconRect = NSRect(x: faviconX, y: rowY + 4, width: faviconSize, height: faviconSize)
        if let favicon = favicons[tab.title] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        let titleX = faviconX + faviconSize + 6
        drawTitle(tab, x: titleX, y: rowY + 2, width: rect.maxX - 8 - titleX)
    }

    private func drawCompactCard(_ tab: TabPreview, index: Int, in rect: NSRect) {
        let indexX = rect.minX + 10
        let indexW = drawIndex(index, x: indexX, centerY: rect.midY)

        let faviconSize = min(26, rect.height - 16)
        let faviconX = indexX + indexW + 8
        let faviconRect = NSRect(x: faviconX, y: rect.midY - faviconSize / 2, width: faviconSize, height: faviconSize)
        if let favicon = favicons[tab.title] {
            favicon.draw(in: faviconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: faviconRect, xRadius: 6, yRadius: 6).fill()
        }

        let titleX = faviconX + faviconSize + 6
        drawTitle(tab, x: titleX, y: rect.minY + (rect.height - 18) / 2, width: rect.maxX - 8 - titleX)
    }

    /// Draw the index label; returns the width it occupied so callers can offset.
    @discardableResult
    private func drawIndex(_ index: Int, x: CGFloat, centerY: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ]
        let str = "\(index + 1)" as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: x, y: centerY - size.height / 2), withAttributes: attrs)
        return size.width
    }

    private func drawTitle(_ tab: TabPreview, x: CGFloat, y: CGFloat, width: CGFloat) {
        let title = tab.title.isEmpty ? tab.url : tab.title
        let rect = NSRect(x: x, y: y, width: max(10, width), height: 20)
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
