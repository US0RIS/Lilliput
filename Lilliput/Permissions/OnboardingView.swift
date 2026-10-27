import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionManager
    var openDemo: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Lilliput").font(.title2.bold())
                    Text("A tiny construction crew is ready to move in.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("To build scaffolding around your windows, Lilliput needs to know where they are.")
                Label("Accessibility access lets Lilliput see window positions and sizes, and notice when they open, move, resize, minimize or close.", systemImage: "macwindow.on.rectangle")
                Label("Lilliput never reads window contents, titles, or anything you type, and makes no network connections.", systemImage: "lock.shield")
                Label("Screen Recording is not needed.", systemImage: "checkmark.circle")
            }
            .font(.callout)

            if permissions.isTrusted {
                Label("Access granted — the crew is on its way.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Text("In System Settings → Privacy & Security → Accessibility, switch on Lilliput. If you rebuilt the app, remove the old entry and add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if permissions.isTrusted {
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Try Demo Mode", action: openDemo)
                    Spacer()
                    Button("Retry") { permissions.refresh() }
                    Button("Open System Settings") { permissions.openSystemSettings() }
                    Button("Grant Access") { permissions.requestAccess() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let permissions: PermissionManager
    var onClose: (() -> Void)?

    init(permissions: PermissionManager, openDemo: @escaping () -> Void) {
        self.permissions = permissions
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 360),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Lilliput"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let view = OnboardingView(permissions: permissions, openDemo: openDemo, close: { [weak self] in self?.close() })
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        permissions.startPolling()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
