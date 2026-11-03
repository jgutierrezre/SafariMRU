//
//  OnboardingWindowController.swift
//  SafariMRU
//
//  First-run window that explains the two permissions the app needs and shows
//  their live status, with a direct link into the right System Settings pane.
//

import ApplicationServices
import Cocoa
import Combine
import CoreGraphics
import SwiftUI

enum Onboarding {
    private static let completedKey = "onboardingCompleted"

    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var accessibilityGranted = Onboarding.accessibilityGranted
    @Published var screenRecordingGranted = Onboarding.screenRecordingGranted

    let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func refresh() {
        accessibilityGranted = Onboarding.accessibilityGranted
        screenRecordingGranted = Onboarding.screenRecordingGranted
    }
}

struct OnboardingView: View {
    @StateObject private var model = OnboardingModel()
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("Welcome to Safari MRU")
                    .font(.title2.weight(.semibold))
                Text("Switch Safari tabs in the order you actually used them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                PermissionRow(
                    title: "Accessibility",
                    runs: "Required",
                    detail: "Lets Safari MRU read Safari's tabs and intercept Ctrl+Tab.",
                    granted: model.accessibilityGranted,
                    isRequired: true,
                    action: Onboarding.openAccessibilitySettings
                )
                Divider().padding(.leading, 46)
                PermissionRow(
                    title: "Screen Recording",
                    runs: "For thumbnails",
                    detail: "Captures the visible tab for previews. Restart the app after granting.",
                    granted: model.screenRecordingGranted,
                    isRequired: false,
                    action: Onboarding.openScreenRecordingSettings
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Text("Safari MRU lives in the menu bar — click the ⇄ icon for settings or to quit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Get Started") {
                    Onboarding.isComplete = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.accessibilityGranted)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(model.statusTimer) { _ in model.refresh() }
    }
}

private struct PermissionRow: View {
    let title: String
    let runs: String
    let detail: String
    let granted: Bool
    let isRequired: Bool
    let action: () -> Void

    private var statusSymbol: String {
        if granted { return "checkmark.circle.fill" }
        return isRequired ? "exclamationmark.triangle.fill" : "circle.dashed"
    }

    private var statusColor: Color {
        if granted { return .green }
        return isRequired ? .orange : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 18))
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(runs)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if granted {
                Text("Granted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings", action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
    }
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    var isVisible: Bool { window?.isVisible ?? false }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari MRU"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(onFinish: { OnboardingWindowController.shared.close() })
        )
        self.init(window: window)
        window.delegate = self
        window.center()
    }

    /// Shown on first run, and on any launch where Accessibility is missing.
    func presentIfNeeded() {
        guard !isVisible else { return }
        guard !Onboarding.accessibilityGranted || !Onboarding.isComplete else { return }
        present()
    }

    func present() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Don't nag again once the required permission is in place.
        if Onboarding.accessibilityGranted {
            Onboarding.isComplete = true
        }
    }
}
