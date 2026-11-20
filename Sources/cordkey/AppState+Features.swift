import AppKit
import CoreAudio
import Foundation

extension AppState {
    // MARK: - Feature Lifecycle

    func setupFeatures() {
        micLock.onRestored = { [weak self] name in
            guard let self else { return }
            self.refreshAudioInputs()
            self.lastEvent = self.l10n.micLockRestored(name)
        }

        hudController.isEnabled = settings.showFloatingHUD
        hudController.position = settings.hudPosition
        hudController.onReleaseRequested = { [weak self] in
            self?.releaseHeldKeysManually()
        }

        savedProfiles = profileStore.profiles
        syncArrivalWatcher()
        syncAppRulesWatcher()
        syncBluetoothTap()
    }

    func teardownFeatures() {
        arrivalWatcher?.stop()
        arrivalWatcher = nil
        frontmostWatcher?.stop()
        frontmostWatcher = nil
        bluetoothTap?.stop()
        bluetoothTap = nil
        isBluetoothTapActive = false
        toggleTimeoutController.cancel()
        hudController.hide()
    }

    // MARK: - Feature 1: Input Microphone Lock

    func toggleMicLock() {
        if micLock.isEnabled {
            micLock.unlock()
            settings.lockedMicUID = ""
            settings.lockedMicName = ""
            settings.save()
            lastEvent = l10n.micUnlockedStatus
        } else {
            let target = currentAudioInput ?? audioInputs.first
            guard let target else { return }
            micLock.lock(to: target)
            settings.lockedMicUID = target.uid
            settings.lockedMicName = target.name
            settings.save()
            lastEvent = l10n.micLockedStatus(target.name)
        }
    }

    // MARK: - Feature 2: Multi-Headset Profiles & Arrival Watcher

    func setAutoSwitchProfiles(_ enabled: Bool) {
        guard settings.autoSwitchProfiles != enabled else { return }
        settings.autoSwitchProfiles = enabled
        settings.save()
        if enabled {
            saveCurrentHeadsetProfileIfNeeded()
        }
        syncArrivalWatcher()
    }

    func deleteProfile(id: String) {
        profileStore.delete(id: id)
        savedProfiles = profileStore.profiles
    }

    func clearAllProfiles() {
        for p in savedProfiles {
            profileStore.delete(id: p.id)
        }
        savedProfiles = profileStore.profiles
    }

    func currentDeviceDisplayName() -> String {
        if let connected = connectedDevice, !connected.isEmpty {
            return connected
        }
        if let listed = hidDevices.first(where: { $0.vendorID == settings.vendorID && $0.productID == settings.productID }) {
            return listed.product
        }
        return HeadsetProfile.makeKey(vendorID: settings.vendorID, productID: settings.productID)
    }

    func saveCurrentHeadsetProfileIfNeeded(deviceNameOverride: String? = nil) {
        guard settings.autoSwitchProfiles, (settings.vendorID != 0 || settings.productID != 0) else { return }
        let name: String
        if let override = deviceNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty, override != "?" {
            name = override
        } else {
            name = currentDeviceDisplayName()
        }
        let profile = settings.makeProfile(deviceName: name)
        profileStore.save(profile)
        savedProfiles = profileStore.profiles
    }

    func switchHeadsetDevice(vendorID: Int, productID: Int) {
        let changingDevice = (vendorID != settings.vendorID || productID != settings.productID)
        if changingDevice {
            saveCurrentHeadsetProfileIfNeeded()
        }
        if settings.autoSwitchProfiles,
           let saved = profileStore.profile(vendorID: vendorID, productID: productID) {
            settings.applyProfile(saved)
        } else {
            settings.vendorID = vendorID
            settings.productID = productID
        }
        settings.save()
        applyCurrentMapperConfig()
        restartListener()
        syncFloatingHUD()
    }

    func syncArrivalWatcher() {
        if settings.enabled && settings.autoSwitchProfiles {
            if arrivalWatcher == nil {
                let watcher = HeadsetArrivalWatcher()
                watcher.onDeviceArrived = { [weak self] info in
                    self?.handleHeadsetArrived(info)
                }
                if watcher.start() {
                    arrivalWatcher = watcher
                }
            }
        } else {
            arrivalWatcher?.stop()
            arrivalWatcher = nil
        }
    }

