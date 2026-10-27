import Foundation
import AppKit
import SpriteKit

/// Transparent, borderless, click-through window covering one display.
/// It never becomes key or main, never appears in Cmd-Tab (the app is an agent),
/// and passes every mouse event straight through to whatever is underneath.
final class OverlayWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configureSpaces(showOverFullScreen: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if showOverFullScreen { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
    }
}

@MainActor
final class OverlayManager {
    struct Display {
        let id: CGDirectDisplayID
        let screen: NSScreen
        let window: OverlayWindow
        let view: SKView
        let scene: ConstructionScene

        var frame: CGRect { screen.frame }
    }

    private(set) var displays: [Display] = []
    private var settings = SimSettings()
    private var showOverFullScreen = false

    var isActive: Bool { !displays.isEmpty }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func rebuild() {
        tearDown()
        for screen in NSScreen.screens {
            let frame = screen.frame
            let window = OverlayWindow(frame: frame)
            window.configureSpaces(showOverFullScreen: showOverFullScreen)
            let view = SKView(frame: CGRect(origin: .zero, size: frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.shouldCullNonVisibleNodes = true
            view.preferredFramesPerSecond = settings.intensity.idleFramesPerSecond
            view.autoresizingMask = [.width, .height]
            let scene = ConstructionScene(size: frame.size, isDemo: false)
            scene.apply(settings: settings)
            scene.backingScale = screen.backingScaleFactor
            scene.availableRect = ScreenGeometry.sceneRect(fromAppKit: screen.visibleFrame, displayFrame: frame)
            view.presentScene(scene)
            view.isPaused = true
            window.contentView = view
            window.orderFrontRegardless()
            let display = Display(id: Self.displayID(of: screen), screen: screen, window: window, view: view, scene: scene)
            scene.onActivityChange = { [weak self, weak view] activity in
                guard let self, let view else { return }
                self.applyActivity(activity, to: view)
            }
            displays.append(display)
        }
    }

    func tearDown() {
        for d in displays {
            d.scene.onActivityChange = nil
            d.scene.removeAllSites()
            d.view.presentScene(nil)
            d.window.orderOut(nil)
            d.window.contentView = nil
            d.window.close()
        }
        displays.removeAll()
    }

    func display(id: CGDirectDisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    func display(for globalFrame: CGRect) -> Display? {
        guard let i = ScreenGeometry.bestDisplayIndex(for: globalFrame, displays: displays.map(\.frame)) else { return nil }
        return displays[i]
    }

    func apply(settings new: SimSettings) {
        settings = new
        for d in displays {
            d.scene.apply(settings: new)
            applyActivity(d.scene.activity, to: d.view)
        }
    }

    func setShowOverFullScreen(_ on: Bool) {
        showOverFullScreen = on
        for d in displays { d.window.configureSpaces(showOverFullScreen: on) }
    }

    private func applyActivity(_ activity: SceneActivity, to view: SKView) {
        switch activity {
        case .empty:
            view.isPaused = true
        case .idle:
            view.preferredFramesPerSecond = settings.intensity.idleFramesPerSecond
            view.isPaused = false
        case .busy:
            view.preferredFramesPerSecond = 60
            view.isPaused = false
        }
    }
}
