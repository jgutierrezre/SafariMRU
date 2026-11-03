//
//  MRUSwitcher.swift
//  SafariMRU
//
//  Ctrl+Tab cycles a preview and switches on Control release (deferred).
//  Ctrl+1..9 / Ctrl+0 switch to a numbered tab immediately.
//  The tab order comes from MRUTracker (native, AXObserver-driven).
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
    func commit() { queue.async { self.doCommit() } }
    func cancel() { queue.async { self.doCancel() } }

    private func step(_ direction: Int) {
        if !isCycling {
            // A cycle must begin with a forward press (Ctrl+Tab).
            if direction < 0 { return }
            let tabs = MRUTracker.shared.tabs()
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

        // Deferred: only move the highlight; the switch happens on Control release.
        updatePreview()
    }

    /// Switch immediately to the Nth item of the active cycle (from a click).
    func commitToIndex(_ index: Int) {
        queue.async { self.doCommitToIndex(index) }
    }

    private func doCommitToIndex(_ index: Int) {
        guard isCycling, index >= 0, index < cycleTabs.count else { return }
        let target = cycleTabs[index]
        isCycling = false
        cycleTabs = []
        selection = 0
        DispatchQueue.main.async {
            SafariAX.switchToTab(title: target.title, fallbackIndex: target.index)
            MRUTracker.shared.promote(target.title)
            PreviewWindowController.shared.hide()
        }
    }

    /// Jump to a numbered position in the active cycle (immediate): 1...n, or 0 for the last.
    func jumpToStackIndex(_ number: Int) {
        queue.async { self.doJumpStack(number) }
    }

    private func doJumpStack(_ number: Int) {
        guard isCycling else { return }
        let idx = number == 0 ? cycleTabs.count - 1 : number - 1
        guard idx >= 0 && idx < cycleTabs.count else { return }
        let target = cycleTabs[idx]
        isCycling = false
        cycleTabs = []
        selection = 0
        DispatchQueue.main.async {
            SafariAX.switchToTab(title: target.title, fallbackIndex: target.index)
            MRUTracker.shared.promote(target.title)
            PreviewWindowController.shared.hide()
        }
    }

    /// Switch directly to a tab-bar position (immediate): 1...n, or 0 for the last.
    func jumpToTabBarIndex(_ number: Int) {
        DispatchQueue.main.async {
            MRUTracker.shared.sync()
            let idx = number == 0 ? MRUTracker.shared.tabCount - 1 : number - 1
            if number == 0 {
                SafariAX.switchToLastTab()
            } else {
                SafariAX.switchToTab(index: idx)
            }
            MRUTracker.shared.sync()
        }
    }

    private func updatePreview() {
        let tabs = cycleTabs
        let idx = selection
        DispatchQueue.main.async {
            PreviewWindowController.shared.show(tabs: tabs, selected: idx)
        }
    }

    private func doCommit() {
        guard isCycling else { return }
        let tabs = cycleTabs
        let idx = selection
        isCycling = false
        cycleTabs = []
        selection = 0

        DispatchQueue.main.async {
            if idx >= 0 && idx < tabs.count {
                SafariAX.switchToTab(title: tabs[idx].title, fallbackIndex: tabs[idx].index)
                MRUTracker.shared.promote(tabs[idx].title)
            }
            PreviewWindowController.shared.hide()
        }
    }

    private func doCancel() {
        guard isCycling else { return }
        isCycling = false
        cycleTabs = []
        selection = 0
        DispatchQueue.main.async {
            PreviewWindowController.shared.hide()
        }
    }
}