    private func handleHeadsetArrived(_ info: HIDDeviceInfo) {
        guard settings.enabled, settings.autoSwitchProfiles, !isLearningHeadsetButton else { return }
        guard info.vendorID != settings.vendorID || info.productID != settings.productID else { return }
        guard let saved = profileStore.profile(vendorID: info.vendorID, productID: info.productID) else { return }

        saveCurrentHeadsetProfileIfNeeded()
        settings.applyProfile(saved)
        settings.save()
        applyCurrentMapperConfig()
        refreshDevices()
        restartListener()
        syncFloatingHUD()
        let label = saved.deviceName.isEmpty ? info.product : saved.deviceName
        lastEvent = l10n.profileSwitchedStatus(label)
    }

    // MARK: - Feature 3: Floating HUD & Toggle Timeout

    func setShowFloatingHUD(_ enabled: Bool) {
        settings.showFloatingHUD = enabled
        settings.save()
        syncFloatingHUD()
    }

    func setHUDPosition(_ position: HUDPosition) {
        settings.hudPosition = position
        settings.save()
        syncFloatingHUD()
    }

    func setToggleTimeoutSeconds(_ seconds: Int) {
        let clamped = max(0, seconds)
        settings.toggleTimeoutSeconds = clamped
        settings.save()
        saveCurrentHeadsetProfileIfNeeded()
        if clamped == 0 {
            toggleTimeoutController.cancel()
        } else {
            armOrCancelToggleTimeout(isHeld: isKeyHeld)
        }
    }

    func syncFloatingHUD() {
        hudController.isEnabled = settings.showFloatingHUD
        hudController.position = settings.hudPosition
        hudController.update(
            heldLabel: heldSummary,
            elapsedSeconds: heldSeconds,
            releaseHint: l10n.hudReleaseHint
        )
    }

    func armOrCancelToggleTimeout(isHeld: Bool) {
        let timeout = settings.toggleTimeoutSeconds
        let shouldArm = isHeld && timeout > 0 && (settings.toggle || isBluetoothToggleHeld)
        if shouldArm {
            toggleTimeoutController.arm(seconds: timeout) { [weak self] in
                guard let self, self.isKeyHeld else { return }
                let reason = self.l10n.reasonToggleTimeout(self.settings.toggleTimeoutSeconds)
                self.mapper.releaseAll(reason: reason)
            }
        } else {
            toggleTimeoutController.cancel()
        }
    }

    // MARK: - Feature 4: Multi-Action Tap / Double-Tap

    func setPlayTapKey(_ text: String) {
        updateMapperSettings { $0.setPlayTapKey(text) }
    }

    func setPlayDoubleTapKey(_ text: String) {
        updateMapperSettings { $0.setPlayDoubleTapKey(text) }
    }

    // MARK: - Feature 5: App-Aware Rules

    func setAppRulesEnabled(_ enabled: Bool) {
        settings.appRulesEnabled = enabled
        settings.save()
        syncAppRulesWatcher()
    }

    func refreshRunningApps() {
        runningApps = FrontmostAppWatcher.listRunningRegularApps()
    }

    func addAppRule(_ rule: AppRule) {
        settings.appRules.removeAll { $0.bundleID.caseInsensitiveCompare(rule.bundleID) == .orderedSame }
        settings.appRules.append(rule)
        settings.save()
        recomputeActiveAppRule()
    }

