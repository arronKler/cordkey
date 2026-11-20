import AppKit
import Foundation

/// Subtle system sound cues for key engage/release (especially helpful in toggle or hold-delay mode).
enum SoundCue {
    private static func play(_ name: String, volume: Float) {
        DispatchQueue.main.async {
            guard let s = NSSound(named: NSSound.Name(name)) else { return }
            s.volume = volume
            s.play()
        }
    }

    static func engaged() { play("Tink", volume: 0.35) }
    static func released() { play("Pop", volume: 0.30) }
}

/// Routes headset button transitions (Consumer 0x0C & Telephony 0x0B) to synthetic keyboard events
/// or media passthrough, handling deduplication, clean-audio toggle mode, hold-threshold tap passthrough,
/// repeat timers, and guaranteed release of all held keys on disconnect or exit.
final class ButtonMapper {
    struct Config {
        let mappings: [HIDButton: KeyCombo]
        let tapCombos: [HIDButton: KeyCombo]
        let doubleTapCombos: [HIDButton: KeyCombo]
        let toggle: Bool
        let holdMs: Int
        let keyRepeat: Bool
        let soundFeedback: Bool
        let verbose: Bool

        init(
            mappings: [HIDButton: KeyCombo],
            tapCombos: [HIDButton: KeyCombo] = [:],
            doubleTapCombos: [HIDButton: KeyCombo] = [:],
            toggle: Bool,
            holdMs: Int,
            keyRepeat: Bool,
            soundFeedback: Bool,
            verbose: Bool
        ) {
            self.mappings = mappings
            self.tapCombos = tapCombos
            self.doubleTapCombos = doubleTapCombos
            self.toggle = toggle
            self.holdMs = holdMs
            self.keyRepeat = keyRepeat
            self.soundFeedback = soundFeedback
            self.verbose = verbose
        }
    }

    struct Snapshot {
        let summary: String
        let physicalButtons: Set<HIDButton>
        let heldCombos: [HIDButton: KeyCombo]
        let hasBluetoothHeld: Bool
        var anyHeld: Bool { !heldCombos.isEmpty }
    }

    private static let passthrough: [HIDButton: KeyEmitter.MediaKey] = [
        .play: .play,
        .volUp: .soundUp,
        .volDown: .soundDown,
        .mute: .mute,
        .next: .next,
        .prev: .previous,
    ]

    private var config: Config
    var seized = false
    var onStateChange: ((Snapshot) -> Void)?

    /// Physical buttons currently depressed.
    private var physicalDown: Set<HIDButton> = []
    /// Synthetic combos currently held down (keyed by source headset button).
    private var heldCombos: [HIDButton: KeyCombo] = [:]
    /// Synthetic combos currently held via Bluetooth AVRCP Play/Pause.
    private var bluetoothHeldButtons: Set<HIDButton> = []
    /// Tracks Bluetooth-initiated toggle-on settle timers pending engage.
    private var bluetoothPendingToggleButtons: Set<HIDButton> = []
    /// Multi-action state machine for hold-delay mode (hold + short tap + double tap).
    private let multiActionRouter = MultiActionRouter()
    /// Short settle timers for toggle-on (waits 60ms after release so EarPods mic un-shorts cleanly).
    private var toggleOnTimers: [HIDButton: DispatchSourceTimer] = [:]
    /// Tracks 2nd press in toggle mode so its matching release doesn't re-trigger toggle-on.
    private var toggleIgnoreNextUp: Set<HIDButton> = []
    /// Active key-repeat timers (when `--repeat` is enabled).
    private var keyRepeatTimers: [HIDButton: DispatchSourceTimer] = [:]
    /// Active passthrough volume-repeat timers (when seized and vol buttons are unmapped).
    private var mediaRepeatTimers: [HIDButton: DispatchSourceTimer] = [:]
    /// Passthrough media keys currently held down.
    private var activePassthroughMedia: [HIDButton: KeyEmitter.MediaKey] = [:]

