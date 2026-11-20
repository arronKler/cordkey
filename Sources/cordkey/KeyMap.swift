import CoreGraphics

/// One physical key on the Mac keyboard (virtual key code + optional modifier bitmask).
struct Key {
    let name: String
    let code: CGKeyCode
    /// Combined generic CGEventFlags bit + device-dependent NX_DEVICE* bit (e.g. Left vs Right Option).
    let modifierMask: UInt64?

    var isModifier: Bool { modifierMask != nil }
}

/// A key or chord such as "f13", "right_option", "cmd+shift+space".
/// Keys are pressed in order and released in reverse order.
struct KeyCombo: CustomStringConvertible {
    let keys: [Key]
    var description: String { keys.map(\.name).joined(separator: "+") }
    var hasNonModifier: Bool { keys.contains { !$0.isModifier } }

    static func parse(_ text: String) -> KeyCombo? {
        let parts = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "+")
            .map { String($0) }
        guard !parts.isEmpty else { return nil }
        var keys: [Key] = []
        for p in parts {
            guard let k = KeyTable.lookup(p) else { return nil }
            keys.append(k)
        }
        return KeyCombo(keys: keys)
    }
}

enum KeyTable {
    // Device-side modifier bits from <IOKit/hidsystem/IOLLEvent.h>
    private static let devLCtl: UInt64   = 0x0000_0001
    private static let devLShift: UInt64 = 0x0000_0002
    private static let devRShift: UInt64 = 0x0000_0004
    private static let devLCmd: UInt64   = 0x0000_0008
    private static let devRCmd: UInt64   = 0x0000_0010
    private static let devLAlt: UInt64   = 0x0000_0020
    private static let devRAlt: UInt64   = 0x0000_0040
    private static let devRCtl: UInt64   = 0x0000_2000

    private static let mods: [(String, CGKeyCode, UInt64)] = [
        ("shift",         56, CGEventFlags.maskShift.rawValue       | devLShift),
        ("right_shift",   60, CGEventFlags.maskShift.rawValue       | devRShift),
        ("control",       59, CGEventFlags.maskControl.rawValue     | devLCtl),
        ("right_control", 62, CGEventFlags.maskControl.rawValue     | devRCtl),
        ("option",        58, CGEventFlags.maskAlternate.rawValue   | devLAlt),
        ("right_option",  61, CGEventFlags.maskAlternate.rawValue   | devRAlt),
        ("command",       55, CGEventFlags.maskCommand.rawValue     | devLCmd),
        ("right_command", 54, CGEventFlags.maskCommand.rawValue     | devRCmd),
        ("fn",            63, CGEventFlags.maskSecondaryFn.rawValue),
    ]

    private static let plain: [(String, CGKeyCode)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
        ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
        ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22),
        ("5", 23), ("equal", 24), ("9", 25), ("7", 26), ("minus", 27), ("8", 28),
        ("0", 29), ("right_bracket", 30), ("o", 31), ("u", 32), ("left_bracket", 33),
        ("i", 34), ("p", 35), ("return", 36), ("l", 37), ("j", 38), ("quote", 39),
        ("k", 40), ("semicolon", 41), ("backslash", 42), ("comma", 43), ("slash", 44),
        ("n", 45), ("m", 46), ("period", 47), ("tab", 48), ("space", 49), ("grave", 50),
        ("delete", 51), ("escape", 53), ("caps_lock", 57),
        ("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118), ("f5", 96), ("f6", 97),
        ("f7", 98), ("f8", 100), ("f9", 101), ("f10", 109), ("f11", 103), ("f12", 111),
        ("f13", 105), ("f14", 107), ("f15", 113), ("f16", 106), ("f17", 64),
        ("f18", 79), ("f19", 80), ("f20", 90),
        ("home", 115), ("end", 119), ("page_up", 116), ("page_down", 121),
        ("forward_delete", 117), ("left", 123), ("right", 124), ("down", 125), ("up", 126),
    ]

    private static let aliases: [String: String] = [
        "cmd": "command", "lcmd": "command", "rcmd": "right_command",
        "ctrl": "control", "lctrl": "control", "rctrl": "right_control",
        "alt": "option", "lalt": "option", "ralt": "right_option",
        "opt": "option", "lopt": "option", "ropt": "right_option",
        "lshift": "shift", "rshift": "right_shift",
        "globe": "fn",
        "spacebar": "space", "enter": "return", "esc": "escape", "backspace": "delete",
    ]

    static func lookup(_ raw: String) -> Key? {
        let name = aliases[raw] ?? raw
        if let m = mods.first(where: { $0.0 == name }) {
            return Key(name: m.0, code: m.1, modifierMask: m.2)
        }
        if let p = plain.first(where: { $0.0 == name }) {
            return Key(name: p.0, code: p.1, modifierMask: nil)
        }
        return nil
    }

    static func name(for code: Int64) -> String {
        if let m = mods.first(where: { Int64($0.1) == code }) { return m.0 }
        if let p = plain.first(where: { Int64($0.1) == code }) { return p.0 }
        return "keycode_\(code)"
    }

    static func knownName(for code: UInt16) -> String? {
        if let m = mods.first(where: { $0.1 == code }) { return m.0 }
        if let p = plain.first(where: { $0.1 == code }) { return p.0 }
        return nil
    }

    static func isModifier(code: UInt16) -> Bool {
        mods.contains { $0.1 == code }
    }

    static var allNames: [String] { mods.map(\.0) + plain.map(\.0) }
    static var aliasList: [(String, String)] { aliases.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
}
