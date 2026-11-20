import Foundation

struct CustomButtonMapping: Identifiable, Codable, Equatable {
    var id: String { button.codeTag }
    let button: HIDButton
    var keyText: String
}

/// Unified descriptor for rendering both built-in (play/vol+/vol-) and learned USB headset buttons.
struct ButtonRowItem: Identifiable, Equatable {
    var id: String { button.codeTag }
    let button: HIDButton
    let title: String
    let subtitle: String?
    let symbolName: String
    let nativeLabel: String
    let isRemovable: Bool
}

enum TriggerMode: String, CaseIterable, Identifiable {
    case hold
    case holdDelay
    case toggle

    var id: String { rawValue }

    func title(_ l10n: L10n) -> String {
        l10n.triggerModeTitle(self)
    }
}

struct KeyPreset: Identifiable {
    var id: String { value }
    let title: String
    let value: String
}

struct AppSettings: Equatable {
    var enabled: Bool = true
    var playKey: String = "f13"
    var volUpKey: String = ""
    var volDownKey: String = ""
    var customButtons: [CustomButtonMapping] = []
    var holdMs: Int = 0
    var toggle: Bool = false
    var keyRepeat: Bool = false
    var seize: Bool = true
    var soundFeedback: Bool = true
    var vendorID: Int = 0x05ac
    var productID: Int = 0x110b
    var language: AppLanguage = .auto
    var lockedMicUID: String = ""
    var lockedMicName: String = ""
    var autoSwitchProfiles: Bool = true
    var showFloatingHUD: Bool = false
    var hudPosition: HUDPosition = .topCenter
    var toggleTimeoutSeconds: Int = 0
    var playTapKey: String = ""
    var playDoubleTapKey: String = ""
    var appRulesEnabled: Bool = false
    var appRules: [AppRule] = []
    var bluetoothMode: Bool = false

    static let coreButtons: [HIDButton] = [.play, .volUp, .volDown]

    private static let presetValues: [(value: String, defaultTitle: String)] = [
        ("f13", "F13"),
        ("right_option", "Right Option"),
        ("option", "Left Option"),
        ("fn", "Fn / Globe"),
        ("right_command", "Right Command"),
        ("space", "Space"),
        ("option+space", "Option + Space"),
        ("command+shift+space", "Cmd + Shift + Space"),
    ]

    func allButtonRows(_ l10n: L10n) -> [ButtonRowItem] {
        var rows: [ButtonRowItem] = Self.coreButtons.map { btn in
            ButtonRowItem(
                button: btn,
                title: l10n.buttonDisplayName(btn),
                subtitle: nil,
                symbolName: btn.symbolName,
                nativeLabel: l10n.nativeLabel(for: btn),
                isRemovable: false
            )
        }
        for c in customButtons {
            rows.append(ButtonRowItem(
                button: c.button,
                title: c.button.displayName(l10n),
                subtitle: c.button.codeTag,
                symbolName: c.button.symbolName,
                nativeLabel: l10n.nativeLabel(for: c.button),
                isRemovable: true
            ))
        }
        return rows
    }

    var triggerMode: TriggerMode {
        get {
            if toggle { return .toggle }
            if holdMs > 0 { return .holdDelay }
            return .hold
        }
        set {
            switch newValue {
            case .hold:
                toggle = false
                holdMs = 0
            case .holdDelay:
                toggle = false
                if holdMs <= 0 { holdMs = 300 }
            case .toggle:
                toggle = true
            }
        }
    }

    static func presets(_ l10n: L10n) -> [KeyPreset] {
        presetValues.map { item in
            KeyPreset(title: l10n.presetTitle(for: item.value, fallback: item.defaultTitle), value: item.value)
        }
    }

    func keyText(for button: HIDButton) -> String {
        switch button {
        case .play: return playKey
        case .volUp: return volUpKey
        case .volDown: return volDownKey
        default:
            return customButtons.first(where: { $0.button == button })?.keyText ?? ""
        }
    }

