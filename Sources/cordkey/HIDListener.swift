import Foundation
import IOKit.hid

/// Identifies a headset button across HID usage pages (Consumer 0x0C, Telephony 0x0B, etc.).
struct HIDButton: Hashable, Codable, Comparable, CustomStringConvertible {
    let page: UInt32
    let usage: UInt32

    static let consumerPage = UInt32(kHIDPage_Consumer)   // 0x0C
    static let telephonyPage = UInt32(kHIDPage_Telephony) // 0x0B

    // Common Consumer-page buttons (USB headsets, EarPods, media remotes)
    static let play    = HIDButton(page: consumerPage, usage: 0xCD) // Play/Pause
    static let volUp   = HIDButton(page: consumerPage, usage: 0xE9) // Volume Increment
    static let volDown = HIDButton(page: consumerPage, usage: 0xEA) // Volume Decrement
    static let mute    = HIDButton(page: consumerPage, usage: 0xE2) // Audio Mute
    static let voice   = HIDButton(page: consumerPage, usage: 0xCF) // Voice Command
    static let playKey = HIDButton(page: consumerPage, usage: 0xB0) // Play (dedicated)
    static let pause   = HIDButton(page: consumerPage, usage: 0xB1) // Pause (dedicated)
    static let next    = HIDButton(page: consumerPage, usage: 0xB5) // Scan Next Track
    static let prev    = HIDButton(page: consumerPage, usage: 0xB6) // Scan Previous Track

    // Common Telephony-page buttons (Jabra, Poly, Logitech, conference headsets)
    static let hook    = HIDButton(page: telephonyPage, usage: 0x20) // Hook Switch (Call/Hangup)
    static let flash   = HIDButton(page: telephonyPage, usage: 0x21) // Flash / Hold
    static let redial  = HIDButton(page: telephonyPage, usage: 0x24) // Redial
    static let micMute = HIDButton(page: telephonyPage, usage: 0x2F) // Phone Mute (Mic Mute)

    static let supportedPages: [UInt32] = [consumerPage, telephonyPage]

    static let pageMatchDictionaries: [[String: Any]] = supportedPages.map {
        [kIOHIDPrimaryUsagePageKey: Int($0)]
    }

    static func parseEvent(from value: IOHIDValue) -> (button: HIDButton, down: Bool, device: IOHIDDevice)? {
        let el = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(el)
        guard supportedPages.contains(page) else { return nil }
        let usage = IOHIDElementGetUsage(el)
        guard usage != 0 && usage < 0xFFFF else { return nil }
        let down = IOHIDValueGetIntegerValue(value) != 0
        return (HIDButton(page: page, usage: usage), down, IOHIDElementGetDevice(el))
    }

    static func < (lhs: HIDButton, rhs: HIDButton) -> Bool {
        lhs.page != rhs.page ? lhs.page < rhs.page : lhs.usage < rhs.usage
    }

    var codeTag: String {
        String(format: "0x%02x:0x%02x", page, usage)
    }

    var shortName: String {
        switch self {
        case .play: return "play"
        case .volUp: return "vol-up"
        case .volDown: return "vol-down"
        case .mute: return "mute"
        case .voice: return "voice"
        case .playKey: return "play-only"
        case .pause: return "pause-only"
        case .next: return "next"
        case .prev: return "prev"
        case .hook: return "hook"
        case .flash: return "flash"
        case .redial: return "redial"
        case .micMute: return "mic-mute"
        default: return codeTag
        }
    }

    func displayName(_ l10n: L10n) -> String {
        l10n.buttonDisplayName(self)
    }

    var symbolName: String {
        switch self {
        case .play, .playKey, .pause: return "playpause.fill"
        case .volUp: return "speaker.plus.fill"
        case .volDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"
        case .voice: return "waveform"
        case .next: return "forward.fill"
        case .prev: return "backward.fill"
        case .hook, .flash, .redial: return "phone.fill"
        case .micMute: return "mic.slash.fill"
        default: return "circle.grid.2x2.fill"
        }
    }

    var description: String { shortName }

