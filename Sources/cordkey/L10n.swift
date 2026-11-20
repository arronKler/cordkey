import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto
    case en
    case zh

    var id: String { rawValue }

    /// Resolves `.auto` via `Locale.preferredLanguages.first` ("zh*" -> `.zh`, else `.en`).
    var resolved: AppLanguage {
        switch self {
        case .en, .zh:
            return self
        case .auto:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? .zh : .en
        }
    }

    var isChinese: Bool { resolved == .zh }

    var pickerTitle: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "English"
        case .zh: return "简体中文"
        }
    }
}

/// Centralized English + Simplified Chinese strings for CordKey UI and live event summaries.
struct L10n {
    static var currentLanguage: AppLanguage = .auto
    static var current: L10n { L10n(currentLanguage) }

    let language: AppLanguage
    var isZH: Bool { language.isChinese }

    init(_ language: AppLanguage = L10n.currentLanguage) {
        self.language = language
    }

    private func t(_ en: String, _ zh: String) -> String {
        isZH ? zh : en
    }

    // MARK: - Trigger Modes & Presets

    func triggerModeTitle(_ mode: TriggerMode) -> String {
        switch mode {
        case .hold: return t("Hold", "按住保持")
        case .holdDelay: return t("Hold Delay", "长按触发")
        case .toggle: return t("Click Toggle", "单击切换")
        }
    }

    func presetTitle(for value: String, fallback: String) -> String {
        switch value {
        case "f13": return "F13"
        case "right_option": return t("Right Option", "右 Option")
        case "option": return t("Left Option", "左 Option")
        case "fn": return t("Fn / Globe", "Fn / 地球键")
        case "right_command": return t("Right Command", "右 Command")
        case "space": return t("Space", "空格 Space")
        case "option+space": return "Option + Space"
        case "command+shift+space": return "Cmd + Shift + Space"
        default: return fallback
        }
    }

    // MARK: - Button Names

    func buttonDisplayName(_ button: HIDButton) -> String {
        switch button {
        case .play: return t("Play / Pause", "中间播放键")
        case .volUp: return t("Volume +", "音量 + 键")
        case .volDown: return t("Volume −", "音量 − 键")
        case .mute: return t("Audio Mute", "静音键")
        case .voice: return t("Voice Assistant", "语音助手键")
        case .playKey: return t("Play", "播放键")
        case .pause: return t("Pause", "暂停键")
        case .next: return t("Next Track", "下一曲键")
        case .prev: return t("Previous Track", "上一曲键")
        case .hook: return t("Hook Switch", "通话/挂断键")
        case .flash: return t("Call Hold", "通话保持键")
        case .redial: return t("Redial", "重拨键")
        case .micMute: return t("Mic Mute", "麦克风静音键")
        default:
            let pageTag: String
            if button.page == HIDButton.telephonyPage {
                pageTag = t("Telephony", "通话页")
            } else if button.page == HIDButton.consumerPage {
                pageTag = t("Consumer", "媒体页")
            } else {
                pageTag = String(format: "0x%02X", button.page)
            }
            return "\(pageTag) 0x\(String(format: "%02X", button.usage))"
        }
    }

    var unmappedLabel: String { t("Unmapped", "不映射") }

    func nativeLabel(for button: HIDButton) -> String {
        switch button {
        case .play: return t("Native Play/Pause", "原生播放/暂停")
        case .volUp: return t("Native Vol+", "原生音量+")
        case .volDown: return t("Native Vol−", "原生音量−")
        case .mute: return t("Native Mute", "原生静音")
        case .next: return t("Native Next", "原生下一曲")
        case .prev: return t("Native Prev", "原生上一曲")
        default: return unmappedLabel
        }
    }

    // MARK: - Menu Bar & Quick Menu

    var statusTooltipNoAX: String {
        t("CordKey: Accessibility permission required — click to grant", "CordKey：缺少辅助功能权限，点击前往授权")
    }

