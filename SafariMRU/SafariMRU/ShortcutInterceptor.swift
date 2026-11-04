//
//  ShortcutInterceptor.swift
//  SafariMRU
//
//  A Quartz CGEventTap that intercepts Ctrl+Tab / Ctrl+Shift+Tab when Safari is
//  frontmost, swallows them (so Safari doesn't switch sequentially), and drives
//  the MRU switcher. Detects physical Control release to commit the cycle.
//

import Cocoa
import ApplicationServices

private let kVK_Tab: CGKeyCode = 48
private let kVK_Escape: CGKeyCode = 53

/// Top-row number keys → 1-based tab number (0 is the last tab).
private let numberKeys: [CGKeyCode: Int] = [
    18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
]

final class ShortcutInterceptor {
    static let shared = ShortcutInterceptor()

    private var eventTap: CFMachPort?
    private var isCycling = false
    private var swallowingClick = false
    private var promptedForAccessibility = false

    /// True once the event tap is installed and shortcuts are live.
    private(set) var isRunning = false

    private let safariBundleID = "com.apple.Safari"

    /// Install the event tap. Call again after granting Accessibility: it
    /// returns early once running, and only prompts once.
    func start() {
        guard !isRunning else { return }

        let prompt = !promptedForAccessibility
        promptedForAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    fileprivate func handleCGEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Clicks while the preview is open belong to the switcher. Clicks on
        // the (full-screen) overlay are delivered to it; clicks on another
        // display dismiss the switcher. Either way the matching mouse-up is
        // swallowed so it cannot interact with the app underneath.
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            if PreviewWindowController.shared.isVisible {
                swallowingClick = true
                if !PreviewWindowController.shared.containsMouseLocation() {
                    MRUSwitcher.shared.cancel()
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
            if swallowingClick {
                swallowingClick = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleID else {
            if isCycling {
                isCycling = false
                MRUSwitcher.shared.commit()
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        if type == .flagsChanged {
            if isCycling && !flags.contains(.maskControl) {
                isCycling = false
                MRUSwitcher.shared.commit()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isCtrl = flags.contains(.maskControl)
            let isCmdOrOpt = flags.contains(.maskCommand) || flags.contains(.maskAlternate)

            if keyCode == kVK_Escape && isCycling {
                isCycling = false
                MRUSwitcher.shared.cancel()
                return nil
            }

            if keyCode == kVK_Tab && isCtrl && !isCmdOrOpt {
                isCycling = true
                swallowingClick = false
                if flags.contains(.maskShift) {
                    MRUSwitcher.shared.cycleBackward()
                } else {
                    MRUSwitcher.shared.cycleForward()
                }
                return nil // swallow so Safari does not switch sequentially
            }

            if Settings.numberShortcutsEnabled, isCtrl && !isCmdOrOpt, let number = numberKeys[keyCode] {
                if isCycling {
                    MRUSwitcher.shared.jumpToStackIndex(number)
                } else {
                    MRUSwitcher.shared.jumpToTabBarIndex(number)
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

// Top-level C-compatible callback (cannot capture; state is recovered via userInfo).
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<ShortcutInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handleCGEvent(proxy: proxy, type: type, event: event)
}
