import AppKit
import Foundation

/// Behavior applied when a rule's target application becomes frontmost.
enum AppRuleAction: Codable, Equatable {
    /// Pause CordKey button remapping so native media/headset controls pass through.
    case pause
    /// Override the Play button with a specific shortcut string (e.g. "command+shift+d").
    case overridePlay(String)
}

/// Per-application rule matched against the frontmost app's bundle identifier.
struct AppRule: Codable, Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    var appName: String
    var action: AppRuleAction
    var enabled: Bool = true
}

/// Built-in preset descriptor for commonly used conferencing and media apps.
struct AppRulePreset: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let action: AppRuleAction

    func makeRule(enabled: Bool = true) -> AppRule {
        AppRule(bundleID: bundleID, appName: appName, action: action, enabled: enabled)
    }
}

extension AppRule {
    /// Popular macOS app presets ready for one-click rule creation.
    static let commonPresets: [AppRulePreset] = [
        AppRulePreset(
            bundleID: "com.electron.lark",
            appName: "Lark / 飞书",
            action: .overridePlay("command+shift+d")
        ),
        AppRulePreset(
            bundleID: "us.zoom.xos",
            appName: "Zoom",
            action: .overridePlay("command+shift+a")
        ),
        AppRulePreset(
            bundleID: "com.hnc.Discord",
            appName: "Discord",
            action: .overridePlay("command+shift+m")
        ),
        AppRulePreset(
            bundleID: "com.apple.Music",
            appName: "Music",
            action: .pause
        ),
        AppRulePreset(
            bundleID: "com.colliderli.iina",
            appName: "IINA",
            action: .pause
        ),
        AppRulePreset(
            bundleID: "com.apple.QuickTimePlayerX",
            appName: "QuickTime Player",
            action: .pause
        ),
    ]
}

/// Lightweight descriptor for a currently running regular macOS application.
struct RunningAppInfo: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

/// Observes frontmost macOS application changes and resolves matching per-app rules.
final class FrontmostAppWatcher {
    private(set) var currentBundleID: String?
    private(set) var currentAppName: String?

    /// Invoked on the main queue whenever the frontmost app is read on start or changes.
    var onFrontmostAppChange: ((_ bundleID: String?, _ appName: String?) -> Void)?

    private var observer: NSObjectProtocol?

    init() {}

    deinit {
        stop()
    }

    func start() {
        stop()

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                ?? NSWorkspace.shared.frontmostApplication
            guard let app, !Self.isIgnoredApp(app) else { return }
            self?.deliverFrontmostApp(bundleID: app.bundleIdentifier, appName: app.localizedName)
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication, !Self.isIgnoredApp(frontmost) {
            deliverFrontmostApp(bundleID: frontmost.bundleIdentifier, appName: frontmost.localizedName)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func deliverFrontmostApp(bundleID: String?, appName: String?) {
        if Thread.isMainThread {
            currentBundleID = bundleID
            currentAppName = appName
            onFrontmostAppChange?(bundleID, appName)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentBundleID = bundleID
                self.currentAppName = appName
                self.onFrontmostAppChange?(bundleID, appName)
            }
        }
    }

    private static func excludedBundleIDs() -> Set<String> {
        var excluded: Set<String> = [
            "io.github.cordkey.app",
            "io.github.cordkey.cli",
        ]
        if let mainBundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mainBundleID.isEmpty {
            excluded.insert(mainBundleID.lowercased())
        }
        return excluded
    }

    private static func isIgnoredApp(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if app.activationPolicy != .regular {
            return true
        }
        if let rawBundleID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawBundleID.isEmpty,
           excludedBundleIDs().contains(rawBundleID.lowercased()) {
            return true
        }
        return false
    }

    /// Returns user-visible running `.regular` apps (excluding CordKey itself), deduplicated and sorted by name.
    static func listRunningRegularApps() -> [RunningAppInfo] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let excluded = excludedBundleIDs()

        var seenBundleIDs: Set<String> = []
        var apps: [RunningAppInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard app.processIdentifier != currentPID else { continue }
            guard let rawBundleID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawBundleID.isEmpty else {
                continue
            }

            let normalizedBundleID = rawBundleID.lowercased()
            guard !excluded.contains(normalizedBundleID) else { continue }
            guard seenBundleIDs.insert(normalizedBundleID).inserted else { continue }

            let trimmedName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (trimmedName?.isEmpty == false) ? trimmedName! : rawBundleID
            apps.append(RunningAppInfo(bundleID: rawBundleID, name: displayName))
        }

        return apps.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return lhs.bundleID.localizedCaseInsensitiveCompare(rhs.bundleID) == .orderedAscending
        }
    }

    /// Finds the first enabled rule whose `bundleID` matches `bundleID` case-insensitively.
    static func matchingRule(for bundleID: String?, in rules: [AppRule]) -> AppRule? {
        guard let target = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else {
            return nil
        }
        return rules.first { rule in
            rule.enabled && rule.bundleID.caseInsensitiveCompare(target) == .orderedSame
        }
    }
}