    init(config: Config) {
        self.config = config
        multiActionRouter.onOutcome = { [weak self] outcome in
            self?.handleMultiActionOutcome(outcome)
        }
    }

    func updateConfig(_ newConfig: Config) {
        releaseAll(reason: L10n.current.reasonConfigUpdated)
        self.config = newConfig
    }

    func handle(button: HIDButton, down: Bool) {
        // Deduplicate repeated states or spurious release events.
        if down {
            guard physicalDown.insert(button).inserted else { return }
        } else {
            guard physicalDown.remove(button) != nil else { return }
        }

        if config.verbose {
            log("button \(button.shortName) [\(button.codeTag)] \(down ? "down" : "up")")
        }

        let l10n = L10n.current
        if let combo = config.mappings[button] {
            handleMapped(button: button, combo: combo, down: down)
        } else if seized, let media = Self.passthrough[button] {
            handlePassthrough(button: button, media: media, down: down)
            emitSnapshot(l10n.eventPassthrough(button, down: down))
        } else {
            emitSnapshot(l10n.eventRaw(button, down: down))
        }
    }

    var hasPendingBluetoothToggle: Bool { !bluetoothPendingToggleButtons.isEmpty }

    /// Routes Bluetooth AVRCP Play/Pause pulses (`down`/`up`) through Click-Toggle semantics
    /// when `.play` is mapped, or passes through native Play/Pause when unmapped.
    func handleBluetoothPlay(down: Bool) {
        if down {
            guard physicalDown.insert(.play).inserted else { return }
        } else {
            guard physicalDown.remove(.play) != nil else { return }
        }

        if config.verbose {
            log("bluetooth play \(down ? "down" : "up")")
        }

        if let combo = config.mappings[.play] {
            handleToggle(button: .play, combo: combo, down: down, isBluetooth: true)
        } else {
            KeyEmitter.sendMedia(.play, down: down)
            emitSnapshot(L10n.current.eventPassthrough(.play, down: down))
        }
    }

    /// Release every currently held synthetic key and cancel all timers.
    func releaseAll(reason: String) {
        _ = multiActionRouter.cancelAll()
        for (_, t) in toggleOnTimers { t.cancel() }
        toggleOnTimers.removeAll()
        bluetoothPendingToggleButtons.removeAll()
        toggleIgnoreNextUp.removeAll()
        for (_, t) in keyRepeatTimers { t.cancel() }
        keyRepeatTimers.removeAll()
        for (_, t) in mediaRepeatTimers { t.cancel() }
        mediaRepeatTimers.removeAll()
        let hadPhysical = !physicalDown.isEmpty
        physicalDown.removeAll()
        bluetoothHeldButtons.removeAll()

        let activeMedia = activePassthroughMedia
        activePassthroughMedia.removeAll()
        for (button, media) in activeMedia.sorted(by: { $0.key < $1.key }) {
            KeyEmitter.sendMedia(media, down: false)
            log("released passthrough \(button.shortName) (\(reason))")
        }

        let activeButtons = heldCombos.keys.sorted()
        let hadHeldCombos = !activeButtons.isEmpty
        for button in activeButtons {
            guard let combo = heldCombos[button] else { continue }
            let extra = otherHeldFlags(excluding: button)
            heldCombos.removeValue(forKey: button)
            KeyEmitter.send(combo, down: false, extraFlags: extra)
            log("released \(combo) (\(reason))")
        }
        if hadHeldCombos {
            if config.soundFeedback { SoundCue.released() }
            emitSnapshot(L10n.current.eventReleasedAll(reason))
        } else if !activeMedia.isEmpty {
            emitSnapshot(L10n.current.eventReleasedAll(reason))
        } else if hadPhysical {
            emitSnapshot(reason)
        }
    }

    // MARK: - Mapped button logic

