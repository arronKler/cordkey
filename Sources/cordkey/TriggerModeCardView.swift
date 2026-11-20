import SwiftUI

private enum TapActionTarget: Equatable {
    case shortTap
    case doubleTap
}

struct TriggerModeCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: KeyRecorder

    @State private var editingTapTarget: TapActionTarget? = nil
    @State private var tapManualText: String = ""
    @State private var tapManualError: String? = nil
    @FocusState private var tapFieldFocused: Bool

    private var l10n: L10n { state.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitleView(l10n.sectionTriggerMode)

            VStack(alignment: .leading, spacing: 8) {
                FullWidthSegmentedControl(
                    options: TriggerMode.allCases,
                    selection: Binding(
                        get: { state.settings.triggerMode },
                        set: { state.setTriggerMode($0) }
                    ),
                    title: { $0.title(l10n) }
                )

                switch state.settings.triggerMode {
                case .hold:
                    Text(l10n.triggerHoldDesc)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .holdDelay:
                    HStack(spacing: 8) {
                        Text(l10n.holdThreshold)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        ForEach([250, 300, 500], id: \.self) { ms in
                            holdThresholdButton(ms)
                        }
                    }
                    tapActionRow(
                        target: .shortTap,
                        label: l10n.shortTapLabel,
                        emptyLabel: l10n.nativeLabel(for: .play),
                        currentText: state.settings.playTapKey,
                        onSelect: { state.setPlayTapKey($0) }
                    )
                    if editingTapTarget == .shortTap {
                        inlineTapEditor(for: .shortTap)
                    }
                    tapActionRow(
                        target: .doubleTap,
                        label: l10n.doubleTapLabel,
                        emptyLabel: l10n.offLabel,
                        currentText: state.settings.playDoubleTapKey,
                        onSelect: { state.setPlayDoubleTapKey($0) }
                    )
                    if editingTapTarget == .doubleTap {
                        inlineTapEditor(for: .doubleTap)
                    }
                    Text(l10n.triggerHoldDelayDesc)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .toggle:
                    HStack(spacing: 6) {
                        Text(l10n.autoReleaseLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        ForEach(ToggleTimeoutController.presetSeconds, id: \.self) { secs in
                            timeoutButton(secs)
                        }
                    }
                    Text(l10n.triggerToggleDesc)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .cordCardStyle()
        }
        .onDisappear {
            cancelTapManualEdit()
        }
        .onReceive(state.$settings.map(\.triggerMode).removeDuplicates().dropFirst()) { _ in
            cancelTapManualEdit()
        }
        .onReceive(recorder.$recordingButton.dropFirst()) { button in
            if button != nil { cancelTapManualEdit() }
        }
        .onReceive(state.$isLearningHeadsetButton.dropFirst()) { learning in
            if learning { cancelTapManualEdit() }
        }
    }

    @ViewBuilder
    private func holdThresholdButton(_ ms: Int) -> some View {
        if state.settings.holdMs == ms {
            Button("\(ms)ms") {
                state.setHoldMs(ms)
            }
            .buttonStyle(ProminentCTAButtonStyle(color: .signalOrange))
        } else {
            Button("\(ms)ms") {
                state.setHoldMs(ms)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func timeoutButton(_ secs: Int) -> some View {
        let title = l10n.timeoutOptionTitle(secs)
        if state.settings.toggleTimeoutSeconds == secs {
            Button(title) {
                state.setToggleTimeoutSeconds(secs)
            }
            .buttonStyle(ProminentCTAButtonStyle(color: .signalOrange))
        } else {
            Button(title) {
                state.setToggleTimeoutSeconds(secs)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    private func tapActionRow(
        target: TapActionTarget,
        label: String,
        emptyLabel: String,
        currentText: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let canonical = AppSettings.canonicalKeyText(currentText)
        let display = state.settings.displayName(forKeyText: currentText, emptyLabel: emptyLabel, l10n: l10n)
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Menu {
                Button {
                    state.stopLearningHeadsetButton()
                    recorder.stop()
                    cancelTapManualEdit()
                    onSelect("")
                } label: {
                    HStack {
                        Text(emptyLabel)
                        if canonical.isEmpty { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach(AppSettings.presets(l10n)) { preset in
                    Button {
                        state.stopLearningHeadsetButton()
                        recorder.stop()
                        cancelTapManualEdit()
                        onSelect(preset.value)
                    } label: {
                        HStack {
                            Text(preset.title)
                            if canonical == preset.value { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button(l10n.menuManualKey) {
                    beginTapManualEdit(for: target, currentText: currentText)
                }
            } label: {
                Text(display)
                    .font(.system(size: 11))
                    .foregroundColor(canonical.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func inlineTapEditor(for target: TapActionTarget) -> some View {
        let title = (target == .shortTap) ? l10n.shortTapTitle : l10n.doubleTapTitle
        let placeholder = (target == .shortTap) ? l10n.shortTapPlaceholder : l10n.doubleTapPlaceholder
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 5) {
                TextField(
                    placeholder,
                    text: Binding(
                        get: { tapManualText },
                        set: { val in
                            tapManualText = val
                            if tapManualError != nil { tapManualError = nil }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .focused($tapFieldFocused)
                .onSubmit { commitTapEdit(for: target) }

                Button(l10n.cancelButton) {
                    cancelTapManualEdit()
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)

                Button(l10n.okButton) {
                    commitTapEdit(for: target)
                }
                .controlSize(.mini)
                .buttonStyle(.borderedProminent)
                .tint(.signalOrange)
            }
            if let err = tapManualError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onExitCommand {
            cancelTapManualEdit()
        }
    }

    private func beginTapManualEdit(for target: TapActionTarget, currentText: String) {
        state.stopLearningHeadsetButton()
        recorder.stop()
        editingTapTarget = target
        tapManualText = currentText
        tapManualError = nil
        DispatchQueue.main.async {
            tapFieldFocused = true
        }
    }

    private func cancelTapManualEdit() {
        editingTapTarget = nil
        tapManualText = ""
        tapManualError = nil
        tapFieldFocused = false
    }

    private func commitTapEdit(for target: TapActionTarget) {
        let trimmed = tapManualText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty && KeyCombo.parse(trimmed) == nil {
            tapManualError = l10n.invalidKeyInline(trimmed)
            tapFieldFocused = true
            return
        }
        if target == .shortTap {
            state.setPlayTapKey(trimmed)
        } else {
            state.setPlayDoubleTapKey(trimmed)
        }
        cancelTapManualEdit()
    }
}
