import Foundation
import AppKit
import ApplicationServices

/// Tracks the Accessibility permission. Lilliput only asks for it when the user clicks
/// "Grant Access" and never shows the system prompt on its own.
@MainActor
final class PermissionManager: NSObject, ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()
    var onChange: ((Bool) -> Void)?
    private var pollTimer: Timer?
    private var promptedThisLaunch = false

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    func refresh() {
        let now = AXIsProcessTrusted()
        if now != isTrusted {
            isTrusted = now
            onChange?(now)
        }
    }

    /// Shows the macOS Accessibility prompt at most once per launch.
    func requestAccess() {
        if !promptedThisLaunch {
            promptedThisLaunch = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else {
            openSystemSettings()
        }
        startPolling()
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
        startPolling()
    }

    /// Cheap trust check every 1.5 s while onboarding is visible; no dialogs.
    func startPolling() {
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: 1.5, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func poll() {
        refresh()
        if isTrusted { stopPolling() }
    }
}