    func removeAppRule(id: String) {
        settings.appRules.removeAll { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        settings.save()
        recomputeActiveAppRule()
    }

    func toggleAppRule(id: String) {
        guard let idx = settings.appRules.firstIndex(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return }
        settings.appRules[idx].enabled.toggle()
        settings.save()
        recomputeActiveAppRule()
    }

    private func ensureFrontmostWatcher() {
        guard frontmostWatcher == nil else { return }
        let watcher = FrontmostAppWatcher()
        watcher.onFrontmostAppChange = { [weak self] bundleID, appName in
            self?.handleFrontmostAppChange(bundleID: bundleID, appName: appName)
        }
        frontmostWatcher = watcher
        watcher.start()
    }

    func syncAppRulesWatcher() {
        ensureFrontmostWatcher()
        if settings.appRulesEnabled {
            refreshRunningApps()
            recomputeActiveAppRule()
        } else {
            let wasPaused = isPausedByAppRule
            let hadRule = (activeAppRule != nil)
            isPausedByAppRule = false
            activeAppRule = nil
            activeFrontmostAppName = nil
            if hadRule || wasPaused {
                applyCurrentMapperConfig()
            }
            if wasPaused && settings.enabled {
                restartListener()
            }
            if wasPaused && !isLearningHeadsetButton && !isKeyHeld && !hidOpenFailed {
                lastEvent = l10n.readyStatus
            }
            syncBluetoothTap()
            onStatusBarChange?()
        }
    }

    private func handleFrontmostAppChange(bundleID: String?, appName: String?) {
        guard settings.appRulesEnabled else { return }
        activeFrontmostAppName = appName
        recomputeActiveAppRule(bundleID: bundleID, appName: appName)
    }

    func recomputeActiveAppRule(bundleID: String? = nil, appName: String? = nil) {
        guard settings.appRulesEnabled else { return }
        let resolvedBundleID = bundleID ?? frontmostWatcher?.currentBundleID
        let resolvedAppName = appName ?? frontmostWatcher?.currentAppName
        let matched = FrontmostAppWatcher.matchingRule(for: resolvedBundleID, in: settings.appRules)

        let prevPaused = isPausedByAppRule
        let prevRule = activeAppRule
        activeAppRule = matched
        activeFrontmostAppName = resolvedAppName

        if let matched, matched.action == .pause {
            isPausedByAppRule = true
            let appLabel = resolvedAppName ?? matched.appName
            mapper.releaseAll(reason: l10n.reasonAppRulePaused(appLabel))
            listener?.stop()
            listener = nil
            connectedDevice = nil
            isSeized = false
            hidOpenFailed = false
            syncBluetoothTap()
            if !prevPaused {
                lastEvent = l10n.subtitleAppPaused(appLabel)
            }
            onStatusBarChange?()
            return
        }

        isPausedByAppRule = false
        if matched != prevRule || prevPaused {
            applyCurrentMapperConfig()
        }
        if prevPaused && settings.enabled && listener == nil && !isLearningHeadsetButton {
            restartListener()
        }
        if prevPaused && matched == nil && !isKeyHeld {
            lastEvent = l10n.readyStatus
        }
        syncBluetoothTap()
        onStatusBarChange?()
    }

    // MARK: - Feature 6: Bluetooth Compatibility Mode

    func setBluetoothMode(_ enabled: Bool) {
        settings.bluetoothMode = enabled
        settings.save()
        if !enabled {
            bluetoothTapFailed = false
            if isBluetoothToggleHeld || mapper.hasPendingBluetoothToggle {
                isBluetoothToggleHeld = false
                mapper.releaseAll(reason: l10n.reasonPaused)
            }
        }
        syncBluetoothTap()
        onStatusBarChange?()
    }

    func syncBluetoothTap() {
        let shouldRun = settings.enabled && settings.bluetoothMode && !isPausedByAppRule && !isLearningHeadsetButton
        if shouldRun {
            if bluetoothTap == nil {
                let tap = BluetoothMediaTap(
                    shouldIntercept: { [weak self] in
                        guard let self else { return false }
                        return self.settings.enabled
                            && !self.isPausedByAppRule
                            && !self.isLearningHeadsetButton
                            && self.connectedDevice == nil
                    },
                    onPlayEvent: { [weak self] down in
                        self?.mapper.handleBluetoothPlay(down: down)
                    }
                )
                bluetoothTap = tap
            }
            if let tap = bluetoothTap {
                let wasFailed = bluetoothTapFailed
                let ok = tap.start()
                isBluetoothTapActive = ok
                bluetoothTapFailed = !ok
                if !ok {
                    lastEvent = l10n.bluetoothTapFailedStatus
                } else if (wasFailed || lastEvent == l10n.bluetoothTapFailedStatus)
                            && !isLearningHeadsetButton && !isKeyHeld && !hidOpenFailed {
                    lastEvent = isPausedByAppRule
                        ? l10n.subtitleAppPaused(activeFrontmostAppName ?? activeAppRule?.appName ?? "")
                        : l10n.readyStatus
                }
            }
        } else {
            bluetoothTap?.stop()
            isBluetoothTapActive = false
            if !settings.bluetoothMode {
                bluetoothTapFailed = false
                if isBluetoothToggleHeld || mapper.hasPendingBluetoothToggle {
                    isBluetoothToggleHeld = false
                    mapper.releaseAll(reason: l10n.reasonPaused)
                }
            }
        }
    }
}
