//
//  MRUSwitcher.swift
//  SafariMRU
//
//  Deferred tab switching: while Control is held, stepping through the MRU list
//  only moves the preview selection; the actual tab switch happens on commit
//  (Control release). Tab order and metadata come from PreviewState, which the
//  Safari extension populates.
//

import Cocoa

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
            let tabs = PreviewState.shared.tabs
            guard !tabs.isEmpty else { return }
            cycleTabs = tabs
            isCycling = true
            selection = 0
        }

        guard cycleTabs.count > 1 else { return }

        if direction > 0 {
            selection += 1
            if selection >= cycleTabs.count { selection = 1 }
        } else {
            if selection > 0 { selection -= 1 }
        }

        updatePreview()
    }

    private func doCommit() {
        guard isCycling else { return }
        let tabs = cycleTabs
        let target = selection
        isCycling = false
        cycleTabs = []
        selection = 0

        DispatchQueue.main.async {
            if target >= 0 && target < tabs.count {
                SafariAX.switchToTab(index: tabs[target].index)
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

    private func updatePreview() {
        let tabs = cycleTabs
        let sel = selection
        DispatchQueue.main.async {
            PreviewWindowController.shared.show(tabs: tabs, selected: sel)
        }
    }
}
