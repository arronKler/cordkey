import CoreAudio
import Foundation

/// Prevents macOS from silently switching the default audio input (e.g., when
/// plugging in EarPods or USB headsets) by restoring the user's locked mic.
final class MicLockController {
    var lockedUID: String?
    var lockedName: String?

    var isEnabled: Bool {
        guard let uid = lockedUID else { return false }
        return !uid.isEmpty
    }

    /// Invoked on the main queue after a stolen default input is automatically
    /// restored to the locked microphone.
    var onRestored: ((_ deviceName: String) -> Void)?

    private let restoreDelay: TimeInterval = 0.25
    private let restoreCooldown: TimeInterval = 0.4
    private var pendingRestoreWorkItem: DispatchWorkItem?
    private var lastRestoreTime: TimeInterval?

    init(lockedUID: String? = nil, lockedName: String? = nil) {
        self.lockedUID = lockedUID
        self.lockedName = lockedName
    }

    deinit {
        pendingRestoreWorkItem?.cancel()
    }

    func lock(to device: AudioInputDevice) {
        cancelPendingRestore()
        lockedUID = device.uid
        lockedName = device.name
        lastRestoreTime = nil
    }

    func unlock() {
        cancelPendingRestore()
        lockedUID = nil
        lockedName = nil
        lastRestoreTime = nil
    }

    /// Evaluates an audio topology or default-input change and schedules a
    /// debounced restore if another device stole the default input.
    /// Returns `true` when a restore attempt was scheduled.
    @discardableResult
    func handleAudioChange(devices: [AudioInputDevice], currentDefaultID: AudioDeviceID?) -> Bool {
        guard isEnabled else {
            cancelPendingRestore()
            return false
        }

        guard let target = findTargetDevice(in: devices) else {
            // Locked mic is not currently connected; leave audio untouched.
            cancelPendingRestore()
            return false
        }

        guard currentDefaultID != target.id else {
            cancelPendingRestore()
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        let remainingCooldown: TimeInterval
        if let last = lastRestoreTime {
            remainingCooldown = max(0, restoreCooldown - (now - last))
        } else {
            remainingCooldown = 0
        }
        let delay = max(restoreDelay, remainingCooldown)

        scheduleRestore(after: delay)
        return true
    }

    private func scheduleRestore(after delay: TimeInterval) {
        cancelPendingRestore()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRestore()
        }
        pendingRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performRestore() {
        pendingRestoreWorkItem = nil
        guard isEnabled else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastRestoreTime, now - last < restoreCooldown {
            let remaining = restoreCooldown - (now - last)
            scheduleRestore(after: remaining + 0.01)
            return
        }

        let devices = AudioInputManager.listInputDevices()
        guard let target = findTargetDevice(in: devices) else { return }
        guard AudioInputManager.defaultInputDeviceID() != target.id else { return }

        lastRestoreTime = now
        if AudioInputManager.setDefaultInputDevice(target.id) {
            onRestored?(target.name)
        }
    }

    private func findTargetDevice(in devices: [AudioInputDevice]) -> AudioInputDevice? {
        if let uid = lockedUID, !uid.isEmpty,
           let match = devices.first(where: { $0.uid == uid }) {
            return match
        }
        if let name = lockedName, !name.isEmpty {
            return devices.first(where: { $0.name == name })
        }
        return nil
    }

    private func cancelPendingRestore() {
        pendingRestoreWorkItem?.cancel()
        pendingRestoreWorkItem = nil
    }
}
