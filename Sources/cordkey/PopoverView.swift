import AppKit
import SwiftUI

private struct MiddleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @ObservedObject var state: AppState
    let onQuit: () -> Void

    @StateObject private var recorder = KeyRecorder()
    @State private var showAdvanced: Bool = false
    @State private var middleHeight: CGFloat = 0

    private var l10n: L10n { state.l10n }

    private let maxMiddleHeight: CGFloat = 680

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            ScrollView(.vertical, showsIndicators: false) {
                middleContent
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 1)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: MiddleHeightKey.self, value: geo.size.height)
                        }
                    )
            }
            .scrollIndicators(.hidden)
            .frame(height: middleHeight > 0 ? min(ceil(middleHeight), maxMiddleHeight) : nil)
            .onPreferenceChange(MiddleHeightKey.self) { height in
                if abs(middleHeight - height) > 0.5 {
                    middleHeight = height
                }
            }

            footerBar
        }
        .padding(14)
        .frame(width: 356)
        .tint(.signalOrange)
        .onAppear {
            state.refreshAll()
        }
        .onDisappear {
            recorder.stop()
            state.stopLearningHeadsetButton()
        }
    }

    private var middleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.hasAXPermission {
                axWarningBanner
            }

            if state.settings.enabled && !state.isPausedByAppRule && state.hidOpenFailed {
                hidWarningBanner
            }

            if let held = state.heldSummary {
                activeHoldBanner(held: held)
            }

            if state.shouldWarnEarPodsMic {
                earPodsMicHintBanner
            }

            MappingsCardView(state: state, recorder: recorder)
            TriggerModeCardView(state: state, recorder: recorder)
            quickSettingsCard
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            CordKeyBadgeView(enabled: state.settings.enabled, accent: .signalOrange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("CordKey")
                        .font(.system(size: 14, weight: .semibold))
                    statusPill
                }
                Text(deviceSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(state.hidOpenFailed && state.settings.enabled ? .red : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { state.settings.enabled },
                set: { state.setEnabled($0) }
            ))
            .toggleStyle(TactileSwitchStyle())
            .labelsHidden()
        }
    }

    private var statusPill: some View {
        let learning = state.isLearningHeadsetButton
        let enabled = state.settings.enabled
        let appPaused = enabled && state.isPausedByAppRule
        let connected = state.connectedDevice != nil
        let btActive = enabled && !appPaused && !connected && state.settings.bluetoothMode && state.isBluetoothTapActive
        let hasOpenError = enabled && !appPaused && !connected && (state.hidOpenFailed || (state.settings.bluetoothMode && state.bluetoothTapFailed))
        let color: Color = learning
            ? .signalOrange
            : (!enabled || appPaused
                ? .secondary
                : (connected ? .green : (hasOpenError ? .red : (btActive ? .blue : .orange))))
        let label = learning
            ? l10n.pillLearning
            : (!enabled
                ? l10n.pillPaused
                : (appPaused
                    ? l10n.pillAppPaused
                    : (connected
                        ? (state.isSeized ? l10n.pillExclusive : l10n.pillShared)
                        : (hasOpenError ? l10n.pillError : (btActive ? l10n.pillBluetooth : l10n.pillDisconnected)))))
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var deviceSubtitle: String {
        if state.isLearningHeadsetButton { return l10n.learningPrompt }
        if !state.settings.enabled { return l10n.subtitlePaused }
        if state.isPausedByAppRule {
            return l10n.subtitleAppPaused(state.activeFrontmostAppName ?? state.activeAppRule?.appName ?? "")
        }
        if let dev = state.connectedDevice { return dev }
        if state.hidOpenFailed { return l10n.hidOpenFailedShort }
        if state.settings.bluetoothMode && state.bluetoothTapFailed { return l10n.bluetoothTapFailedShort }
        if state.settings.bluetoothMode && state.isBluetoothTapActive { return l10n.subtitleBluetoothActive }
        return l10n.subtitleWaiting(vendorID: state.settings.vendorID, productID: state.settings.productID)
    }

    // MARK: - Banners

    private var axWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.signalOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.axBannerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.axBannerSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.axBannerStaleHint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(l10n.axBannerButton) {
                state.openAccessibilitySettings()
            }
            .buttonStyle(ProminentCTAButtonStyle(color: .signalOrange))
        }
        .cordBannerStyle(color: .orange)
    }

    private var hidWarningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.hidBannerTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l10n.hidBannerSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                Button(l10n.hidBannerButton) {
                    state.openInputMonitoringSettings()
                }
                .buttonStyle(ProminentCTAButtonStyle(color: .signalOrange))

                Button(l10n.retryButton) {
                    state.refreshAll()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(.leading, 24)
        }
        .cordBannerStyle(color: .red)
    }

    private func activeHoldBanner(held: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.signalOrange)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.holdingTitle(held))
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.holdingElapsed(formatDuration(state.heldSeconds)))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(l10n.releaseNow) {
                state.releaseHeldKeysManually()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .cordBannerStyle(color: .signalOrange, strokeOpacity: 0.34)
    }

    private var earPodsMicHintBanner: some View {
        let builtIn = state.builtInAudioInput
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text(l10n.earPodsMicHint(hasBuiltInMic: builtIn != nil))
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button(l10n.switchToToggle) {
                    state.setTriggerMode(.toggle)
                }
                .buttonStyle(ProminentCTAButtonStyle(color: .blue))

                if let builtIn {
                    Button {
                        state.selectAudioInput(builtIn.id)
                    } label: {
                        Text(l10n.useAudioInput(builtIn.name))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }
        }
        .cordBannerStyle(color: .blue, strokeOpacity: 0.25)
    }

    // MARK: - Quick Settings Card

    private var quickSettingsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitleView(l10n.sectionAudioAndDevice)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Label(l10n.inputMic, systemImage: "mic")
                        .font(.system(size: 12))
                    Spacer()
                    Menu {
                        if state.audioInputs.isEmpty {
                            Text(l10n.noInputDevice)
                        } else {
                            ForEach(state.audioInputs) { mic in
                                Button {
                                    state.selectAudioInput(mic.id)
                                } label: {
                                    HStack {
                                        Text(mic.name)
                                        if mic.id == state.defaultAudioInputID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(state.currentAudioInput?.name ?? l10n.noInputDevice)
                            .font(.system(size: 11.5))
                            .foregroundColor(state.audioInputs.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 146, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(state.audioInputs.isEmpty)

                    Button {
                        state.toggleMicLock()
                    } label: {
                        Image(systemName: state.isMicLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(state.isMicLocked ? .signalOrange : .secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(state.isMicLocked ? Color.signalOrange.opacity(0.14) : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(state.audioInputs.isEmpty && !state.isMicLocked)
                    .help(state.isMicLocked ? l10n.micLockUnlockHelp : l10n.micLockLockHelp)
                }

                Divider()

                HStack(spacing: 6) {
                    Label(l10n.floatingHUDLabel, systemImage: "rectangle.topthird.inset.filled")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    if state.settings.showFloatingHUD {
                        Picker("", selection: Binding(
                            get: { state.settings.hudPosition },
                            set: { state.setHUDPosition($0) }
                        )) {
                            ForEach(HUDPosition.allCases) { pos in
                                Text(l10n.hudPositionTitle(pos)).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .labelsHidden()
                        .frame(width: 96)
                    }
                    Toggle("", isOn: Binding(
                        get: { state.settings.showFloatingHUD },
                        set: { state.setShowFloatingHUD($0) }
                    ))
                    .toggleStyle(TactileSwitchStyle())
                    .labelsHidden()
                }

                Divider()

                HStack {
                    Label(l10n.soundCues, systemImage: "speaker.wave.2")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.settings.soundFeedback },
                        set: { state.setSoundFeedback($0) }
                    ))
                    .toggleStyle(TactileSwitchStyle())
                    .labelsHidden()
                }

                Divider()

                HStack {
                    Label(l10n.languageLabel, systemImage: "globe")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { state.settings.language },
                        set: { state.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.pickerTitle).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: 196)
                }

                DisclosureGroup(isExpanded: $showAdvanced) {
                    AdvancedSettingsView(state: state)
                } label: {
                    Text(l10n.advancedSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .cordCardStyle()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill((state.isKeyHeld || state.isLearningHeadsetButton) ? Color.signalOrange : (state.hidOpenFailed ? Color.red : Color.secondary.opacity(0.45)))
                    .frame(width: 6, height: 6)
                Text(state.lastEvent)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            Divider()

            HStack(spacing: 10) {
                Toggle(l10n.launchAtLogin, isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 11.5))

                Spacer()

                Button(l10n.accessibilityButton) {
                    state.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)

                Text("·").foregroundColor(.secondary.opacity(0.5))

                Button(l10n.quitButton) {
                    onQuit()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.primary)
            }
        }
    }

    private func formatDuration(_ secs: Int) -> String {
        String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
