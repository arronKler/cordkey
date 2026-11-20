import AppKit
import SwiftUI

/// Captures keyboard shortcuts (single keys, multi-modifier chords, Caps Lock) via a local NSEvent monitor.
final class KeyRecorder: ObservableObject {
    @Published private(set) var recordingButton: HIDButton? = nil

    private var keyMonitor: Any? = nil
    private var pendingModCodes: [UInt16] = []
    private var chordModCodes: [UInt16] = []

    deinit {
        stop()
    }

    func start(for button: HIDButton, state: AppState) {
        state.stopLearningHeadsetButton()
        stop()
        recordingButton = button
        pendingModCodes = []
        chordModCodes = []
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self, weak state] event in
            guard let self, let state, let activeButton = self.recordingButton else { return event }

            if event.type == .keyDown {
                let code = event.keyCode
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

                if code == 53 && flags.isEmpty {
                    self.stop()
                    return nil
                }

                guard let keyName = KeyTable.knownName(for: code) else {
                    // Keep recorder active and inform the user instead of silently aborting.
                    state.lastEvent = state.l10n.unsupportedRecordedKey(code)
                    return nil
                }

                var parts: [String] = []
                let canonicalMods: [(NSEvent.ModifierFlags, String)] = [
                    (.command, "command"),
                    (.control, "control"),
                    (.option, "option"),
                    (.shift, "shift"),
                ]
                for (flag, fallbackName) in canonicalMods where flags.contains(flag) {
                    let specific = self.pendingModCodes
                        .filter { Self.modifierFlag(for: $0) == flag }
                        .compactMap { KeyTable.knownName(for: $0) }
                    if specific.isEmpty {
                        parts.append(fallbackName)
                    } else {
                        parts.append(contentsOf: specific)
                    }
                }
                if self.pendingModCodes.contains(63), event.modifierFlags.contains(.function) {
                    parts.append("fn")
                }
                parts.append(keyName)

                self.pendingModCodes.removeAll()
                self.chordModCodes.removeAll()
                state.setKey(parts.joined(separator: "+"), for: activeButton)
                self.stop()
                return nil
            }

            if event.type == .flagsChanged {
                let code = event.keyCode
                let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])

                // Caps Lock (57) toggles hardware state via flagsChanged rather than keyDown.
                if code == 57 {
                    var parts = self.pendingModCodes.compactMap { KeyTable.knownName(for: $0) }
                    parts.append("caps_lock")
                    state.setKey(parts.joined(separator: "+"), for: activeButton)
                    self.stop()
                    return nil
                }

                if relevant.isEmpty {
                    if !self.chordModCodes.isEmpty {
                        let names = self.chordModCodes.compactMap { KeyTable.knownName(for: $0) }
                        if !names.isEmpty {
                            state.setKey(names.joined(separator: "+"), for: activeButton)
                        }
                        self.pendingModCodes.removeAll()
                        self.chordModCodes.removeAll()
                        self.stop()
                    }
                    return nil
                }

                if let flag = Self.modifierFlag(for: code), KeyTable.isModifier(code: code) {
                    if relevant.contains(flag) && !self.pendingModCodes.contains(code) {
                        self.pendingModCodes.append(code)
                        if !self.chordModCodes.contains(code) {
                            self.chordModCodes.append(code)
                        }
                    } else {
                        self.pendingModCodes.removeAll { $0 == code }
                    }
                }
                self.pendingModCodes.removeAll { modCode in
                    guard let flag = Self.modifierFlag(for: modCode) else { return true }
                    return !relevant.contains(flag)
                }
                return nil
            }

            return event
        }
    }

    private static func modifierFlag(for code: UInt16) -> NSEvent.ModifierFlags? {
        switch code {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    func stop() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        recordingButton = nil
        pendingModCodes = []
        chordModCodes = []
    }
}