    private func handleMapped(button: HIDButton, combo: KeyCombo, down: Bool) {
        if config.toggle {
            handleToggle(button: button, combo: combo, down: down)
            return
        }

        if config.holdMs > 0 {
            let maConfig = MultiActionConfig(
                holdCombo: combo,
                tapCombo: config.tapCombos[button],
                doubleTapCombo: config.doubleTapCombos[button],
                holdMs: config.holdMs
            )
            multiActionRouter.handle(button: button, down: down, config: maConfig)
            return
        }

        // Standard immediate hold-to-hold mode.
        if down {
            pressCombo(button: button, combo: combo, label: "pressed ")
        } else if heldCombos[button] != nil {
            releaseCombo(button: button, combo: combo, label: "released")
        }
    }

    private func handleMultiActionOutcome(_ outcome: MultiActionOutcome) {
        let l10n = L10n.current
        switch outcome {
        case .pressing(let button):
            emitSnapshot(l10n.eventHolding(button))
        case .holdStarted(let button, let combo):
            pressCombo(button: button, combo: combo, label: "held")
        case .holdEnded(let button, let combo):
            releaseCombo(button: button, combo: combo, label: "released")
        case .singleTapKey(let button, let combo):
            sendTap(combo, button: button, label: "tapped")
            emitSnapshot(l10n.eventTapKey(button, combo: combo))
        case .singleTapPassthrough(let button):
            if seized, let media = Self.passthrough[button] {
                KeyEmitter.sendMedia(media, down: true)
                KeyEmitter.sendMedia(media, down: false)
                log("\(button.shortName) tapped → passthrough")
                emitSnapshot(l10n.eventTapPassthrough(button))
            } else {
                emitSnapshot(l10n.eventTap(button))
            }
        case .doubleTapKey(let button, let combo):
            sendTap(combo, button: button, label: "double-tapped")
            emitSnapshot(l10n.eventDoubleTapKey(button, combo: combo))
        }
    }

    private func sendTap(_ combo: KeyCombo, button: HIDButton, label: String) {
        let extra = otherHeldFlags(excluding: button)
        KeyEmitter.send(combo, down: true, extraFlags: extra)
        KeyEmitter.send(combo, down: false, extraFlags: extra)
        if config.soundFeedback { SoundCue.engaged() }
        log("\(button.shortName) \(label) → \(combo)")
    }

