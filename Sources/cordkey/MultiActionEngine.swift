import Foundation

/// Per-button multi-action configuration combining Hold, Short Tap, and optional Double-Tap.
struct MultiActionConfig {
    /// Key or chord held down once the physical press reaches `holdMs`.
    let holdCombo: KeyCombo
    /// Optional shortcut tapped on a short press; `nil` passes through the native media key when seized.
    let tapCombo: KeyCombo?
    /// Optional shortcut tapped when two short presses occur within `doubleTapWindowMs`.
    let doubleTapCombo: KeyCombo?
    /// Press duration threshold (in milliseconds) before transitioning into hold.
    let holdMs: Int
    /// Maximum gap (in milliseconds) after a short release to wait for a second tap.
    let doubleTapWindowMs: Int

    init(
        holdCombo: KeyCombo,
        tapCombo: KeyCombo? = nil,
        doubleTapCombo: KeyCombo? = nil,
        holdMs: Int,
        doubleTapWindowMs: Int = 280
    ) {
        self.holdCombo = holdCombo
        self.tapCombo = tapCombo
        self.doubleTapCombo = doubleTapCombo
        self.holdMs = holdMs
        self.doubleTapWindowMs = doubleTapWindowMs
    }
}

/// Logical action outcomes emitted by `MultiActionRouter` for a headset button.
enum MultiActionOutcome {
    /// Hold threshold elapsed while the button remained pressed; caller should press `KeyCombo` down.
    case holdStarted(HIDButton, KeyCombo)
    /// Held button was physically released; caller should release `KeyCombo`.
    case holdEnded(HIDButton, KeyCombo)
    /// Single short tap resolved; caller should tap `KeyCombo` (down + up).
    case singleTapKey(HIDButton, KeyCombo)
    /// Single short tap resolved with `tapCombo == nil`; caller should pass through native media key.
    case singleTapPassthrough(HIDButton)
    /// Double-tap resolved on the second press down; caller should tap `KeyCombo` (down + up).
    /// Note: Fires immediately on the 2nd press down for minimal latency; the matching 2nd release is swallowed.
    case doubleTapKey(HIDButton, KeyCombo)
    /// Initial physical press started and is waiting for `holdMs` to determine tap vs hold.
    case pressing(HIDButton)
}

/// State machine routing physical press/release transitions for one or more `HIDButton`s
/// into single-tap, double-tap, and hold outcomes with zero extra delay when double-tap is unconfigured.
final class MultiActionRouter {
    private struct PendingDoubleTap {
        let timer: DispatchSourceTimer
        let tapCombo: KeyCombo?
        let doubleTapCombo: KeyCombo
    }

    var onOutcome: ((MultiActionOutcome) -> Void)?

    private let queue: DispatchQueue
    private var physicalDown: Set<HIDButton> = []
    private var heldCombos: [HIDButton: KeyCombo] = [:]
    private var holdTimers: [HIDButton: DispatchSourceTimer] = [:]
    private var doubleTapTimers: [HIDButton: PendingDoubleTap] = [:]
    /// Tracks buttons whose 2nd press already triggered `.doubleTapKey` on down so the matching release is swallowed.
    private var awaitingDoubleTapRelease: Set<HIDButton> = []

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    deinit {
        _ = cancelAll()
    }

    /// Processes a physical button press (`down == true`) or release (`down == false`).
    ///
    /// Double-tap timing behavior:
    /// - When `config.doubleTapCombo == nil`, releasing before `holdMs` emits `.singleTapKey` or
    ///   `.singleTapPassthrough` immediately with zero extra delay.
    /// - When `config.doubleTapCombo != nil`, releasing before `holdMs` arms a `doubleTapWindowMs` timer.
    ///   A second press within that window cancels the timer and fires `.doubleTapKey` immediately on press down;
    ///   the matching second release is swallowed (`awaitingDoubleTapRelease`) without starting a hold.
    func handle(button: HIDButton, down: Bool, config: MultiActionConfig) {
        if down {
            guard physicalDown.insert(button).inserted else { return }
            handlePressDown(button: button, config: config)
        } else {
            guard physicalDown.remove(button) != nil else { return }
            handleReleaseUp(button: button, config: config)
        }
    }