    /// Parses aliases (`play`, `mic-mute`, `hook`, `mute`, `voice`, ...) or raw `PAGE:USAGE` (`0x0b:0x2f`).
    static func parse(_ raw: String) -> HIDButton? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "play", "play_or_pause": return .play
        case "vol-up", "vol_up", "volume_up": return .volUp
        case "vol-down", "vol_down", "volume_down": return .volDown
        case "mute": return .mute
        case "voice", "siri": return .voice
        case "next": return .next
        case "prev", "previous": return .prev
        case "hook", "call", "answer": return .hook
        case "mic-mute", "mic_mute", "phone-mute": return .micMute
        case "flash": return .flash
        case "redial": return .redial
        default:
            let parts = s.split(separator: ":").map(String.init)
            guard parts.count == 2,
                  let p = parseUInt32(parts[0]),
                  let u = parseUInt32(parts[1]),
                  p > 0, u > 0 else { return nil }
            return HIDButton(page: p, usage: u)
        }
    }

    private static func parseUInt32(_ s: String) -> UInt32? {
        s.hasPrefix("0x") ? UInt32(s.dropFirst(2), radix: 16) : UInt32(s)
    }
}

struct HIDDeviceInfo: Equatable {
    let product: String
    let manufacturer: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let pages: [UInt32]

    var pagesLabel: String {
        let names = pages.sorted().map { p -> String in
            if p == HIDButton.consumerPage { return "Consumer" }
            if p == HIDButton.telephonyPage { return "Telephony" }
            return String(format: "0x%02x", p)
        }
        return names.joined(separator: "+")
    }
}

/// Listens to Consumer (0x0C) and Telephony (0x0B) button presses on one USB/HID headset,
/// matched by vendor/product id. With `seize`, macOS no longer sees the buttons.
final class HIDListener {
    typealias InputHandler = (_ button: HIDButton, _ down: Bool) -> Void
    typealias ConnectHandler = (_ description: String) -> Void
    typealias DisconnectHandler = () -> Void

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let onInput: InputHandler
    private let onConnect: ConnectHandler?
    private let onDisconnect: DisconnectHandler
    private(set) var seized = false
    private(set) var connectedDevice: String?
    private var connectedDevices: Set<IOHIDDevice> = []
    private var started = false

    init(
        vendor: Int,
        product: Int,
        onInput: @escaping InputHandler,
        onConnect: ConnectHandler? = nil,
        onDisconnect: @escaping DisconnectHandler
    ) {
        self.onInput = onInput
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect

        let matches: [[String: Any]] = HIDButton.supportedPages.map { page in
            [
                kIOHIDVendorIDKey: vendor,
                kIOHIDProductIDKey: product,
                kIOHIDPrimaryUsagePageKey: Int(page),
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx, let parsed = HIDButton.parseEvent(from: value) else { return }
            let me = Unmanaged<HIDListener>.fromOpaque(ctx).takeUnretainedValue()
            me.onInput(parsed.button, parsed.down)
        }, ctx)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let desc = HIDListener.describe(dev)
            log("headset connected: \(desc)")
            guard let ctx else { return }
            let me = Unmanaged<HIDListener>.fromOpaque(ctx).takeUnretainedValue()
            me.connectedDevices.insert(dev)
            me.connectedDevice = desc
            me.onConnect?(desc)
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            log("headset disconnected: \(HIDListener.describe(dev))")
            guard let ctx else { return }
            let me = Unmanaged<HIDListener>.fromOpaque(ctx).takeUnretainedValue()
            guard me.connectedDevices.remove(dev) != nil else { return }
            me.connectedDevice = me.connectedDevices.first.map(HIDListener.describe)
            me.onDisconnect()
        }, ctx)
    }

    deinit {
        stop()
    }

    /// Opens the manager. Tries exclusive (seize) access first if requested.
    func start(seize: Bool) -> Bool {
        guard !started else { return true }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if seize {
            let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if r == kIOReturnSuccess {
                seized = true
                started = true
                return true
            }
            log(String(format: "exclusive access failed (0x%08x); falling back to shared mode — original button action may also fire", r))
        }
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnSuccess {
            started = true
            return true
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        unregisterCallbacks()
        return false
    }

    func stop() {
        unregisterCallbacks()
        guard started else { return }
        started = false
        seized = false
        connectedDevices.removeAll()
        connectedDevice = nil
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func unregisterCallbacks() {
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
    }

    static func describe(_ dev: IOHIDDevice) -> String {
        let info = inspect(dev)
        return String(format: "%@ (0x%04x:0x%04x)", info.product, info.vendorID, info.productID)
    }

    static func inspect(_ dev: IOHIDDevice) -> HIDDeviceInfo {
        let product = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?"
        let manufacturer = IOHIDDeviceGetProperty(dev, kIOHIDManufacturerKey as CFString) as? String ?? ""
        let transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? "?"
        let vid = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let page = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int).map(UInt32.init)
        return HIDDeviceInfo(
            product: product,
            manufacturer: manufacturer,
            transport: transport,
            vendorID: vid,
            productID: pid,
            pages: page.map { [$0] } ?? []
        )
    }

    /// Lists all connected HID Consumer (0x0C) and Telephony (0x0B) devices, deduplicated by VID/PID/transport.
    static func listHeadsetDevices() -> [HIDDeviceInfo] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, HIDButton.pageMatchDictionaries as CFArray)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }
        defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let cfSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
            return []
        }

        // Merge multiple HID interfaces (e.g. Consumer + Telephony) of the same physical headset.
        struct Key: Hashable { let vid: Int; let pid: Int; let transport: String }
        var grouped: [Key: HIDDeviceInfo] = [:]
        for dev in cfSet {
            let info = inspect(dev)
            let k = Key(vid: info.vendorID, pid: info.productID, transport: info.transport)
            if let existing = grouped[k] {
                let mergedPages = Array(Set(existing.pages + info.pages)).sorted()
                grouped[k] = HIDDeviceInfo(
                    product: existing.product != "?" ? existing.product : info.product,
                    manufacturer: !existing.manufacturer.isEmpty ? existing.manufacturer : info.manufacturer,
                    transport: existing.transport,
                    vendorID: existing.vendorID,
                    productID: existing.productID,
                    pages: mergedPages
                )
            } else {
                grouped[k] = info
            }
        }

        return grouped.values.sorted { a, b in
            let aUSB = a.transport.localizedCaseInsensitiveContains("usb")
            let bUSB = b.transport.localizedCaseInsensitiveContains("usb")
            if aUSB != bUSB { return aUSB }
            if a.vendorID != b.vendorID { return a.vendorID < b.vendorID }
            if a.productID != b.productID { return a.productID < b.productID }
            return a.product < b.product
        }
    }
}

