import Foundation
import IOKit.hid

/// Saved mapping and behavior profile for a specific USB/HID headset (keyed by VID:PID).
struct HeadsetProfile: Codable, Equatable, Identifiable {
    var id: String
    var vendorID: Int
    var productID: Int
    var deviceName: String
    var playKey: String
    var volUpKey: String
    var volDownKey: String
    var customButtons: [CustomButtonMapping]
    var holdMs: Int
    var toggle: Bool
    var keyRepeat: Bool
    var seize: Bool
    var tapKey: String
    var doubleTapKey: String
    var toggleTimeoutSeconds: Int
    var updatedAt: Date

    static func makeKey(vendorID: Int, productID: Int) -> String {
        String(format: "0x%04x:0x%04x", vendorID, productID)
    }

    init(
        vendorID: Int,
        productID: Int,
        deviceName: String,
        playKey: String = "f13",
        volUpKey: String = "",
        volDownKey: String = "",
        customButtons: [CustomButtonMapping] = [],
        holdMs: Int = 0,
        toggle: Bool = false,
        keyRepeat: Bool = false,
        seize: Bool = true,
        tapKey: String = "",
        doubleTapKey: String = "",
        toggleTimeoutSeconds: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = Self.makeKey(vendorID: vendorID, productID: productID)
        self.vendorID = vendorID
        self.productID = productID
        self.deviceName = deviceName
        self.playKey = playKey
        self.volUpKey = volUpKey
        self.volDownKey = volDownKey
        self.customButtons = customButtons
        self.holdMs = max(0, holdMs)
        self.toggle = toggle
        self.keyRepeat = keyRepeat
        self.seize = seize
        self.tapKey = tapKey
        self.doubleTapKey = doubleTapKey
        self.toggleTimeoutSeconds = max(0, toggleTimeoutSeconds)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case vendorID
        case productID
        case deviceName
        case playKey
        case volUpKey
        case volDownKey
        case customButtons
        case holdMs
        case toggle
        case keyRepeat
        case seize
        case tapKey
        case doubleTapKey
        case toggleTimeoutSeconds
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let vid = try c.decodeIfPresent(Int.self, forKey: .vendorID) ?? 0
        let pid = try c.decodeIfPresent(Int.self, forKey: .productID) ?? 0
        let decodedID = try c.decodeIfPresent(String.self, forKey: .id)
        self.vendorID = vid
        self.productID = pid
        self.id = (decodedID?.isEmpty == false) ? decodedID! : Self.makeKey(vendorID: vid, productID: pid)
        self.deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        self.playKey = try c.decodeIfPresent(String.self, forKey: .playKey) ?? "f13"
        self.volUpKey = try c.decodeIfPresent(String.self, forKey: .volUpKey) ?? ""
        self.volDownKey = try c.decodeIfPresent(String.self, forKey: .volDownKey) ?? ""
        self.customButtons = try c.decodeIfPresent([CustomButtonMapping].self, forKey: .customButtons) ?? []
        self.holdMs = max(0, try c.decodeIfPresent(Int.self, forKey: .holdMs) ?? 0)
        self.toggle = try c.decodeIfPresent(Bool.self, forKey: .toggle) ?? false
        self.keyRepeat = try c.decodeIfPresent(Bool.self, forKey: .keyRepeat) ?? false
        self.seize = try c.decodeIfPresent(Bool.self, forKey: .seize) ?? true
        self.tapKey = try c.decodeIfPresent(String.self, forKey: .tapKey) ?? ""
        self.doubleTapKey = try c.decodeIfPresent(String.self, forKey: .doubleTapKey) ?? ""
        self.toggleTimeoutSeconds = max(0, try c.decodeIfPresent(Int.self, forKey: .toggleTimeoutSeconds) ?? 0)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// Persists per-headset profiles as JSON in `UserDefaults`.
final class HeadsetProfileStore {
    static let defaultsKey = "cordkey.headsetProfiles"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var cache: [String: HeadsetProfile]

    init(defaults: UserDefaults = .standard, key: String = HeadsetProfileStore.defaultsKey) {
        self.defaults = defaults
        self.storageKey = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: HeadsetProfile].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    var profiles: [HeadsetProfile] {
        lock.lock()
        let values = Array(cache.values)
        lock.unlock()
        return values.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id < $1.id
        }
    }

    var count: Int {
        lock.lock()
        let n = cache.count
        lock.unlock()
        return n
    }

    func profile(vendorID: Int, productID: Int) -> HeadsetProfile? {
        let key = HeadsetProfile.makeKey(vendorID: vendorID, productID: productID)
        lock.lock()
        let found = cache[key]
        lock.unlock()
        return found
    }

    func save(_ profile: HeadsetProfile) {
        let key = HeadsetProfile.makeKey(vendorID: profile.vendorID, productID: profile.productID)
        var normalized = profile
        normalized.id = key
        normalized.holdMs = max(0, normalized.holdMs)
        normalized.toggleTimeoutSeconds = max(0, normalized.toggleTimeoutSeconds)

        lock.lock()
        cache[key] = normalized
        let snapshot = cache
        lock.unlock()
        persist(snapshot)
    }

    func delete(id: String) {
        lock.lock()
        let removed = cache.removeValue(forKey: id)
        let snapshot = cache
        lock.unlock()
        if removed != nil {
            persist(snapshot)
        }
    }

    private func persist(_ snapshot: [String: HeadsetProfile]) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

/// Lightweight shared (non-seize) HID watcher reporting Consumer/Telephony headset arrivals.
final class HeadsetArrivalWatcher {
    var onDeviceArrived: ((HIDDeviceInfo) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var started = false
    private var isSuppressingInitial = false
    private var startGeneration: UInt64 = 0
    private var recentArrivals: [String: CFAbsoluteTime] = [:]
    private let debounceInterval: CFAbsoluteTime = 0.5

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard !started else { return true }

        startGeneration &+= 1
        let gen = startGeneration
        isSuppressingInitial = true

        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDButton.pageMatchDictionaries as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            guard let ctx else { return }
            let info = HIDListener.inspect(dev)
            guard !(info.vendorID == 0 && info.productID == 0) else { return }
            let watcher = Unmanaged<HeadsetArrivalWatcher>.fromOpaque(ctx).takeUnretainedValue()
            watcher.handleDeviceMatched(info)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnSuccess {
            started = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started, self.startGeneration == gen else { return }
                self.isSuppressingInitial = false
            }
            return true
        }

        isSuppressingInitial = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        return false
    }

    func stop() {
        startGeneration &+= 1
        isSuppressingInitial = false
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        recentArrivals.removeAll()
        guard started else { return }
        started = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handleDeviceMatched(_ info: HIDDeviceInfo) {
        guard !isSuppressingInitial else { return }
        let key = HeadsetProfile.makeKey(vendorID: info.vendorID, productID: info.productID)
        let now = CFAbsoluteTimeGetCurrent()
        if let last = recentArrivals[key], now - last < debounceInterval {
            return
        }
        recentArrivals[key] = now

        DispatchQueue.main.async { [weak self] in
            guard let self, self.started else { return }
            self.onDeviceArrived?(info)
        }
    }
}