    var statusTooltipHIDFailed: String {
        t("CordKey: \(hidOpenFailedShort)", "CordKey：\(hidOpenFailedShort)")
    }

    var statusTooltipPaused: String {
        t("CordKey: Paused (click for panel, right-click for quick menu)", "CordKey：已暂停（点击打开面板，右键快速开关）")
    }

    func statusTooltipHolding(_ held: String) -> String {
        t("CordKey: Holding \(held)", "CordKey：正在按住 \(held)")
    }

    func statusTooltipConnected(_ device: String?) -> String {
        let dev = device ?? t("Waiting for headset", "等待耳机连接")
        return t("CordKey: \(dev)", "CordKey：\(dev)")
    }

    func statusTooltipAppPaused(_ appName: String) -> String {
        appName.isEmpty
            ? t("CordKey: Paused by App Rule", "CordKey：已按应用规则暂停")
            : t("CordKey: Paused for \(appName)", "CordKey：在 \(appName) 中自动暂停")
    }

    var statusTooltipBluetooth: String {
        t("CordKey: Bluetooth compatibility mode active", "CordKey：蓝牙兼容模式运行中")
    }

    var menuPauseMapping: String { t("Pause Key Mapping", "暂停按键映射") }
    var menuResumeMapping: String { t("Resume Key Mapping", "恢复按键映射") }

    func menuReleaseHeld(_ held: String) -> String {
        t("Release Held Key (\(held))", "立即松开当前按键 (\(held))")
    }

    var menuOpenAX: String { t("Open Accessibility Settings...", "打开系统辅助功能设置...") }
    var menuQuit: String { t("Quit CordKey", "退出 CordKey") }

    // MARK: - Popover Header & Banners

    var pillPaused: String { t("Paused", "已暂停") }
    var pillAppPaused: String { t("App Paused", "应用暂停") }
    var pillBluetooth: String { t("Bluetooth", "蓝牙模式") }
    var pillLearning: String { t("Learning", "识别中") }
    var pillExclusive: String { t("Exclusive", "独占") }
    var pillShared: String { t("Shared", "共享") }
    var pillDisconnected: String { t("Disconnected", "未连接") }
    var pillError: String { t("Permission", "需权限") }

    var subtitlePaused: String {
        t("Headset buttons restored to native behavior", "耳机按键已恢复原生控制")
    }

    func subtitleAppPaused(_ appName: String) -> String {
        appName.isEmpty
            ? t("Paused by App Rule", "已按应用规则自动暂停")
            : t("Paused while \(appName) is active", "\(appName) 在前台时自动暂停")
    }

    var subtitleBluetoothActive: String {
        t("Listening for Bluetooth Play/Pause", "正在监听蓝牙耳机播放键")
    }

    var bluetoothTapFailedShort: String {
        t("Bluetooth tap needs Accessibility", "蓝牙拦截需要辅助功能权限")
    }

    var bluetoothTapFailedStatus: String {
        t("Bluetooth mode needs Accessibility permission", "蓝牙兼容模式需要辅助功能权限")
    }

    func subtitleWaiting(vendorID: Int, productID: Int) -> String {
        isZH
            ? String(format: "等待设备 0x%04x:0x%04x 插入", vendorID, productID)
            : String(format: "Waiting for device 0x%04x:0x%04x", vendorID, productID)
    }

    var axBannerTitle: String { t("Accessibility Permission Required", "需要辅助功能权限") }
    var axBannerSubtitle: String { t("Simulated keystrokes are blocked until granted", "未授权时系统会拦截模拟按键") }
    var axBannerStaleHint: String {
        t(
            "Already enabled? Remove CordKey (−) in the list and re-add (+) it.",
            "若已勾选仍提示，请在列表选中 CordKey 点「−」移除后重新「+」添加"
        )
    }
    var axBannerButton: String { t("Open Settings", "前往授权") }

