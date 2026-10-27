import Foundation
import AppKit
import ApplicationServices

@MainActor
protocol WindowTrackerDelegate: AnyObject {
    /// - Parameters:
    ///   - stacking: tracked (eligible, on-screen) windows, front to back.
    ///   - occluders: every on-screen normal-layer window (tracked or not), front to back,
    ///     in AppKit global coordinates.
    func tracker(_ tracker: WindowTracker,
                 didEmit events: [WindowEvent],
                 stacking: [WindowSnapshot],
                 occluders: [(id: WindowID, frame: CGRect)])
}

/// Discovers and observes other applications' windows.
///
/// Strategy:
/// * Core Graphics window list (`CGWindowListCopyWindowInfo`) is the source of truth for
///   identity (window number), geometry and stacking. It needs no Screen Recording
///   permission because Lilliput never reads window titles or pixels.
/// * Accessibility (`AXObserver`) notifications tell us *when* to look: windows created,
///   moved, resized, minimized, focus changes. AX is also used once per window to read its
///   role/subrole so dialogs, panels and popovers are skipped.
/// * While a window is being dragged or resized we poll the window list at display rate;
///   otherwise a slow reconciliation timer catches anything notifications missed.
@MainActor
final class WindowTracker: NSObject {
    private enum Classification {
        case accepted
        case rejected
        case unknown(attempts: Int, lastTry: TimeInterval)
    }

    struct RawWindow {
        let id: WindowID
        let pid: pid_t
        let cgFrame: CGRect
        let alpha: Double
    }

    weak var delegate: WindowTrackerDelegate?

    var excludedBundleIDs: Set<String> = [] {
        didSet { if oldValue != excludedBundleIDs { requestReconcile() } }
    }
    var allowFullScreenWindows = false {
        didSet { if oldValue != allowFullScreenWindows { requestReconcile() } }
    }

    private let registry = WindowRegistry()
    private var observers: [pid_t: AXObserver] = [:]
    private var classification: [WindowID: Classification] = [:]
    private var bundleCache: [pid_t: String] = [:]
    private var idleTimer: Timer?
    private var activeTimer: Timer?
    private var activeUntil: TimeInterval = 0
    private var mouseIsDown = false
    private var mouseMonitor: Any?
    private var reconcileScheduled = false
    private var nextAnimated = true
    private var lastOccluderSignature: [CGRect] = []
    private(set) var isRunning = false
    private let ownPID = getpid()