    /// Cancels all pending hold and double-tap timers, resets internal state,
    /// and returns any buttons currently in `.held` state (sorted by button) so the caller can release them safely.
    @discardableResult
    func cancelAll() -> [(HIDButton, KeyCombo)] {
        for (_, timer) in holdTimers { timer.cancel() }
        holdTimers.removeAll()

        for (_, pending) in doubleTapTimers { pending.timer.cancel() }
        doubleTapTimers.removeAll()

        physicalDown.removeAll()
        awaitingDoubleTapRelease.removeAll()

        let active = heldCombos.keys.sorted().compactMap { button -> (HIDButton, KeyCombo)? in
            guard let combo = heldCombos[button] else { return nil }
            return (button, combo)
        }
        heldCombos.removeAll()
        return active
    }

    /// Returns whether `button` is currently in the held state.
    func isHeld(_ button: HIDButton) -> Bool {
        heldCombos[button] != nil
    }

    // MARK: - Private transitions

    private func handlePressDown(button: HIDButton, config: MultiActionConfig) {
        // Second press arriving within the double-tap window fires immediately on down.
        if let pending = doubleTapTimers.removeValue(forKey: button) {
            pending.timer.cancel()
            holdTimers.removeValue(forKey: button)?.cancel()
            let combo = config.doubleTapCombo ?? pending.doubleTapCombo
            awaitingDoubleTapRelease.insert(button)
            onOutcome?(.doubleTapKey(button, combo))
            return
        }

        if config.holdMs <= 0 {
            heldCombos[button] = config.holdCombo
            onOutcome?(.holdStarted(button, config.holdCombo))
            return
        }

        armHoldTimer(for: button, config: config)
        onOutcome?(.pressing(button))
    }

    private func handleReleaseUp(button: HIDButton, config: MultiActionConfig) {
        if awaitingDoubleTapRelease.remove(button) != nil {
            return
        }

        if let heldCombo = heldCombos.removeValue(forKey: button) {
            onOutcome?(.holdEnded(button, heldCombo))
            return
        }

        guard let pendingHold = holdTimers.removeValue(forKey: button) else { return }
        pendingHold.cancel()

        guard let doubleTapCombo = config.doubleTapCombo, config.doubleTapWindowMs > 0 else {
            emitSingleTap(button: button, tapCombo: config.tapCombo)
            return
        }

        armDoubleTapTimer(
            for: button,
            tapCombo: config.tapCombo,
            doubleTapCombo: doubleTapCombo,
            windowMs: config.doubleTapWindowMs
        )
    }

    private func armHoldTimer(for button: HIDButton, config: MultiActionConfig) {
        holdTimers[button]?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(config.holdMs))
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer, !timer.isCancelled, self.holdTimers[button] === timer else { return }
            self.holdTimers.removeValue(forKey: button)
            guard self.physicalDown.contains(button) else { return }

            if let pendingTap = self.doubleTapTimers.removeValue(forKey: button) {
                pendingTap.timer.cancel()
            }
            self.heldCombos[button] = config.holdCombo
            self.onOutcome?(.holdStarted(button, config.holdCombo))
        }
        holdTimers[button] = timer
        timer.resume()
    }

    private func armDoubleTapTimer(
        for button: HIDButton,
        tapCombo: KeyCombo?,
        doubleTapCombo: KeyCombo,
        windowMs: Int
    ) {
        doubleTapTimers[button]?.timer.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(windowMs))
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer, !timer.isCancelled, self.doubleTapTimers[button]?.timer === timer else { return }
            guard let pending = self.doubleTapTimers.removeValue(forKey: button) else { return }
            self.emitSingleTap(button: button, tapCombo: pending.tapCombo)
        }
        doubleTapTimers[button] = PendingDoubleTap(
            timer: timer,
            tapCombo: tapCombo,
            doubleTapCombo: doubleTapCombo
        )
        timer.resume()
    }

    private func emitSingleTap(button: HIDButton, tapCombo: KeyCombo?) {
        if let tapCombo {
            onOutcome?(.singleTapKey(button, tapCombo))
        } else {
            onOutcome?(.singleTapPassthrough(button))
        }
    }
}
