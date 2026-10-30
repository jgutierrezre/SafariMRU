//
//  MRUSwitcher.swift
//  SafariMRU
//
//  Most-recently-used tab ordering. Maintains a per-window MRU stack of tab
//  titles, steps through it while Control is held, and commits on release.
//

import Cocoa

final class MRUSwitcher {
    static let shared = MRUSwitcher()
    private let queue = DispatchQueue(label: "mru.switcher")

    /// Tab titles in MRU order; index 0 = most recently used.
    private var mru: [String] = []
    private var activeTitle: String?
    private var isCycling = false
    private var cyclePos = 0
    /// Title of the tab we just switched to (so polling ignores our own switch).
    private var expectedTitle: String?
    private var pollTimer: DispatchSourceTimer?

    func start() {
        queue.async { self.initialSync() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.4)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        pollTimer = timer
    }

    private func initialSync() {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]
        var seed = [a]
        for (i, t) in titles.enumerated() where i != active {
            if !seed.contains(t) { seed.append(t) }
        }
        mru = seed
        activeTitle = a
    }

    private func poll() {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]

        var newMru = mru.filter { titles.contains($0) }
        for t in titles where !newMru.contains(t) { newMru.append(t) }
        mru = newMru

        if activeTitle != a {
            if let exp = expectedTitle, exp == a {
                expectedTitle = nil
            } else if isCycling {
                isCycling = false
                cyclePos = 0
                promote(a)
            } else {
                promote(a)
            }
            activeTitle = a
        }
    }

    private func promote(_ title: String) {
        mru.removeAll { $0 == title }
        mru.insert(title, at: 0)
    }

    func cycleForward() { queue.async { self.doCycle(1) } }
    func cycleBackward() { queue.async { self.doCycle(-1) } }
    func commit() { queue.async { self.doCommit() } }

    private func doCycle(_ direction: Int) {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]
        activeTitle = a

        if !isCycling {
            // A cycle must begin with a forward press (Ctrl+Tab). Backward first does nothing.
            if direction < 0 { return }
            if mru.isEmpty {
                initialSync()
                if mru.isEmpty { return }
            }
            // Sync the active tab to the front (catches a click the poll hasn't seen yet).
            if mru.first != a { promote(a) }
            isCycling = true
            cyclePos = 0
        }

        guard mru.count > 1 else { return }

        if direction > 0 {
            cyclePos += 1
            if cyclePos >= mru.count { cyclePos = 1 }
        } else {
            if cyclePos > 0 { cyclePos -= 1 }
        }

        let target = mru[cyclePos]
        guard let idx = titles.firstIndex(of: target) else {
            mru.removeAll { $0 == target }
            isCycling = false
            cyclePos = 0
            return
        }
        expectedTitle = target
        SafariAX.switchToTab(index: idx)
    }

    private func doCommit() {
        guard isCycling else { return }
        let target = mru[cyclePos]
        promote(target)
        isCycling = false
        cyclePos = 0
    }
}