struct MappingsCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: KeyRecorder

    @State private var editingRow: ButtonRowItem? = nil
    @State private var manualText: String = ""
    @State private var manualError: String? = nil
    @FocusState private var manualFieldFocused: Bool

    private var l10n: L10n { state.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitleView(l10n.sectionMappings)
                Spacer()
                if recorder.recordingButton != nil {
                    Text(l10n.promptPressKeyboard)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.signalOrange)
                } else if state.isLearningHeadsetButton {
                    Button(l10n.promptPressHeadsetCancel) {
                        state.stopLearningHeadsetButton()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .tint(.signalOrange)
                } else {
                    Button {
                        cancelManualEdit()
                        recorder.stop()
                        state.startLearningHeadsetButton()
                    } label: {
                        Label(l10n.learnButton, systemImage: "plus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.signalOrange)
                    .help(l10n.learnButtonHelp)
                }
            }

            VStack(spacing: 0) {
                let rows = state.settings.allButtonRows(l10n)
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { Divider().padding(.leading, 32) }
                    mappingRow(for: row)
                    if editingRow?.button == row.button {
                        Divider().padding(.leading, 32)
                        inlineManualEditor(for: row)
                    }
                }
            }
            .cordCardStyle()
        }
        .onDisappear {
            cancelManualEdit()
        }
    }

    private func mappingRow(for row: ButtonRowItem) -> some View {
        let isPressed = state.physicalButtons.contains(row.button) || state.highlightedButton == row.button
        let isRecording = (recorder.recordingButton == row.button)
        let currentKey = AppSettings.canonicalKeyText(state.settings.keyText(for: row.button))

        return HStack(spacing: 7) {
            Image(systemName: row.symbolName)
                .font(.system(size: 12))
                .foregroundColor(isPressed ? .signalOrange : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 12, weight: isPressed ? .semibold : .regular))
                    .lineLimit(1)
                if let sub = row.subtitle {
                    Text(sub)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 74, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 4)

            if isRecording {
                Button(l10n.waitingForKey) {
                    recorder.stop()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.signalOrange)
            } else {
                Menu {
                    ForEach(AppSettings.presets(l10n)) { preset in
                        Button {
                            state.stopLearningHeadsetButton()
                            recorder.stop()
                            cancelManualEdit()
                            state.setKey(preset.value, for: row.button)
                        } label: {
                            HStack {
                                Text(preset.title)
                                if currentKey == preset.value { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Divider()
                    Button(l10n.menuRecordShortcut) {
                        cancelManualEdit()
                        recorder.start(for: row.button, state: state)
                    }
                    Button(l10n.menuManualKey) {
                        beginManualEdit(for: row)
                    }
                    Divider()
                    Button {
                        state.stopLearningHeadsetButton()
                        recorder.stop()
                        cancelManualEdit()
                        state.setKey("", for: row.button)
                    } label: {
                        HStack {
                            Text(l10n.menuUnmap(row.nativeLabel))
                            if currentKey.isEmpty { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Text(state.settings.displayName(for: row, l10n: l10n))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 56, maxWidth: 108, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)

                Button {
                    cancelManualEdit()
                    recorder.start(for: row.button, state: state)
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(l10n.recordShortcutHelp)

                if row.isRemovable {
                    Button {
                        if editingRow?.button == row.button { cancelManualEdit() }
                        state.removeCustomButton(row.button)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.removeCustomButtonHelp)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isPressed ? Color.signalOrange.opacity(0.14) : Color.clear)
    }

    private func inlineManualEditor(for row: ButtonRowItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.manualKeyTitle(row.title))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField(
                    l10n.manualKeyPlaceholder,
                    text: Binding(
                        get: { manualText },
                        set: { newValue in
                            manualText = newValue
                            if manualError != nil { manualError = nil }
                        }
                    )
                )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .focused($manualFieldFocused)
                    .onSubmit { commitManualEdit(for: row.button) }

                Button(l10n.cancelButton) {
                    cancelManualEdit()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button(l10n.okButton) {
                    commitManualEdit(for: row.button)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.signalOrange)
            }

            if let err = manualError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .onExitCommand {
            cancelManualEdit()
        }
    }

    private func beginManualEdit(for row: ButtonRowItem) {
        state.stopLearningHeadsetButton()
        recorder.stop()
        editingRow = row
        manualText = state.settings.keyText(for: row.button)
        manualError = nil
        DispatchQueue.main.async {
            manualFieldFocused = true
        }
    }

    private func cancelManualEdit() {
        editingRow = nil
        manualText = ""
        manualError = nil
        manualFieldFocused = false
    }

    private func commitManualEdit(for button: HIDButton) {
        let trimmed = manualText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty && KeyCombo.parse(trimmed) == nil {
            manualError = l10n.invalidKeyInline(trimmed)
            manualFieldFocused = true
            return
        }
        state.setKey(trimmed, for: button)
        cancelManualEdit()
    }
}
