import AppKit
import CoreGraphics
import Foundation

/// Optional Bluetooth headset compatibility mode via a session-level `CGEventTap`.
///
/// Bluetooth headsets (AirPods, Sony WH/WF, Bose, Beats) report media buttons over AVRCP,
/// which macOS injects directly into the window server as `NX_SYSDEFINED` (`type == 14`,
/// `subtype == 8`) events rather than HID Consumer usages. When enabled, `BluetoothMediaTap`
/// intercepts system Play/Pause (`keyCode == 16`), swallows the original event so Apple Music /
/// Spotify do not react, and forwards `(down: Bool)` to `onPlayEvent`.
///
/// Note: Bluetooth AVRCP typically emits instant `down` + `up` pulses on press, so this pairs
/// cleanly with Click-Toggle mode (or single-shot mapped play actions).
final class BluetoothMediaTap {
    /// Magic `eventSourceUserData` value identifying synthetic media events posted by CordKey.
    ///
    /// Integrator note: In `KeyEmitter.sendMedia(_:down:isRepeat:)`, tag the `CGEvent` before posting:
    /// ```swift
    /// if let cg = ev?.cgEvent {
    ///     cg.setIntegerValueField(.eventSourceUserData, value: BluetoothMediaTap.syntheticEventTag)
    ///     cg.post(tap: .cghidEventTap)
    /// }
    /// ```
    /// `"CKMD"` (`0x434B_4D44`) ensures `BluetoothMediaTap` never re-intercepts CordKey's own
    /// passthrough media events.
    static let syntheticEventTag: Int64 = 0x434B_4D44

    private static let nxSysDefinedType: UInt32 = 14
    private static let mediaSubtype: Int16 = 8
    private static let playPauseKeyCode: Int = 16
    private static let keyStateDown: Int = 0xA
    private static let keyStateUp: Int = 0xB

    /// Optional predicate checked before swallowing a Play/Pause event.
    /// Return `false` to pass the event through unmodified (e.g. when a USB headset is seized
    /// or when CordKey is paused by an App Rule). Defaults to intercepting when `nil`.
    var shouldIntercept: (() -> Bool)?

    /// Invoked asynchronously on `DispatchQueue.main` with `true` on key down and `false` on key up.
    var onPlayEvent: ((Bool) -> Void)?

    /// `true` while the `CGEventTap` is installed on the main run loop.
    var isRunning: Bool {
        tap != nil
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        shouldIntercept: (() -> Bool)? = nil,
        onPlayEvent: ((Bool) -> Void)? = nil
    ) {
        self.shouldIntercept = shouldIntercept
        self.onPlayEvent = onPlayEvent
    }

    deinit {
        stop()
    }

    /// Installs and enables the `CGEventTap` on the main run loop (`.commonModes`).
    ///
    /// - Returns: `true` if the tap is active; `false` if macOS denied tap creation
    ///   (typically missing Accessibility permission) so the UI can prompt the user.
    @discardableResult
    func start() -> Bool {
        if tap != nil {
            return true
        }

        let sysDefinedMask: CGEventMask = 1 << Self.nxSysDefinedType
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: sysDefinedMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0) else {
            CFMachPortInvalidate(createdTap)
            return false
        }

        self.tap = createdTap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        return true
    }

    /// Disables the tap, detaches its `CFRunLoopSource` from the main run loop,
    /// and invalidates the underlying `CFMachPort`.
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let instance = Unmanaged<BluetoothMediaTap>.fromOpaque(userInfo).takeUnretainedValue()
        return instance.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.nxSysDefinedType else {
            return Unmanaged.passUnretained(event)
        }

        // Never intercept CordKey's own synthetic media passthrough events.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventTag else {
            return Unmanaged.passUnretained(event)
        }

        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.mediaSubtype else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
        let keyFlags = ns.data1 & 0x0000_FFFF
        let state = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x1) != 0

        guard keyCode == Self.playPauseKeyCode,
              !isRepeat,
              state == Self.keyStateDown || state == Self.keyStateUp
        else {
            return Unmanaged.passUnretained(event)
        }

        guard shouldIntercept?() ?? true else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = (state == Self.keyStateDown)
        DispatchQueue.main.async { [weak self] in
            self?.onPlayEvent?(isDown)
        }
        return nil
    }
}