    /// Clean-audio toggle:
    /// - 1st click: engages 60ms *after* button release so mic is completely un-shorted (no click noise).
    /// - 2nd click: releases *immediately* on button down so the 2nd click is not captured in speech.
    private func handleToggle(button: HIDButton, combo: KeyCombo, down: Bool, isBluetooth: Bool = false) {
        let l10n = L10n.current
        if down {
            if let pending = toggleOnTimers.removeValue(forKey: button) {
                pending.cancel()
                bluetoothPendingToggleButtons.remove(button)
                toggleIgnoreNextUp.insert(button)
                emitSnapshot(l10n.eventTriggerCancelled(button))
                return
            }
            if heldCombos[button] != nil {
                toggleIgnoreNextUp.insert(button)
                releaseCombo(button: button, combo: combo, label: "toggled off")
            } else {
                emitSnapshot(l10n.eventToggleArmed(button, combo: combo))
            }
        } else {
            if toggleIgnoreNextUp.remove(button) != nil {
                emitSnapshot(l10n.eventReleased(button))
                return
            }
            guard heldCombos[button] == nil else { return }
            if isBluetooth {
                bluetoothPendingToggleButtons.insert(button)
            } else {
                bluetoothPendingToggleButtons.remove(button)
            }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(60))
            timer.setEventHandler { [weak self, weak timer] in
                guard let self, let timer, !timer.isCancelled, self.toggleOnTimers[button] === timer else { return }
                self.toggleOnTimers.removeValue(forKey: button)
                let fromBluetooth = self.bluetoothPendingToggleButtons.remove(button) != nil
                self.pressCombo(button: button, combo: combo, label: "toggled on", isBluetooth: fromBluetooth)
            }
            toggleOnTimers[button]?.cancel()
            toggleOnTimers[button] = timer
            timer.resume()
        }
    }

    private func pressCombo(button: HIDButton, combo: KeyCombo, label: String, isBluetooth: Bool = false) {
        let extra = otherHeldFlags(excluding: button)
        heldCombos[button] = combo
        if isBluetooth {
            bluetoothHeldButtons.insert(button)
        } else {
            bluetoothHeldButtons.remove(button)
        }
        KeyEmitter.send(combo, down: true, extraFlags: extra)
        if config.soundFeedback { SoundCue.engaged() }
        log("\(button.shortName) \(label) → \(combo) down")
        emitSnapshot(L10n.current.eventEngaged(button, combo: combo))

        if config.keyRepeat && combo.hasNonModifier {
            startKeyRepeat(button: button, combo: combo)
        }
    }

    private func releaseCombo(button: HIDButton, combo: KeyCombo, label: String) {
        stopKeyRepeat(button: button)
        heldCombos.removeValue(forKey: button)
        bluetoothHeldButtons.remove(button)
        let extra = otherHeldFlags(excluding: button)
        KeyEmitter.send(combo, down: false, extraFlags: extra)
        if config.soundFeedback { SoundCue.released() }
        log("\(button.shortName) \(label) → \(combo) up")
        emitSnapshot(L10n.current.eventDisengaged(button, combo: combo))
    }

    private func emitSnapshot(_ summary: String) {
        onStateChange?(Snapshot(
            summary: summary,
            physicalButtons: physicalDown,
            heldCombos: heldCombos,
            hasBluetoothHeld: !bluetoothHeldButtons.isEmpty
        ))
    }

    private func otherHeldFlags(excluding button: HIDButton) -> UInt64 {
        var mask: UInt64 = 0
        for (b, c) in heldCombos where b != button {
            for k in c.keys {
                if let m = k.modifierMask { mask |= m }
            }
        }
        return mask
    }

    private func startKeyRepeat(button: HIDButton, combo: KeyCombo) {
        stopKeyRepeat(button: button)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer, !timer.isCancelled, self.keyRepeatTimers[button] === timer else { return }
            guard self.heldCombos[button] != nil else { return }
            KeyEmitter.sendRepeat(combo, extraFlags: self.otherHeldFlags(excluding: button))
        }
        keyRepeatTimers[button] = timer
        timer.resume()
    }

    private func stopKeyRepeat(button: HIDButton) {
        if let t = keyRepeatTimers.removeValue(forKey: button) { t.cancel() }
    }

    // MARK: - Passthrough for unmapped buttons while seized

    private func handlePassthrough(button: HIDButton, media: KeyEmitter.MediaKey, down: Bool) {
        if down {
            activePassthroughMedia[button] = media
            KeyEmitter.sendMedia(media, down: true)
            if media == .soundUp || media == .soundDown {
                startMediaRepeat(button: button, media: media)
            }
        } else {
            activePassthroughMedia.removeValue(forKey: button)
            stopMediaRepeat(button: button)
            KeyEmitter.sendMedia(media, down: false)
        }
    }

    private func startMediaRepeat(button: HIDButton, media: KeyEmitter.MediaKey) {
        stopMediaRepeat(button: button)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: .milliseconds(80))
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer, !timer.isCancelled, self.mediaRepeatTimers[button] === timer else { return }
            guard self.physicalDown.contains(button) else { return }
            KeyEmitter.sendMedia(media, down: true, isRepeat: true)
        }
        mediaRepeatTimers[button] = timer
        timer.resume()
    }

    private func stopMediaRepeat(button: HIDButton) {
        if let t = mediaRepeatTimers.removeValue(forKey: button) { t.cancel() }
    }
}
