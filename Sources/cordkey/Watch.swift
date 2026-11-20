import AppKit
import CoreGraphics
import Foundation

/// `cordkey watch`: prints keyboard and system media events the system sees,
/// so you can confirm the headset button produces the held key and does not leak Play/Pause.
enum Watch {
    private static var activeTap: CFMachPort?

    static func run() -> Never {
        let sysDefinedMask: CGEventMask = 1 << 14 // NX_SYSDEFINED
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            sysDefinedMask

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let t = Watch.activeTap { CGEvent.tapEnable(tap: t, enable: true) }
                    return Unmanaged.passUnretained(event)
                }

                if type.rawValue == 14 {
                    if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
                        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
                        let keyFlags = ns.data1 & 0x0000_FFFF
                        let state = (keyFlags & 0xFF00) >> 8
                        let isRepeat = (keyFlags & 0x1) != 0
                        let action = state == 0xA ? (isRepeat ? "down (repeat)" : "down") : (state == 0xB ? "up" : "state_\(state)")
                        let name: String
                        switch keyCode {
                        case 0: name = "vol-up"
                        case 1: name = "vol-down"
                        case 7: name = "mute"
                        case 16: name = "play"
                        case 17: name = "next"
                        case 18: name = "prev"
                        default: name = "media_\(keyCode)"
                        }
                        log("media \(name) \(action)")
                    }
                    return Unmanaged.passUnretained(event)
                }

                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let rep = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let kind: String
                switch type {
                case .keyDown: kind = rep ? "down (repeat)" : "down"
                case .keyUp: kind = "up"
                case .flagsChanged: kind = "flags=\(Watch.formatFlags(event.flags))"
                default: kind = "type \(type.rawValue)"
                }
                log("key \(KeyTable.name(for: code)) \(kind)")
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            log("cannot create event tap: grant Input Monitoring (or Accessibility) to your terminal in System Settings → Privacy & Security")
            exit(1)
        }

        activeTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("watching keyboard & media events, Ctrl+C to stop")
        CFRunLoopRun()
        exit(0)
    }

    private static func formatFlags(_ flags: CGEventFlags) -> String {
        var names: [String] = []
        if flags.contains(.maskCommand)     { names.append("cmd") }
        if flags.contains(.maskShift)       { names.append("shift") }
        if flags.contains(.maskAlternate)   { names.append("opt") }
        if flags.contains(.maskControl)     { names.append("ctrl") }
        if flags.contains(.maskSecondaryFn) { names.append("fn") }
        let hex = String(format: "0x%llx", flags.rawValue)
        return names.isEmpty ? "[] (\(hex))" : "[\(names.joined(separator: "+"))] (\(hex))"
    }
}
