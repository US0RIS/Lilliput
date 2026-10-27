import AppKit
import SpriteKit
import SwiftUI

struct DemoControlsView: View {
    @ObservedObject var controller: DemoController

    var body: some View {
        HStack(spacing: 8) {
            Button { controller.openWindow() } label: { Label("Open", systemImage: "plus.rectangle") }
                .disabled(controller.windowCount >= 6)
            Button { controller.moveFront() } label: { Label("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
            Button { controller.moveFront(fast: true) } label: { Label("Fling", systemImage: "wind") }
            Button { controller.resizeFront() } label: { Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button { controller.focusNext() } label: { Label("Focus", systemImage: "square.stack.3d.up") }
            Button { controller.minimizeFront() } label: { Label("Minimize", systemImage: "minus.rectangle") }
            Button { controller.restoreOne() } label: { Label("Restore", systemImage: "rectangle.portrait.and.arrow.forward") }
                .disabled(controller.minimizedCount == 0)
            Button { controller.closeFront() } label: { Label("Close", systemImage: "xmark.rectangle") }
            Button { controller.specialEvent() } label: { Label("Event", systemImage: "sparkles") }
            Spacer(minLength: 8)
            Toggle("Autoplay", isOn: $controller.autoplay)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Demo Construction: a separate preview window with pretend windows, driven by the
/// same ConstructionScene / ConstructionSite code as the real overlays. Works without
/// Accessibility permission.
@MainActor
final class DemoWindowController: NSWindowController, NSWindowDelegate {
    private let controller: DemoController
    private let skView: SKView
    private let settings: SettingsStore
    var onClose: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let size = CGSize(width: 1120, height: 720)
        let controlsHeight: CGFloat = 52
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Lilliput — Demo Construction"
        window.minSize = CGSize(width: 820, height: 520)
        window.isReleasedWhenClosed = false

        let sceneSize = CGSize(width: size.width, height: size.height - controlsHeight)
        let demo = DemoController(size: sceneSize, settings: settings.simSettings)
        let view = SKView(frame: CGRect(x: 0, y: controlsHeight, width: size.width, height: sceneSize.height))
        view.autoresizingMask = [.width, .height]
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        controller = demo
        skView = view

        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.addSubview(view)
        let controls = NSHostingView(rootView: DemoControlsView(controller: demo))
        controls.frame = CGRect(x: 0, y: 0, width: size.width, height: controlsHeight)
        controls.autoresizingMask = [.width]
        container.addSubview(controls)
        window.contentView = container

        super.init(window: window)
        window.delegate = self
        window.center()
        skView.presentScene(controller.scene)
        controller.scene.backingScale = window.backingScaleFactor
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        controller.start()
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        controller.shutdown()
        skView.presentScene(nil)
    }

    @objc private func settingsChanged() {
        controller.scene.apply(settings: settings.simSettings)
        SoundEngine.shared.enabled = settings.soundEnabled
    }

    func windowWillClose(_ notification: Notification) {
        shutdown()
        onClose?()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        if let w = window { controller.scene.backingScale = w.backingScaleFactor }
    }
}