    var hidBannerTitle: String { t("Input Monitoring Permission Required", "需要输入监控权限") }
    var hidBannerSubtitle: String {
        t(
            "Headset buttons cannot be captured until granted in System Settings",
            "未授权时无法捕获耳机按键事件，请前往系统设置授权"
        )
    }
    var hidBannerButton: String { t("Open Settings", "前往授权") }
    var retryButton: String { t("Retry", "重试") }

    func holdingTitle(_ held: String) -> String {
        t("Holding: \(held)", "正在按住：\(held)")
    }

    func holdingElapsed(_ duration: String) -> String {
        t("Elapsed \(duration)", "已持续 \(duration)")
    }

    var releaseNow: String { t("Release Now", "立即松开") }

    func earPodsMicHint(hasBuiltInMic: Bool) -> String {
        if hasBuiltInMic {
            return t(
                "Holding EarPods center button physically mutes its inline mic. Switch to Click Toggle or use built-in mic:",
                "EarPods 长按中间键会物理静音耳机自带麦。建议改用「单击切换」或改用机身麦克风："
            )
        }
        return t(
            "Holding EarPods center button physically mutes its inline mic. Switch to Click Toggle to avoid mic muting.",
            "EarPods 长按中间键会物理静音耳机自带麦。建议改用「单击切换」以避免静音。"
        )
    }

    var switchToToggle: String { t("Use Click Toggle", "改用单击切换") }

    func useAudioInput(_ name: String) -> String {
        t("Use \(name)", "用 \(name)")
    }

    // MARK: - Mappings Card

    var sectionMappings: String { t("Button Mappings", "按键映射") }
    var promptPressKeyboard: String { t("Press a key (Esc to cancel)", "请按键盘键 (Esc 取消)") }
    var promptPressHeadsetCancel: String { t("Press headset button… (Cancel)", "请按耳机键… (取消)") }
    var learnButton: String { t("Learn Button", "识别耳机键") }

    var learnButtonHelp: String {
        t(
            "Works with any USB headset: click then press mute/call/media button to auto-detect",
            "兼容任意 USB 耳麦：点击后按耳机上的静音键/通话键/媒体键自动识别并添加"
        )
    }

    var waitingForKey: String { t("Waiting…", "等待按键…") }
    var menuRecordShortcut: String { t("Record Shortcut…", "按键盘录制快捷键…") }
    var menuManualKey: String { t("Enter Key Name…", "手动输入键名…") }

    func menuUnmap(_ nativeLabel: String) -> String {
        if nativeLabel == unmappedLabel {
            return t("Unmap", "不映射")
        }
        return t("Unmap (\(nativeLabel))", "不映射（\(nativeLabel)）")
    }

    var recordShortcutHelp: String {
        t("Press any key or chord on your keyboard to record", "按下键盘上的任意键或组合键直接录制")
    }

    var removeCustomButtonHelp: String { t("Remove this custom headset button", "移除此自定义耳机键") }

    // MARK: - Trigger Mode Card

    var sectionTriggerMode: String { t("Trigger Mode", "触发方式") }

    var triggerHoldDesc: String {
        t(
            "Presses the mapped key on button down and releases on button up (zero latency).",
            "按下耳机键立即按下键盘键，松开立即松开（零延迟）。"
        )
    }

    var holdThreshold: String { t("Hold Threshold", "长按阈值") }

    var triggerHoldDelayDesc: String {
        t(
            "Taps shorter than threshold pass through natively; longer holds engage the key.",
            "短于阈值松手执行原生功能，达到阈值才保持按下。"
        )
    }

    var triggerToggleDesc: String {
        t(
            "Tap once to engage cleanly after release (avoids click noise & mic mute); tap again to release.",
            "按一下松手后自动开启（避开按键杂音与麦静音），再按一下立即结束。"
        )
    }

