import AppKit
import ApplicationServices
import CoreAudio
import Foundation

/// Central observable state for the CordKey menu bar popover,
/// bridging HIDListener (Consumer + Telephony), ButtonMapper, HIDButtonLearner,
/// CoreAudio input devices, and system permissions.
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var hasAXPermission: Bool = false
    @Published var connectedDevice: String? = nil
    @Published var isSeized: Bool = false

    @Published var physicalButtons: Set<HIDButton> = []
    @Published var heldSummary: String? = nil
    @Published var heldSeconds: Int = 0
    @Published var lastEvent: String = ""

    @Published var isLearningHeadsetButton: Bool = false
    @Published var highlightedButton: HIDButton? = nil
    @Published var hidOpenFailed: Bool = false

    @Published var hidDevices: [HIDDeviceInfo] = []
    @Published var audioInputs: [AudioInputDevice] = []
    @Published var defaultAudioInputID: AudioDeviceID? = nil
    @Published var launchAtLogin: Bool = LaunchAgentHelper.isEnabled

    @Published var savedProfiles: [HeadsetProfile] = []
    @Published var activeAppRule: AppRule? = nil
    @Published var isPausedByAppRule: Bool = false
    @Published var activeFrontmostAppName: String? = nil
    @Published var runningApps: [RunningAppInfo] = []
    @Published var isBluetoothTapActive: Bool = false
    @Published var bluetoothTapFailed: Bool = false

    /// Called whenever status bar icon or elapsed title needs redraw.
    var onStatusBarChange: (() -> Void)?

    var l10n: L10n { L10n(settings.language) }
    var isMicLocked: Bool { micLock.isEnabled }

    let verbose: Bool
    var mapper: ButtonMapper!
    var listener: HIDListener?
    var learner: HIDButtonLearner?
    private let audioManager = AudioInputManager()

    let micLock: MicLockController
    let profileStore = HeadsetProfileStore()
    var arrivalWatcher: HeadsetArrivalWatcher?
    let hudController = FloatingHUDController()
    let toggleTimeoutController = ToggleTimeoutController()
    var frontmostWatcher: FrontmostAppWatcher?
    var bluetoothTap: BluetoothMediaTap?
    var isBluetoothToggleHeld: Bool = false

    private var axTimer: Timer?
    private var holdClockTimer: Timer?
    private var holdStartDate: Date?
    private var sleepObserver: NSObjectProtocol?

    var isKeyHeld: Bool { heldSummary != nil }

    var currentAudioInput: AudioInputDevice? {
        guard let id = defaultAudioInputID else { return nil }
        return audioInputs.first { $0.id == id }
    }

    var builtInAudioInput: AudioInputDevice? {
        audioInputs.first { $0.isBuiltIn }
    }

    /// Show smart warning when user is using EarPods in hold mode while default mic is EarPods
    /// (holding EarPods center button physically shorts the EarPods mic line).
    var shouldWarnEarPodsMic: Bool {
        guard settings.enabled, !settings.playKey.isEmpty else { return false }
        guard settings.triggerMode != .toggle else { return false }
        let isEarPodsTarget = (settings.vendorID == 0x05ac && settings.productID == 0x110b)
        return isEarPodsTarget && currentAudioInput?.isEarPods == true
    }

    init(promptAX: Bool, verbose: Bool) {
        self.verbose = verbose
        let loaded = AppSettings.load()
        self.settings = loaded
        self.micLock = MicLockController(
            lockedUID: loaded.lockedMicUID.isEmpty ? nil : loaded.lockedMicUID,
            lockedName: loaded.lockedMicName.isEmpty ? nil : loaded.lockedMicName
        )
        self.lastEvent = L10n(loaded.language).readyStatus

        mapper = ButtonMapper(config: loaded.mapperConfig(verbose: verbose))
        mapper.onStateChange = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.applyMapperSnapshot(snapshot)
            }
        }

        checkAccessibility(prompt: promptAX)
        if !hasAXPermission {
            startAXWatcher()
        }

        refreshDevices()
        refreshAudioInputs()
        audioManager.startObserving { [weak self] in
            self?.refreshAudioInputs()
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.toggleTimeoutController.cancel()
            self.hudController.hide()
            self.mapper.releaseAll(reason: self.l10n.reasonSleep)
        }

        setupFeatures()

        if settings.enabled && !isPausedByAppRule {
            restartListener()
        }
    }

    deinit {
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        axTimer?.invalidate()
        holdClockTimer?.invalidate()
        audioManager.stopObserving()
        teardownFeatures()
        listener?.stop()
        learner?.stop()
    }

    func shutdown() {
        stopLearningHeadsetButton(restartIfNeeded: false)
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            sleepObserver = nil
        }
        axTimer?.invalidate()
        holdClockTimer?.invalidate()
        audioManager.stopObserving()
        teardownFeatures()
        mapper.releaseAll(reason: l10n.reasonQuit)
        listener?.stop()
    }

    // MARK: - User Actions

    func setEnabled(_ enabled: Bool) {
        guard settings.enabled != enabled else { return }
        settings.enabled = enabled
        settings.save()
        if !enabled {
            stopLearningHeadsetButton()
        }
        syncArrivalWatcher()
        restartListener()
        syncBluetoothTap()
        onStatusBarChange?()
    }

    func setLanguage(_ language: AppLanguage) {
        guard settings.language != language else { return }
        settings.language = language
        L10n.currentLanguage = language
        settings.save()
        if isLearningHeadsetButton {
            lastEvent = l10n.learningPrompt
        } else if hidOpenFailed {
            lastEvent = l10n.hidOpenFailed
        } else if isPausedByAppRule {
            lastEvent = l10n.subtitleAppPaused(activeFrontmostAppName ?? activeAppRule?.appName ?? "")
        } else if !isKeyHeld {
            lastEvent = l10n.readyStatus
        }
        syncFloatingHUD()
        onStatusBarChange?()
    }

    func setKey(_ text: String, for button: HIDButton) {
        updateMapperSettings { $0.setKeyText(text, for: button) }
    }

    func removeCustomButton(_ button: HIDButton) {
        updateMapperSettings { $0.removeCustomButton(button) }
    }

    func setTriggerMode(_ mode: TriggerMode) {
        updateMapperSettings { $0.triggerMode = mode }
    }

    func setHoldMs(_ ms: Int) {
        updateMapperSettings {
            $0.holdMs = ms
            $0.toggle = false
        }
    }

    func setSoundFeedback(_ enabled: Bool) {
        updateMapperSettings { $0.soundFeedback = enabled }
    }

    func setKeyRepeat(_ enabled: Bool) {
        updateMapperSettings { $0.keyRepeat = enabled }
    }

    func updateMapperSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        settings.save()
        saveCurrentHeadsetProfileIfNeeded()
        applyCurrentMapperConfig()
    }

    func applyCurrentMapperConfig() {
        var overrideKey: String? = nil
        if settings.appRulesEnabled, case .overridePlay(let k) = activeAppRule?.action {
            overrideKey = k
        }
        mapper.updateConfig(settings.mapperConfig(verbose: verbose, overridePlayKey: overrideKey))
        toggleTimeoutController.cancel()
        syncFloatingHUD()
    }

    func setSeize(_ enabled: Bool) {
        settings.seize = enabled
        settings.save()
        saveCurrentHeadsetProfileIfNeeded()
        restartListener()
    }

    func selectHIDDevice(vendorID: Int, productID: Int) {
        switchHeadsetDevice(vendorID: vendorID, productID: productID)
    }

    func selectAudioInput(_ id: AudioDeviceID) {
        if AudioInputManager.setDefaultInputDevice(id) {
            let devices = AudioInputManager.listInputDevices()
            if micLock.isEnabled, let chosen = devices.first(where: { $0.id == id }) {
                micLock.lock(to: chosen)
                settings.lockedMicUID = chosen.uid
                settings.lockedMicName = chosen.name
                settings.save()
            }
            refreshAudioInputs()
            if let name = audioInputs.first(where: { $0.id == id })?.name {
                lastEvent = l10n.switchedMic(name)
            }
        }
    }

    func releaseHeldKeysManually() {
        mapper.releaseAll(reason: l10n.reasonManualRelease)
    }

    // MARK: - Universal USB Headset Button Learner

    func startLearningHeadsetButton() {
        stopLearningHeadsetButton()

        // Release current seize temporarily so we can listen across all connected USB headsets.
        isLearningHeadsetButton = true
        syncBluetoothTap()
        lastEvent = l10n.learningPrompt
        mapper.releaseAll(reason: l10n.reasonLearnMode)
        listener?.stop()
        listener = nil
        connectedDevice = nil
        isSeized = false
        hidOpenFailed = false

        let newLearner = HIDButtonLearner { [weak self] device, button in
            DispatchQueue.main.async {
                self?.handleLearnedButton(device: device, button: button)
            }
        }
        if newLearner.start() {
            learner = newLearner
        } else {
            isLearningHeadsetButton = false
            lastEvent = l10n.learningFailed
            if settings.enabled { restartListener() }
        }
        onStatusBarChange?()
    }

    func stopLearningHeadsetButton(restartIfNeeded: Bool = true) {
        guard isLearningHeadsetButton || learner != nil else { return }
        learner?.stop()
        learner = nil
        isLearningHeadsetButton = false
        if !isKeyHeld && lastEvent == l10n.learningPrompt {
            lastEvent = l10n.readyStatus
        }
        if restartIfNeeded && settings.enabled && listener == nil && !isPausedByAppRule {
            restartListener()
        }
        syncBluetoothTap()
        onStatusBarChange?()
    }

    private func handleLearnedButton(device: HIDDeviceInfo, button: HIDButton) {
        guard isLearningHeadsetButton else { return }
        learner?.stop()
        learner = nil
        isLearningHeadsetButton = false

        let deviceChanged = (device.vendorID != settings.vendorID || device.productID != settings.productID)
        if deviceChanged {
            saveCurrentHeadsetProfileIfNeeded()
            if settings.autoSwitchProfiles,
               let existing = profileStore.profile(vendorID: device.vendorID, productID: device.productID) {
                settings.applyProfile(existing)
            } else {
                settings.vendorID = device.vendorID
                settings.productID = device.productID
            }
        }
        settings.ensureButtonExists(button, defaultKey: "f13")
        settings.save()
        refreshDevices()
        saveCurrentHeadsetProfileIfNeeded(deviceNameOverride: device.product)

        applyCurrentMapperConfig()
        if settings.enabled && !isPausedByAppRule {
            restartListener()
        }
        syncBluetoothTap()

        highlightedButton = button
        lastEvent = l10n.learnedButton(product: device.product, button: button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.highlightedButton == button {
                self?.highlightedButton = nil
            }
        }
    }

    // MARK: - Refresh & Permissions

    func refreshAll() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAXPermission {
            hasAXPermission = trusted
            if trusted {
                syncBluetoothTap()
            } else {
                bluetoothTap?.stop()
                isBluetoothTapActive = false
            }
            onStatusBarChange?()
        }
        if !trusted && axTimer == nil {
            startAXWatcher()
        }
        refreshDevices()
        refreshAudioInputs()
        if settings.appRulesEnabled {
            refreshRunningApps()
        }
        if hidOpenFailed && settings.enabled && listener == nil && !isLearningHeadsetButton && !isPausedByAppRule {
            restartListener()
        }
    }

    func refreshDevices() {
        hidDevices = HIDListener.listHeadsetDevices()
    }

    func refreshAudioInputs() {
        audioInputs = AudioInputManager.listInputDevices()
        defaultAudioInputID = AudioInputManager.defaultInputDeviceID()
        micLock.handleAudioChange(devices: audioInputs, currentDefaultID: defaultAudioInputID)
    }

    func openAccessibilitySettings() {
        checkAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        if !hasAXPermission {
            startAXWatcher()
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            LaunchAgentHelper.enable()
        } else {
            LaunchAgentHelper.disable()
        }
        launchAtLogin = LaunchAgentHelper.isEnabled
    }

    // MARK: - Internal

    private func applyMapperSnapshot(_ snap: ButtonMapper.Snapshot) {
        if !isLearningHeadsetButton && !hidOpenFailed && settings.enabled && !isPausedByAppRule {
            lastEvent = snap.summary
        }
        physicalButtons = snap.physicalButtons

        let prevBluetoothHeld = isBluetoothToggleHeld
        isBluetoothToggleHeld = snap.hasBluetoothHeld

        if snap.anyHeld {
            let names = snap.heldCombos.sorted { $0.key < $1.key }.map { $0.value.description }.joined(separator: " / ")
            let wasHeld = (heldSummary != nil)
            heldSummary = names
            if !wasHeld {
                startHoldClock()
            }
            if !wasHeld || prevBluetoothHeld != isBluetoothToggleHeld {
                armOrCancelToggleTimeout(isHeld: true)
            }
        } else {
            heldSummary = nil
            stopHoldClock()
            armOrCancelToggleTimeout(isHeld: false)
        }
        syncFloatingHUD()
        onStatusBarChange?()
    }

    private func startHoldClock() {
        holdStartDate = Date()
        heldSeconds = 0
        holdClockTimer?.invalidate()
        holdClockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.holdStartDate else { return }
            self.heldSeconds = max(0, Int(Date().timeIntervalSince(start)))
            self.syncFloatingHUD()
            self.onStatusBarChange?()
        }
    }

    private func stopHoldClock() {
        holdClockTimer?.invalidate()
        holdClockTimer = nil
        holdStartDate = nil
        heldSeconds = 0
    }

    func restartListener() {
        stopLearningHeadsetButton(restartIfNeeded: false)
        let wasHIDOpenFailed = hidOpenFailed
        mapper.releaseAll(reason: settings.enabled ? l10n.reasonReconnect : l10n.reasonPaused)
        listener?.stop()
        listener = nil
        connectedDevice = nil
        isSeized = false
        hidOpenFailed = false

        guard settings.enabled && !isPausedByAppRule else {
            if !isLearningHeadsetButton && !isKeyHeld && !isPausedByAppRule {
                lastEvent = l10n.readyStatus
            }
            syncBluetoothTap()
            onStatusBarChange?()
            return
        }

        weak var weakListener: HIDListener?
        let newListener = HIDListener(
            vendor: settings.vendorID,
            product: settings.productID,
            onInput: { [weak self] button, down in
                self?.mapper.handle(button: button, down: down)
            },
            onConnect: { [weak self] desc in
                DispatchQueue.main.async {
                    guard let self, let expected = weakListener, self.listener === expected, self.settings.enabled else { return }
                    self.connectedDevice = desc
                    self.hidOpenFailed = false
                    self.refreshDevices()
                    self.onStatusBarChange?()
                }
            },
            onDisconnect: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, let expected = weakListener, self.listener === expected, self.settings.enabled else { return }
                    self.connectedDevice = expected.connectedDevice
                    self.mapper.releaseAll(reason: self.l10n.reasonDisconnected)
                    self.refreshDevices()
                    self.onStatusBarChange?()
                }
            }
        )
        weakListener = newListener

        if newListener.start(seize: settings.seize) {
            listener = newListener
            isSeized = newListener.seized
            mapper.seized = newListener.seized
            connectedDevice = newListener.connectedDevice
            if wasHIDOpenFailed && !isLearningHeadsetButton && !isKeyHeld {
                lastEvent = l10n.readyStatus
            }
        } else {
            hidOpenFailed = true
            lastEvent = l10n.hidOpenFailed
            log(String(format: "cannot open headset 0x%04x/0x%04x", settings.vendorID, settings.productID))
        }
        syncBluetoothTap()
        onStatusBarChange?()
    }

    private func checkAccessibility(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        hasAXPermission = AXIsProcessTrustedWithOptions(opts)
        onStatusBarChange?()
    }

    private func startAXWatcher() {
        axTimer?.invalidate()
        axTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.hasAXPermission {
                self.hasAXPermission = trusted
                if trusted {
                    self.syncBluetoothTap()
                }
                self.onStatusBarChange?()
                if trusted {
                    timer.invalidate()
                    self.axTimer = nil
                }
            }
        }
    }
}

/// Manages ~/Library/LaunchAgents/io.github.cordkey.app.plist for "Launch at Login".
enum LaunchAgentHelper {
    private static let label = "io.github.cordkey.app"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() {
        let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/cordkey-app.log").path

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execPath, "--menubar", "--no-prompt"],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        do {
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            log("enabled launch at login: \(plistURL.path)")
        } catch {
            log("failed to enable launch at login: \(error)")
        }
    }

    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
        log("disabled launch at login")
    }
}