/// Temporarily listens across ALL connected Consumer & Telephony HID devices in shared mode
/// so the user can press any button on any USB headset to auto-detect both device and button code.
final class HIDButtonLearner {
    typealias CaptureHandler = (_ device: HIDDeviceInfo, _ button: HIDButton) -> Void

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let onCapture: CaptureHandler
    private var started = false

    init(onCapture: @escaping CaptureHandler) {
        self.onCapture = onCapture
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDButton.pageMatchDictionaries as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx, let parsed = HIDButton.parseEvent(from: value), parsed.down else { return }
            let me = Unmanaged<HIDButtonLearner>.fromOpaque(ctx).takeUnretainedValue()
            let info = HIDListener.inspect(parsed.device)
            me.onCapture(info, parsed.button)
        }, ctx)
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard !started else { return true }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnSuccess {
            started = true
            return true
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        return false
    }

    func stop() {
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        guard started else { return }
        started = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

/// CLI `cordkey probe`: prints every Consumer/Telephony button press across all connected HID headsets.
enum HIDProbe {
    static func run() -> Never {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, HIDButton.pageMatchDictionaries as CFArray)
        IOHIDManagerRegisterInputValueCallback(mgr, { _, _, _, value in
            guard let parsed = HIDButton.parseEvent(from: value) else { return }
            let info = HIDListener.inspect(parsed.device)
            let btn = parsed.button
            log(String(format: "[%@ 0x%04x:0x%04x] %@ (%@) %@", info.product, info.vendorID, info.productID, btn.codeTag, btn.shortName, parsed.down ? "down" : "up"))
        }, nil)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            log("cannot open HID manager (Input Monitoring permission may be required)")
            exit(1)
        }
        log("probing all Consumer (0x0C) & Telephony (0x0B) HID headsets — press any headset button, Ctrl+C to stop")
        CFRunLoopRun()
        exit(0)
    }
}

private let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func log(_ msg: String) {
    print("[\(logFormatter.string(from: Date()))] \(msg)")
    fflush(stdout)
}