    var shortTapLabel: String { t("Short Tap", "短按") }
    var doubleTapLabel: String { t("Double Tap", "双击") }
    var offLabel: String { t("Off", "关闭") }
    var shortTapTitle: String { t("Key for Short Tap", "设置短按按键") }
    var doubleTapTitle: String { t("Key for Double Tap", "设置双击按键") }
    var shortTapPlaceholder: String {
        t("e.g. space, escape (empty = native)", "如 space、escape（留空为原生）")
    }
    var doubleTapPlaceholder: String {
        t("e.g. command+shift+d (empty = off)", "如 command+shift+d（留空则关闭）")
    }
    var autoReleaseLabel: String { t("Auto-Release", "超时自动松开") }

    func timeoutOptionTitle(_ seconds: Int) -> String {
        switch seconds {
        case 0: return t("Off", "关闭")
        case 60: return t("1m", "1分")
        case 120: return t("2m", "2分")
        case 300: return t("5m", "5分")
        default: return t("\(seconds)s", "\(seconds)秒")
        }
    }

    // MARK: - Audio, Device & Language Card

    var sectionAudioAndDevice: String { t("Audio & Device", "音频与设备") }
    var inputMic: String { t("Input Mic", "输入麦克风") }
    var noInputDevice: String { t("No Input Device", "无输入设备") }
    var micLockLockHelp: String {
        t("Lock default input mic (prevents headset auto-switch)", "锁定当前麦克风（防止插耳机时被系统自动抢占）")
    }
    var micLockUnlockHelp: String {
        t("Mic locked (click to unlock)", "麦克风已锁定（点击解锁）")
    }
    var floatingHUDLabel: String { t("Floating Status HUD", "悬浮状态胶囊") }
    func hudPositionTitle(_ pos: HUDPosition) -> String {
        switch pos {
        case .topCenter: return t("Top", "顶部")
        case .bottomCenter: return t("Bottom", "底部")
        }
    }
    var hudReleaseHint: String { t("Click to release", "点击松开") }
    var soundCues: String { t("Sound Cues", "触发提示音") }
    var languageLabel: String { t("Language", "界面语言") }
    var advancedSummary: String {
        t("Advanced (Device / Profiles / Bluetooth / Rules)", "高级选项（设备 / 配置 / 蓝牙 / 应用规则）")
    }
    var exclusiveMode: String { t("Exclusive Mode (Block Native)", "独占模式（屏蔽原生按键）") }
    var keyRepeatLabel: String { t("Key Repeat (Arrows / Letters)", "长按连发（方向/字符键）") }
    var usbHeadset: String { t("USB Headset", "USB 耳麦设备") }
    var noHeadsetsFound: String { t("No USB headsets detected", "未检测到 USB 耳麦") }
    var resetToEarPods: String { t("Reset to EarPods (0x05ac:0x110b)", "恢复默认 EarPods (0x05ac:0x110b)") }
    var refreshDevices: String { t("Refresh Devices", "刷新设备列表") }
    var autoSwitchProfiles: String { t("Auto-Switch Headset Profiles", "多耳机自动切换配置") }
    func savedProfilesCount(_ count: Int) -> String {
        if count == 0 {
            return t("No saved headset profiles", "暂无已保存的耳机配置")
        }
        return t("\(count) saved profile\(count == 1 ? "" : "s")", "已保存 \(count) 个耳机配置")
    }
    var manageProfilesLabel: String { t("Saved Profiles", "已保存配置") }
    var clearProfilesButton: String { t("Clear All", "全部清空") }
    var deleteProfileHelp: String { t("Delete saved profile", "删除此耳机配置") }
    var bluetoothModeLabel: String { t("Bluetooth Compatibility Mode", "蓝牙耳机兼容模式") }
    var bluetoothModeNote: String {
        t(
            "Supports AirPods/Sony Play via Click Toggle (also captures keyboard F8 Play).",
            "通过单击切换兼容 AirPods/Sony 等蓝牙耳机（同时会接管键盘 F8 播放键）。"
        )
    }

