import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionManager
    var openDemo: () -> Void

    @State private var launchError: String?
    @State private var launchAtLogin = false

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            crew.tabItem { Label("Crew", systemImage: "person.3") }
            apps.tabItem { Label("Apps", systemImage: "app.badge") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 420)
        .padding(.top, 6)
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Enable Lilliput", isOn: $settings.isEnabled)
                Toggle("Pause workers", isOn: $settings.isPaused)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchError = settings.setLaunchAtLogin(newValue)
                        launchAtLogin = settings.launchAtLogin
                    }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show over full-screen apps", isOn: $settings.showOverFullScreen)
                Text("Off by default so video and presentations stay clean.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                HStack {
                    Image(systemName: permissions.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissions.isTrusted ? .green : .orange)
                    Text(permissions.isTrusted ? "Window observation is enabled." : "Accessibility access is needed to follow your windows.")
                    Spacer()
                    if !permissions.isTrusted {
                        Button("Open System Settings") { permissions.openSystemSettings() }
                    }
                }
                Button("Open Demo Construction…", action: openDemo)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Crew

    private var crew: some View {
        Form {
            Section("Construction") {
                Picker("Density", selection: $settings.density) {
                    ForEach(ConstructionDensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Worker size", selection: $settings.workerSize) {
                    ForEach(WorkerSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Animation", selection: $settings.intensity) {
                    ForEach(AnimationIntensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Special events", isOn: $settings.specialEvents)
                Toggle("Quiet construction sounds", isOn: $settings.soundEnabled)
            }
            Section("Limits") {
                Stepper(value: $settings.maxActiveSites, in: SettingsStore.siteLimitRange) {
                    HStack { Text("Active sites"); Spacer(); Text("\(settings.maxActiveSites)").monospacedDigit().foregroundStyle(.secondary) }
                }
                Stepper(value: $settings.maxWorkersPerSite, in: SettingsStore.workerLimitRange) {
                    HStack { Text("Workers per site"); Spacer(); Text("\(settings.maxWorkersPerSite)").monospacedDigit().foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apps

    private var apps: some View {
        Form {
            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No apps excluded. The crew works on every normal window.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            AppIconView(bundleID: bundleID)
                            Text(Self.appName(for: bundleID))
                            Spacer()
                            Button(role: .destructive) {
                                settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Excluded apps")
            } footer: {
                HStack {
                    Menu("Add Running App") {
                        ForEach(Self.runningApps(), id: \.self) { bundleID in
                            Button(Self.appName(for: bundleID)) { add(bundleID) }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…") { chooseApp() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add(_ bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            add(id)
        }
    }

    static func runningApps() -> [String] {
        let own = Bundle.main.bundleIdentifier
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != own }
        return Array(Set(ids)).sorted { appName(for: $0).localizedCaseInsensitiveCompare(appName(for: $1)) == .orderedAscending }
    }

    static func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.none)
                .frame(width: 96, height: 96)
            Text("Lilliput").font(.title.bold())
            Text("Version \(Self.versionString)").foregroundStyle(.secondary)
            Text("A tiny construction crew that treats your windows as buildings.\nEverything runs locally. No network, no telemetry.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
            Button("Open Demo Construction…", action: openDemo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

private struct AppIconView: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app").frame(width: 18, height: 18)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: SettingsStore, permissions: PermissionManager, openDemo: @escaping () -> Void) {
        let host = NSHostingController(rootView: SettingsView(settings: settings, permissions: permissions, openDemo: openDemo))
        let window = NSWindow(contentViewController: host)
        window.title = "Lilliput Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
