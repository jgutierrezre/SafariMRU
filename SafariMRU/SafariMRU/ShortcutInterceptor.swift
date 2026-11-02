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

/// Top-row number keys → 1-based tab number (0 is the 10th).
private let numberKeys: [CGKeyCode: Int] = [
    18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
]

final class ShortcutInterceptor {
    static let shared = ShortcutInterceptor()

    private var eventTap: CFMachPort?
    private var isCycling = false

    private let safariBundleID = "com.apple.Safari"

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

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
                if flags.contains(.maskShift) {
                    MRUSwitcher.shared.cycleBackward()
                } else {
                    MRUSwitcher.shared.cycleForward()
                }
                return nil // swallow so Safari does not switch sequentially
            }

            if isCtrl && !isCmdOrOpt, let number = numberKeys[keyCode] {
                if isCycling {
                    MRUSwitcher.shared.jumpToStackIndex(number - 1)
                } else {
                    MRUSwitcher.shared.jumpToTabBarIndex(number - 1)
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
