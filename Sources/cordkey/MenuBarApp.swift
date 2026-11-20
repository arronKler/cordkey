import AppKit
import Darwin
import Foundation
import SwiftUI

/// Launches the macOS menu bar UI (LSUIElement / accessory app with no Dock icon).
enum MenuBarApp {
    private static var strongDelegate: MenuBarController?
    private static var lockFD: Int32 = -1

    static func run(promptAX: Bool, verbose: Bool) -> Never {
        // Enforce single instance across both CordKey.app and `cordkey --menubar`.
        guard acquireSingleInstanceLock() else {
            log("CordKey is already running.")
            exit(0)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MenuBarController(promptAX: promptAX, verbose: verbose)
        strongDelegate = controller
        app.delegate = controller
        app.run()
        exit(0)
    }

    private static func acquireSingleInstanceLock() -> Bool {
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CordKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let lockPath = supportDir.appendingPathComponent("cordkey.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        let pidStr = "\(ProcessInfo.processInfo.processIdentifier)\n"
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        _ = pidStr.withCString { write(fd, $0, strlen($0)) }
        return true
    }
}

final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let promptAX: Bool
    private let verbose: Bool

    private var state: AppState!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lastPopoverCloseTime: CFAbsoluteTime = 0

    private var sigIntSource: DispatchSourceSignal?
    private var sigTermSource: DispatchSourceSignal?

    init(promptAX: Bool, verbose: Bool) {
        self.promptAX = promptAX
        self.verbose = verbose
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState(promptAX: promptAX, verbose: verbose)
        state.onStatusBarChange = { [weak self] in
            self?.updateStatusItem()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: PopoverView(state: state, onQuit: { NSApp.terminate(nil) })
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        updateStatusItem()
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.shutdown()
    }

    // MARK: - Status Item Appearance

    private func updateStatusItem() {
        guard let button = statusItem?.button, let state else { return }

        let l10n = state.l10n
        let image: NSImage?
        let tooltip: String
        var title = ""

        if !state.hasAXPermission {
            let warn = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "CordKey")
            warn?.isTemplate = true
            image = warn
            tooltip = l10n.statusTooltipNoAX
        } else if !state.settings.enabled {
            image = MenuBarIcons.idleImage
            tooltip = l10n.statusTooltipPaused
        } else if state.isPausedByAppRule {
            image = MenuBarIcons.idleImage
            tooltip = l10n.statusTooltipAppPaused(state.activeFrontmostAppName ?? state.activeAppRule?.appName ?? "")
        } else if state.hidOpenFailed || state.bluetoothTapFailed {
            let warn = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "CordKey")
            warn?.isTemplate = true
            image = warn
            tooltip = state.hidOpenFailed ? l10n.statusTooltipHIDFailed : l10n.bluetoothTapFailedStatus
        } else if state.isKeyHeld {
            image = MenuBarIcons.activeImage
            title = String(format: " %d:%02d", state.heldSeconds / 60, state.heldSeconds % 60)
            tooltip = l10n.statusTooltipHolding(state.heldSummary ?? "")
        } else if state.connectedDevice != nil {
            image = MenuBarIcons.idleImage
            tooltip = l10n.statusTooltipConnected(state.connectedDevice)
        } else if state.isBluetoothTapActive {
            image = MenuBarIcons.idleImage
            tooltip = l10n.statusTooltipBluetooth
        } else {
            image = MenuBarIcons.idleImage
            tooltip = l10n.statusTooltipConnected(nil)
        }

        image?.accessibilityDescription = "CordKey"
        button.image = image
        button.title = title
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let showWarning = !state.hasAXPermission || (state.settings.enabled && !state.isPausedByAppRule && (state.hidOpenFailed || state.bluetoothTapFailed))
        button.appearsDisabled = !showWarning && (!state.settings.enabled || state.isPausedByAppRule || (state.connectedDevice == nil && !state.isBluetoothTapActive && !state.isKeyHeld))
        button.toolTip = tooltip
    }

    // MARK: - Click Handling (Left = Popover, Right = Quick Menu)

    @objc private func handleStatusBarClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let isRightClick = (event?.type == .rightMouseUp) || (event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            if popover.isShown { popover.performClose(nil) }
            showQuickContextMenu(from: button)
        } else {
            togglePopover(from: button)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTime = CFAbsoluteTimeGetCurrent()
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Transient popovers dismiss on mouseDown before leftMouseUp triggers this action.
            if CFAbsoluteTimeGetCurrent() - lastPopoverCloseTime < 0.25 {
                return
            }
            state.refreshAll()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self] in
                self?.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showQuickContextMenu(from button: NSStatusBarButton) {
        let l10n = state.l10n
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: state.settings.enabled ? l10n.menuPauseMapping : l10n.menuResumeMapping,
            action: #selector(quickToggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        if state.isKeyHeld {
            let releaseItem = NSMenuItem(
                title: l10n.menuReleaseHeld(state.heldSummary ?? ""),
                action: #selector(quickReleaseHeld),
                keyEquivalent: ""
            )
            releaseItem.target = self
            menu.addItem(releaseItem)
        }

        menu.addItem(.separator())

        let axItem = NSMenuItem(
            title: l10n.menuOpenAX,
            action: #selector(quickOpenAX),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        let quitItem = NSMenuItem(title: l10n.menuQuit, action: #selector(quickQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quickToggleEnabled() { state.setEnabled(!state.settings.enabled) }
    @objc private func quickReleaseHeld() { state.releaseHeldKeysManually() }
    @objc private func quickOpenAX() { state.openAccessibilitySettings() }
    @objc private func quickQuit() { NSApp.terminate(nil) }

    // MARK: - Signals

    private func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let stop: () -> Void = { NSApp.terminate(nil) }

        let sInt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sInt.setEventHandler(handler: stop)
        sInt.resume()
        sigIntSource = sInt

        let sTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sTerm.setEventHandler(handler: stop)
        sTerm.resume()
        sigTermSource = sTerm
    }
}
