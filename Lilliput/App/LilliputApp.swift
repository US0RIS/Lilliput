import AppKit

/// Entry point. Lilliput is an agent app (LSUIElement): no Dock icon, no Cmd-Tab entry,
/// just a menu-bar item and transparent overlays.
@main
@MainActor
enum LilliputApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