    // MARK: - App-Aware Rules

    var appRulesLabel: String { t("App-Aware Rules", "分应用规则") }
    var addRuleButton: String { t("Add Rule", "添加规则") }
    var appRulesQuickPresets: String { t("Quick Presets", "常用预设") }
    var appRulesRunningApps: String { t("Running Apps", "正在运行的应用") }
    var appRulesEmptyHint: String {
        t("Pause in media apps or override Play per app.", "可在影音软件中自动暂停，或为会议软件单独指定快捷键。")
    }
    var appRulePauseLabel: String { t("Pause", "自动暂停") }
    var appRuleActionPause: String { t("Pause CordKey (Native Media)", "自动暂停（恢复原生媒体键）") }
    var appRuleActionMutePrefix: String { t("Override Play →", "改用播放键 →") }
    var appRuleCustomKeyItem: String { t("Custom Shortcut…", "自定义快捷键…") }
    func appRuleCustomTitle(_ appName: String) -> String {
        t("Play key in \(appName)", "设置「\(appName)」专用播放键")
    }

    // MARK: - Footer & Inline Editor

    var launchAtLogin: String { t("Launch at Login", "登录自启") }
    var accessibilityButton: String { t("Accessibility", "辅助功能") }
    var quitButton: String { t("Quit", "退出") }

    func manualKeyTitle(_ buttonTitle: String) -> String {
        t("Key for “\(buttonTitle)”", "设置「\(buttonTitle)」按键")
    }

    var manualKeyPlaceholder: String {
        t("e.g. f13, right_option (empty = unmap)", "如 f13、right_option（留空则不映射）")
    }
    var okButton: String { t("Save", "保存") }
    var cancelButton: String { t("Cancel", "取消") }

    func invalidKeyInline(_ text: String) -> String {
        t(
            "Unrecognized key “\(text)” — try f13, space, right_option, fn, cmd+shift+space.",
            "无法识别「\(text)」— 可输入 f13、space、right_option、fn、cmd+shift+space。"
        )
    }

    func unsupportedRecordedKey(_ code: UInt16) -> String {
        t(
            "Key (code \(code)) not supported — Esc to cancel or try another",
            "不支持该按键 (键码 \(code)) — 按 Esc 取消或改按其他键"
        )
    }

    // MARK: - Live Event Summaries & Reasons

    var readyStatus: String { t("Ready, waiting for headset button", "就绪，等待耳机按键") }
    var hidOpenFailed: String {
        t("Cannot open headset (Input Monitoring permission may be required)", "无法打开耳机设备（可能缺少输入监控权限）")
    }
    var hidOpenFailedShort: String {
        t("Input Monitoring permission required", "需要输入监控权限")
    }
    var reasonQuit: String { t("App quit", "退出应用") }
    var reasonPaused: String { t("Paused", "已暂停") }
    var reasonManualRelease: String { t("Manual release", "手动松开") }
    var reasonLearnMode: String { t("Entering learn mode", "进入识别模式") }
    var reasonReconnect: String { t("Reconnecting", "重新连接") }
    var reasonDisconnected: String { t("Headset disconnected", "耳机已断开") }
    var reasonConfigUpdated: String { t("Config updated", "配置已更新") }
    var reasonSleep: String { t("System sleep", "系统休眠") }

    func switchedMic(_ name: String) -> String {
        t("Switched mic → \(name)", "已切换麦克风 → \(name)")
    }

    func micLockedStatus(_ name: String) -> String {
        t("Locked mic → \(name)", "已锁定麦克风 → \(name)")
    }

    var micUnlockedStatus: String {
        t("Unlocked input microphone", "已解除麦克风锁定")
    }

    func micLockRestored(_ name: String) -> String {
        t("Restored locked mic → \(name)", "已恢复锁定麦克风 → \(name)")
    }

