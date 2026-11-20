import AppKit
import CoreGraphics

/// Posts synthetic keyboard and media events. Requires Accessibility permission
/// for the process (or the terminal that launched it); otherwise macOS drops them silently.
enum KeyEmitter {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Press (down=true) or release (down=false) a combo.
    /// `extraFlags` carries any modifier bits held by other active mappings.
    static func send(_ combo: KeyCombo, down: Bool, extraFlags: UInt64 = 0) {
        let ordered = down ? combo.keys : combo.keys.reversed()

        // Track which modifier keys inside this combo are currently active at each step.
        var activeModIndices: [Int] = down ? [] : combo.keys.indices.filter { combo.keys[$0].isModifier }

        func currentFlags() -> CGEventFlags {
            var raw = extraFlags
            for idx in activeModIndices {
                if let m = combo.keys[idx].modifierMask { raw |= m }
            }
            return CGEventFlags(rawValue: raw)
        }

        for (stepIdx, key) in ordered.enumerated() {
            let origIdx = down ? stepIdx : (combo.keys.count - 1 - stepIdx)
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: down) else { continue }
            if key.isModifier {
                if down {
                    activeModIndices.append(origIdx)
                } else {
                    activeModIndices.removeAll { $0 == origIdx }
                }
                ev.type = .flagsChanged
            }
            ev.flags = currentFlags()
            ev.post(tap: .cghidEventTap)
        }
    }

    /// Post an autorepeat keyDown for non-modifier keys in a held combo.
    static func sendRepeat(_ combo: KeyCombo, extraFlags: UInt64 = 0) {
        var raw = extraFlags
        for k in combo.keys {
            if let m = k.modifierMask { raw |= m }
        }
        let flags = CGEventFlags(rawValue: raw)
        for key in combo.keys where !key.isModifier {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true) else { continue }
            ev.flags = flags
            ev.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            ev.post(tap: .cghidEventTap)
        }
    }

    /// Media keys (NX_KEYTYPE_*), used to pass through buttons we don't remap
    /// while the device is seized.
    enum MediaKey: Int {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
    }

    static func sendMedia(_ key: MediaKey, down: Bool, isRepeat: Bool = false) {
        let stateBits = (down ? 0xA : 0xB) << 8
        let repeatBit = isRepeat ? 0x1 : 0x0
        let data1 = (key.rawValue << 16) | stateBits | repeatBit
        let ev = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        if let cg = ev?.cgEvent {
            cg.setIntegerValueField(.eventSourceUserData, value: BluetoothMediaTap.syntheticEventTag)
            cg.post(tap: .cghidEventTap)
        }
    }
}