    static func canonicalKeyText(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return "" }
        return KeyCombo.parse(normalized)?.description ?? normalized
    }

    mutating func setKeyText(_ text: String, for button: HIDButton) {
        let canonical = Self.canonicalKeyText(text)
        switch button {
        case .play: playKey = canonical
        case .volUp: volUpKey = canonical
        case .volDown: volDownKey = canonical
        default:
            if let idx = customButtons.firstIndex(where: { $0.button == button }) {
                customButtons[idx].keyText = canonical
            } else {
                customButtons.append(CustomButtonMapping(button: button, keyText: canonical))
            }
        }
    }

    mutating func setPlayTapKey(_ text: String) {
        playTapKey = Self.canonicalKeyText(text)
    }

    mutating func setPlayDoubleTapKey(_ text: String) {
        playDoubleTapKey = Self.canonicalKeyText(text)
    }

    /// Ensures a learned non-core button exists in `customButtons` (giving it a ready default key).
    mutating func ensureButtonExists(_ button: HIDButton, defaultKey: String = "f13") {
        guard !Self.coreButtons.contains(button) else { return }
        if !customButtons.contains(where: { $0.button == button }) {
            customButtons.append(CustomButtonMapping(button: button, keyText: defaultKey))
        }
    }

    mutating func removeCustomButton(_ button: HIDButton) {
        customButtons.removeAll { $0.button == button }
    }

    func displayName(forKeyText raw: String, emptyLabel: String, l10n: L10n? = nil) -> String {
        guard !raw.isEmpty else { return emptyLabel }
        let canonical = Self.canonicalKeyText(raw)
        let resolvedL10n = l10n ?? L10n(language)
        if let p = Self.presets(resolvedL10n).first(where: { $0.value == canonical }) {
            return p.title
        }
        return KeyCombo.parse(raw)?.description ?? raw
    }

    func displayName(for row: ButtonRowItem, l10n: L10n? = nil) -> String {
        displayName(forKeyText: keyText(for: row.button), emptyLabel: row.nativeLabel, l10n: l10n)
    }

    func mapperConfig(verbose: Bool, overridePlayKey: String? = nil) -> ButtonMapper.Config {
        var map: [HIDButton: KeyCombo] = [:]
        for button in Self.coreButtons + customButtons.map(\.button) {
            let text = (button == .play && overridePlayKey != nil) ? overridePlayKey! : keyText(for: button)
            if !text.isEmpty, let combo = KeyCombo.parse(text) {
                map[button] = combo
            }
        }
        var tapCombos: [HIDButton: KeyCombo] = [:]
        let canonicalTap = Self.canonicalKeyText(playTapKey)
        if !canonicalTap.isEmpty, let combo = KeyCombo.parse(canonicalTap) {
            tapCombos[.play] = combo
        }
        var doubleTapCombos: [HIDButton: KeyCombo] = [:]
        let canonicalDouble = Self.canonicalKeyText(playDoubleTapKey)
        if !canonicalDouble.isEmpty, let combo = KeyCombo.parse(canonicalDouble) {
            doubleTapCombos[.play] = combo
        }
        return ButtonMapper.Config(
            mappings: map,
            tapCombos: tapCombos,
            doubleTapCombos: doubleTapCombos,
            toggle: toggle,
            holdMs: toggle ? 0 : holdMs,
            keyRepeat: keyRepeat,
            soundFeedback: soundFeedback,
            verbose: verbose
        )
    }

    func makeProfile(deviceName: String) -> HeadsetProfile {
        HeadsetProfile(
            vendorID: vendorID,
            productID: productID,
            deviceName: deviceName,
            playKey: Self.canonicalKeyText(playKey),
            volUpKey: Self.canonicalKeyText(volUpKey),
            volDownKey: Self.canonicalKeyText(volDownKey),
            customButtons: customButtons.map {
                CustomButtonMapping(button: $0.button, keyText: Self.canonicalKeyText($0.keyText))
            },
            holdMs: holdMs,
            toggle: toggle,
            keyRepeat: keyRepeat,
            seize: seize,
            tapKey: Self.canonicalKeyText(playTapKey),
            doubleTapKey: Self.canonicalKeyText(playDoubleTapKey),
            toggleTimeoutSeconds: toggleTimeoutSeconds
        )
    }

    mutating func applyProfile(_ profile: HeadsetProfile) {
        vendorID = profile.vendorID
        productID = profile.productID
        playKey = Self.canonicalKeyText(profile.playKey)
        volUpKey = Self.canonicalKeyText(profile.volUpKey)
        volDownKey = Self.canonicalKeyText(profile.volDownKey)
        customButtons = profile.customButtons.map {
            CustomButtonMapping(button: $0.button, keyText: Self.canonicalKeyText($0.keyText))
        }
        holdMs = max(0, profile.holdMs)
        toggle = profile.toggle
        keyRepeat = profile.keyRepeat
        seize = profile.seize
        playTapKey = Self.canonicalKeyText(profile.tapKey)
        playDoubleTapKey = Self.canonicalKeyText(profile.doubleTapKey)
        toggleTimeoutSeconds = max(0, profile.toggleTimeoutSeconds)
    }

    // MARK: - Persistence

    private enum Keys {
        static let enabled = "cordkey.enabled"
        static let playKey = "cordkey.playKey"
        static let volUpKey = "cordkey.volUpKey"
        static let volDownKey = "cordkey.volDownKey"
        static let customButtons = "cordkey.customButtons"
        static let holdMs = "cordkey.holdMs"
        static let toggle = "cordkey.toggle"
        static let keyRepeat = "cordkey.keyRepeat"
        static let seize = "cordkey.seize"
        static let soundFeedback = "cordkey.soundFeedback"
        static let vendorID = "cordkey.vendorID"
        static let productID = "cordkey.productID"
        static let language = "cordkey.language"
        static let lockedMicUID = "cordkey.lockedMicUID"
        static let lockedMicName = "cordkey.lockedMicName"
        static let autoSwitchProfiles = "cordkey.autoSwitchProfiles"
        static let showFloatingHUD = "cordkey.showFloatingHUD"
        static let hudPosition = "cordkey.hudPosition"
        static let toggleTimeoutSeconds = "cordkey.toggleTimeoutSeconds"
        static let playTapKey = "cordkey.playTapKey"
        static let playDoubleTapKey = "cordkey.playDoubleTapKey"
        static let appRulesEnabled = "cordkey.appRulesEnabled"
        static let appRules = "cordkey.appRules"
        static let bluetoothMode = "cordkey.bluetoothMode"
    }

    static func load() -> AppSettings {
        let d = UserDefaults.standard
        var s = AppSettings()
        if d.object(forKey: Keys.enabled) != nil       { s.enabled = d.bool(forKey: Keys.enabled) }
        if let v = d.string(forKey: Keys.playKey)      { s.playKey = canonicalKeyText(v) }
        if let v = d.string(forKey: Keys.volUpKey)     { s.volUpKey = canonicalKeyText(v) }
        if let v = d.string(forKey: Keys.volDownKey)   { s.volDownKey = canonicalKeyText(v) }
        if let data = d.data(forKey: Keys.customButtons),
           let decoded = try? JSONDecoder().decode([CustomButtonMapping].self, from: data) {
            s.customButtons = decoded.map {
                CustomButtonMapping(button: $0.button, keyText: canonicalKeyText($0.keyText))
            }
        }
        if d.object(forKey: Keys.holdMs) != nil        { s.holdMs = max(0, d.integer(forKey: Keys.holdMs)) }
        if d.object(forKey: Keys.toggle) != nil        { s.toggle = d.bool(forKey: Keys.toggle) }
        if d.object(forKey: Keys.keyRepeat) != nil     { s.keyRepeat = d.bool(forKey: Keys.keyRepeat) }
        if d.object(forKey: Keys.seize) != nil         { s.seize = d.bool(forKey: Keys.seize) }
        if d.object(forKey: Keys.soundFeedback) != nil { s.soundFeedback = d.bool(forKey: Keys.soundFeedback) }
        if d.object(forKey: Keys.vendorID) != nil      { s.vendorID = d.integer(forKey: Keys.vendorID) }
        if d.object(forKey: Keys.productID) != nil     { s.productID = d.integer(forKey: Keys.productID) }
        if let rawLang = d.string(forKey: Keys.language),
           let lang = AppLanguage(rawValue: rawLang) {
            s.language = lang
        }
        if let v = d.string(forKey: Keys.lockedMicUID)  { s.lockedMicUID = v }
        if let v = d.string(forKey: Keys.lockedMicName) { s.lockedMicName = v }
        if d.object(forKey: Keys.autoSwitchProfiles) != nil {
            s.autoSwitchProfiles = d.bool(forKey: Keys.autoSwitchProfiles)
        }
        if d.object(forKey: Keys.showFloatingHUD) != nil {
            s.showFloatingHUD = d.bool(forKey: Keys.showFloatingHUD)
        }
        if let rawPos = d.string(forKey: Keys.hudPosition),
           let pos = HUDPosition(rawValue: rawPos) {
            s.hudPosition = pos
        }
        if d.object(forKey: Keys.toggleTimeoutSeconds) != nil {
            s.toggleTimeoutSeconds = max(0, d.integer(forKey: Keys.toggleTimeoutSeconds))
        }
        if let v = d.string(forKey: Keys.playTapKey)       { s.playTapKey = canonicalKeyText(v) }
        if let v = d.string(forKey: Keys.playDoubleTapKey) { s.playDoubleTapKey = canonicalKeyText(v) }
        if d.object(forKey: Keys.appRulesEnabled) != nil {
            s.appRulesEnabled = d.bool(forKey: Keys.appRulesEnabled)
        }
        if let data = d.data(forKey: Keys.appRules),
           let decoded = try? JSONDecoder().decode([AppRule].self, from: data) {
            s.appRules = decoded
        }
        if d.object(forKey: Keys.bluetoothMode) != nil {
            s.bluetoothMode = d.bool(forKey: Keys.bluetoothMode)
        }
        L10n.currentLanguage = s.language
        return s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Keys.enabled)
        d.set(playKey, forKey: Keys.playKey)
        d.set(volUpKey, forKey: Keys.volUpKey)
        d.set(volDownKey, forKey: Keys.volDownKey)
        if let data = try? JSONEncoder().encode(customButtons) {
            d.set(data, forKey: Keys.customButtons)
        }
        d.set(holdMs, forKey: Keys.holdMs)
        d.set(toggle, forKey: Keys.toggle)
        d.set(keyRepeat, forKey: Keys.keyRepeat)
        d.set(seize, forKey: Keys.seize)
        d.set(soundFeedback, forKey: Keys.soundFeedback)
        d.set(vendorID, forKey: Keys.vendorID)
        d.set(productID, forKey: Keys.productID)
        d.set(language.rawValue, forKey: Keys.language)
        d.set(lockedMicUID, forKey: Keys.lockedMicUID)
        d.set(lockedMicName, forKey: Keys.lockedMicName)
        d.set(autoSwitchProfiles, forKey: Keys.autoSwitchProfiles)
        d.set(showFloatingHUD, forKey: Keys.showFloatingHUD)
        d.set(hudPosition.rawValue, forKey: Keys.hudPosition)
        d.set(toggleTimeoutSeconds, forKey: Keys.toggleTimeoutSeconds)
        d.set(Self.canonicalKeyText(playTapKey), forKey: Keys.playTapKey)
        d.set(Self.canonicalKeyText(playDoubleTapKey), forKey: Keys.playDoubleTapKey)
        d.set(appRulesEnabled, forKey: Keys.appRulesEnabled)
        if let data = try? JSONEncoder().encode(appRules) {
            d.set(data, forKey: Keys.appRules)
        }
        d.set(bluetoothMode, forKey: Keys.bluetoothMode)
    }
}