    func profileSwitchedStatus(_ name: String) -> String {
        t("Switched profile → \(name)", "已切换耳机配置 → \(name)")
    }

    func reasonToggleTimeout(_ seconds: Int) -> String {
        t("Auto-release \(timeoutOptionTitle(seconds))", "超时自动松开 \(timeoutOptionTitle(seconds))")
    }

    func reasonAppRulePaused(_ appName: String) -> String {
        appName.isEmpty
            ? t("Paused by App Rule", "应用规则暂停")
            : t("Paused for \(appName)", "已在 \(appName) 中暂停")
    }

    var learningPrompt: String {
        t("Press any button on your USB headset…", "请按下任意 USB 耳机上的按键…")
    }

    var learningFailed: String {
        t("Cannot start learning (Input Monitoring permission may be required)", "无法启动识别（可能缺少输入监控权限）")
    }

    func learnedButton(product: String, button: HIDButton) -> String {
        let name = buttonDisplayName(button)
        return t("Learned: \(product) · \(name) (\(button.codeTag))", "已识别：\(product) · \(name) (\(button.codeTag))")
    }

    func eventPassthrough(_ button: HIDButton, down: Bool) -> String {
        let name = buttonDisplayName(button)
        let action = down ? t("down", "按下") : t("up", "松开")
        return t("\(name) \(action) → Native passthrough", "\(name) \(action) → 原生透传")
    }

    func eventRaw(_ button: HIDButton, down: Bool) -> String {
        let name = buttonDisplayName(button)
        let action = down ? t("down", "按下") : t("up", "松开")
        return "\(name) \(action)"
    }

    func eventReleasedAll(_ reason: String) -> String {
        t("Released keys (\(reason))", "已释放按键（\(reason)）")
    }

    func eventHolding(_ button: HIDButton) -> String {
        t("\(buttonDisplayName(button)) holding…", "\(buttonDisplayName(button)) 按住中…")
    }

    func eventTapPassthrough(_ button: HIDButton) -> String {
        t("\(buttonDisplayName(button)) tap → Native passthrough", "\(buttonDisplayName(button)) 短按 → 原生透传")
    }

    func eventTap(_ button: HIDButton) -> String {
        t("\(buttonDisplayName(button)) tap", "\(buttonDisplayName(button)) 短按")
    }

    func eventTapKey(_ button: HIDButton, combo: KeyCombo) -> String {
        t("\(buttonDisplayName(button)) tap → \(combo)", "\(buttonDisplayName(button)) 短按 → \(combo)")
    }

    func eventDoubleTapKey(_ button: HIDButton, combo: KeyCombo) -> String {
        t("\(buttonDisplayName(button)) double-tap → \(combo)", "\(buttonDisplayName(button)) 双击 → \(combo)")
    }

    func eventTriggerCancelled(_ button: HIDButton) -> String {
        t("\(buttonDisplayName(button)) trigger cancelled", "\(buttonDisplayName(button)) 已取消触发")
    }

    func eventToggleArmed(_ button: HIDButton, combo: KeyCombo) -> String {
        t("\(buttonDisplayName(button)) engages on release → \(combo)", "\(buttonDisplayName(button)) 松手后开启 → \(combo)")
    }

    func eventReleased(_ button: HIDButton) -> String {
        t("\(buttonDisplayName(button)) released", "\(buttonDisplayName(button)) 已松开")
    }

    func eventEngaged(_ button: HIDButton, combo: KeyCombo) -> String {
        t("\(buttonDisplayName(button)) engaged → \(combo) down", "\(buttonDisplayName(button)) 触发 → \(combo) 按下")
    }

    func eventDisengaged(_ button: HIDButton, combo: KeyCombo) -> String {
        t("\(buttonDisplayName(button)) ended → \(combo) up", "\(buttonDisplayName(button)) 结束 → \(combo) 松开")
    }
}