    static let systemBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.screenshot.launcher",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.wallpaper.agent",
        "com.apple.AirPlayUIAgent",
        "com.apple.universalcontrol",
        "com.apple.coreservices.uiagent",
        "com.apple.UserNotificationCenter",
        "com.apple.SecurityAgent",
        "com.apple.accessibility.universalAccessAuthWarn",
    ]

    static let minimumSize = CGSize(width: 180, height: 120)

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        registry.reset()
        classification.removeAll()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(spaceChanged(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            addObserver(for: app.processIdentifier)
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.handleMouse(type)
            }
        }

        let timer = Timer(timeInterval: 0.6, target: self, selector: #selector(idleTick), userInfo: nil, repeats: true)
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer

        reconcile(animated: true, checkHidden: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for pid in Array(observers.keys) { removeObserver(for: pid) }
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
        idleTimer?.invalidate()
        idleTimer = nil
        activeTimer?.invalidate()
        activeTimer = nil
        registry.reset()
        classification.removeAll()
        bundleCache.removeAll()
    }

    /// Re-evaluates soon (coalesced).
    func requestReconcile(animated: Bool = true) {
        guard isRunning else { return }
        if !animated { nextAnimated = false }
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reconcileScheduled = false
                let animated = self.nextAnimated
                self.nextAnimated = true
                self.reconcile(animated: animated, checkHidden: true)
            }
        }
    }

    /// Re-emits everything as freshly opened (after the overlays were rebuilt).
    func resync(animated: Bool) {
        guard isRunning else { return }
        registry.reset()
        reconcile(animated: animated, checkHidden: true)
        // Registry needs the stabilisation delay to elapse before emitting `opened`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                self?.reconcile(animated: animated, checkHidden: true)
            }
        }
    }

    // MARK: Accessibility observers

    private func addObserver(for pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, lilliputAXCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let names = [
            kAXWindowCreatedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
            kAXUIElementDestroyedNotification,
        ]
        var any = false
        for n in names where AXObserverAddNotification(observer, app, n as CFString, refcon) == .success {
            any = true
        }
        guard any else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    fileprivate func handleAXNotification(_ name: String) {
        switch name {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            enterActiveMode(for: 0.4)
        default:
            enterActiveMode(for: 0.3)
            requestReconcile()
        }
    }

    // MARK: Workspace and input

    @objc private func appLaunched(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            addObserver(for: app.processIdentifier)
        }
        requestReconcile()
    }

    @objc private func appTerminated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            removeObserver(for: app.processIdentifier)
            bundleCache[app.processIdentifier] = nil
        }
        requestReconcile()
    }

    @objc private func appActivated(_ note: Notification) {
        requestReconcile()
        enterActiveMode(for: 0.3)
    }

    @objc private func spaceChanged(_ note: Notification) {
        requestReconcile(animated: false)
    }

    private func handleMouse(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            mouseIsDown = true
            enterActiveMode(for: 0.3)
        case .leftMouseDragged:
            enterActiveMode(for: 0.3)
        case .leftMouseUp:
            mouseIsDown = false
            enterActiveMode(for: 0.4)
        default:
            break
        }
    }

    private func enterActiveMode(for duration: TimeInterval) {
        guard isRunning else { return }
        activeUntil = max(activeUntil, ProcessInfo.processInfo.systemUptime + duration)
        guard activeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(activeTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        activeTimer = timer
    }

    @objc private func activeTick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now > activeUntil && !mouseIsDown {
            activeTimer?.invalidate()
            activeTimer = nil
            reconcile(animated: true, checkHidden: true)
            return
        }
        // Safety: a stuck "mouse down" (missed up event) expires after a while.
        if mouseIsDown && now > activeUntil + 8 { mouseIsDown = false }
        reconcile(animated: true, checkHidden: false)
    }

    @objc private func idleTick() {
        reconcile(animated: true, checkHidden: true)
    }

    // MARK: Reconciliation

    private func reconcile(animated: Bool, checkHidden: Bool) {
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let raw = Self.enumerateWindows()
        let primaryHeight = Self.primaryScreenHeight()
        let screenFramesCG = NSScreen.screens.map { ScreenGeometry.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight) }

        var inputs: [WindowRegistry.Input] = []
        var occluders: [(id: WindowID, frame: CGRect)] = []
        var seenIDs = Set<WindowID>()
        for w in raw where w.pid != ownPID {
            seenIDs.insert(w.id)
            let frame = ScreenGeometry.appKitRect(fromCG: w.cgFrame, primaryHeight: primaryHeight)
            occluders.append((w.id, frame))
            guard isEligible(w, screens: screenFramesCG, now: now) else { continue }
            inputs.append(WindowRegistry.Input(id: w.id, pid: w.pid, frame: frame, bundleID: bundleID(for: w.pid)))
        }
        // Forget classifications for windows that are gone for good.
        if classification.count > 400 {
            classification = classification.filter { seenIDs.contains($0.key) }
        }

        let out = registry.reconcile(inputs, now: now, animated: animated, checkHidden: checkHidden) { id in
            Self.windowExists(id)
        }
        let signature = occluders.map(\.frame)
        let occludersChanged = signature != lastOccluderSignature
        lastOccluderSignature = signature
        if !out.events.isEmpty || out.stackingChanged || occludersChanged {
            delegate?.tracker(self, didEmit: out.events, stacking: out.stacking, occluders: occluders)
        }
    }

    private func isEligible(_ w: RawWindow, screens: [CGRect], now: TimeInterval) -> Bool {
        guard w.alpha > 0.05,
              w.cgFrame.width >= Self.minimumSize.width,
              w.cgFrame.height >= Self.minimumSize.height else { return false }
        let bundle = bundleID(for: w.pid)
        if let bundle, Self.systemBundleIDs.contains(bundle) || excludedBundleIDs.contains(bundle) { return false }
        if !allowFullScreenWindows, screens.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(w.cgFrame) && w.cgFrame.width >= $0.width - 4 && w.cgFrame.height >= $0.height - 4 }) {
            return false
        }
        switch classification[w.id] {
        case .accepted?:
            return true
        case .rejected?:
            return false
        case .unknown(let attempts, let lastTry)?:
            guard now - lastTry > 0.2 else { return false }
            let result = classify(w)
            switch result {
            case .accepted, .rejected:
                classification[w.id] = result
                if case .accepted = result { return true }
                return false
            case .unknown:
                if attempts >= 4 {
                    // Some apps don't expose AX windows; accept clearly app-like windows.
                    let ok = w.cgFrame.width >= 400 && w.cgFrame.height >= 250
                    classification[w.id] = ok ? .accepted : .rejected
                    return ok
                }
                classification[w.id] = .unknown(attempts: attempts + 1, lastTry: now)
                return false
            }
        case nil:
            let result = classify(w)
            if case .unknown = result {
                classification[w.id] = .unknown(attempts: 1, lastTry: now)
                return false
            }
            classification[w.id] = result
            if case .accepted = result { return true }
            return false
        }
    }

    /// Matches the CG window to its AX element (same process, same frame) and checks the
    /// role/subrole: standard windows (and large dialogs) get scaffolding.
    private func classify(_ w: RawWindow) -> Classification {
        let app = AXUIElementCreateApplication(w.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let windows: [AXUIElement] = AX.copy(app, kAXWindowsAttribute) else {
            return .unknown(attempts: 0, lastTry: 0)
        }
        for el in windows {
            guard let p = AX.point(el, kAXPositionAttribute), let s = AX.size(el, kAXSizeAttribute) else { continue }
            guard abs(p.x - w.cgFrame.minX) < 3, abs(p.y - w.cgFrame.minY) < 3,
                  abs(s.width - w.cgFrame.width) < 3, abs(s.height - w.cgFrame.height) < 3 else { continue }
            let role: String? = AX.copy(el, kAXRoleAttribute)
            let subrole: String? = AX.copy(el, kAXSubroleAttribute)
            guard role == kAXWindowRole else { return .rejected }
            if subrole == kAXStandardWindowSubrole { return .accepted }
            if subrole == kAXDialogSubrole, s.width >= 300, s.height >= 200 { return .accepted }
            return .rejected
        }
        return .unknown(attempts: 0, lastTry: 0)
    }

    private func bundleID(for pid: pid_t) -> String? {
        if let b = bundleCache[pid] { return b }
        let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let b { bundleCache[pid] = b }
        return b
    }

    // MARK: Core Graphics

    static func primaryScreenHeight() -> CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) { return primary.frame.height }
        return NSScreen.screens.first?.frame.height ?? 0
    }

    /// On-screen, normal-layer windows, front to back.
    static func enumerateWindows() -> [RawWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var result: [RawWindow] = []
        result.reserveCapacity(list.count)
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsAny = info[kCGWindowBounds as String] else { continue }
            let boundsDict = boundsAny as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            result.append(RawWindow(id: number, pid: pid, cgFrame: bounds, alpha: alpha))
        }
        return result
    }

    /// True if the window still exists anywhere (minimized, hidden, other Space).
    static func windowExists(_ id: WindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
    }
}

/// C callback for AXObserver. Runs on the main run loop.
private func lilliputAXCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let name = notification as String
    MainActor.assumeIsolated {
        let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        tracker.handleAXNotification(name)
    }
}

/// Small typed wrappers over AXUIElementCopyAttributeValue.
enum AX {
    static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }
}
