//
//  MRUSwitcher.swift
//  SafariMRU
//
//  Immediate MRU switching: each Ctrl+Tab / Tab switches to the next tab right
//  away, while the preview overlay shows the frozen MRU order and the current
//  selection. Tab order and metadata come from PreviewState (the extension).
//

import Foundation

final class MRUSwitcher {
    static let shared = MRUSwitcher()
    private let queue = DispatchQueue(label: "mru.switcher")

    private var isCycling = false
    private var selection = 0
    /// Snapshot of tabs taken when the cycle starts, so mid-cycle changes don't shift indices.
    private var cycleTabs: [TabPreview] = []

    func cycleForward() { queue.async { self.step(1) } }
    func cycleBackward() { queue.async { self.step(-1) } }
    func commit() { queue.async { self.endCycle() } }
    func cancel() { queue.async { self.endCycle() } }

    private func step(_ direction: Int) {
        if !isCycling {
            // A cycle must begin with a forward press (Ctrl+Tab).
            if direction < 0 { return }
            let tabs = Self.currentTabs()
            guard !tabs.isEmpty else { return }
            cycleTabs = tabs
            isCycling = true
            selection = 0
        }

        guard cycleTabs.count > 1 else { return }

        if direction > 0 {
            selection += 1
            if selection >= cycleTabs.count { selection = 0 }
        } else {
            selection -= 1
            if selection < 0 { selection = cycleTabs.count - 1 }
        }

        activateSelection()
    }

    /// Jump to a numbered position in the active cycle: 1...n, or 0 for the last.
    func jumpToStackIndex(_ number: Int) {
        queue.async { self.doJumpStack(number) }
    }

    private func doJumpStack(_ number: Int) {
        guard isCycling else { return }
        let idx = number == 0 ? cycleTabs.count - 1 : number - 1
        guard idx >= 0 && idx < cycleTabs.count else { return }
        selection = idx
        activateSelection()
    }

    /// Switch directly to a tab-bar position: 1...n, or 0 for the last (rightmost).
    func jumpToTabBarIndex(_ number: Int) {
        DispatchQueue.main.async {
            if number == 0 {
                SafariAX.switchToLastTab()
            } else {
                SafariAX.switchToTab(index: number - 1)
            }
        }
    }

    /// Prefer the extension's state; fall back to AX tab titles when it's empty.
    private static func currentTabs() -> [TabPreview] {
        let ext = PreviewState.shared.tabs
        if !ext.isEmpty { return ext }

        guard let (active, titles) = SafariAX.getTabInfo() else { return [] }
        var result: [TabPreview] = []
        for (i, title) in titles.enumerated() {
            result.append(TabPreview(title: title, url: "", index: i))
        }
        if active >= 0 && active < result.count {
            let a = result.remove(at: active)
            result.insert(a, at: 0)
        }
        return result
    }

    /// Switch to the current selection immediately and refresh the preview.
    private func activateSelection() {
        let tabs = cycleTabs
        let idx = selection
        DispatchQueue.main.async {
            guard idx >= 0 && idx < tabs.count else { return }
            SafariAX.switchToTab(title: tabs[idx].title, fallbackIndex: tabs[idx].index)
            PreviewWindowController.shared.show(tabs: tabs, selected: idx)
        }
    }

    private func endCycle() {
        guard isCycling else { return }
        isCycling = false
        cycleTabs = []
        selection = 0
        DispatchQueue.main.async {
            PreviewWindowController.shared.hide()
        }
    }
}
