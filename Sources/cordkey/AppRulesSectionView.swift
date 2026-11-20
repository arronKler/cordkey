import SwiftUI

struct AppRulesSectionView: View {
    @ObservedObject var state: AppState

    @State private var customTarget: RunningAppInfo? = nil
    @State private var customKeyText: String = ""
    @State private var customKeyError: String? = nil
    @FocusState private var customFieldFocused: Bool

    private var l10n: L10n { state.l10n }

    private static let quickOverrideKeys: [String] = [
        "command+shift+d",
        "command+shift+a",
        "command+shift+m",
        "f13",
        "right_option",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(l10n.appRulesLabel, systemImage: "app.badge.checkmark")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.settings.appRulesEnabled },
                    set: { state.setAppRulesEnabled($0) }
                ))
                .toggleStyle(TactileSwitchStyle())
                .labelsHidden()
            }

            if state.settings.appRulesEnabled {
                if state.settings.appRules.isEmpty {
                    Text(l10n.appRulesEmptyHint)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 4) {
                        ForEach(state.settings.appRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }

                if let target = customTarget {
                    customKeyEditor(for: target)
                }

                HStack {
                    Menu {
                        Section(l10n.appRulesQuickPresets) {
                            ForEach(AppRule.commonPresets) { preset in
                                Button {
                                    state.addAppRule(preset.makeRule())
                                } label: {
                                    Text("\(preset.appName) · \(actionBadge(preset.action))")
                                }
                            }
                        }
                        if !state.runningApps.isEmpty {
                            Divider()
                            Section(l10n.appRulesRunningApps) {
                                ForEach(state.runningApps) { app in
                                    Menu(app.name) {
                                        Button(l10n.appRuleActionPause) {
                                            state.addAppRule(AppRule(bundleID: app.bundleID, appName: app.name, action: .pause))
                                        }
                                        Divider()
                                        ForEach(Self.quickOverrideKeys, id: \.self) { key in
                                            let label = state.settings.displayName(forKeyText: key, emptyLabel: key, l10n: l10n)
                                            Button("\(l10n.appRuleActionMutePrefix) \(label)") {
                                                state.addAppRule(AppRule(bundleID: app.bundleID, appName: app.name, action: .overridePlay(key)))
                                            }
                                        }
                                        Divider()
                                        Button(l10n.appRuleCustomKeyItem) {
                                            beginCustomKeyEdit(for: app)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(l10n.addRuleButton, systemImage: "plus.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .onTapGesture {
                        state.refreshRunningApps()
                    }
                    Spacer()
                }
                .onAppear {
                    state.refreshRunningApps()
                }
            }
        }
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        let isActive = state.activeAppRule?.id.caseInsensitiveCompare(rule.id) == .orderedSame
        return HStack(spacing: 6) {
            Button {
                state.toggleAppRule(id: rule.id)
            } label: {
                Image(systemName: rule.enabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11.5))
                    .foregroundColor(rule.enabled ? .signalOrange : .secondary)
            }
            .buttonStyle(.plain)

            Text(rule.appName)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(rule.enabled ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isActive {
                Circle()
                    .fill(Color.signalOrange)
                    .frame(width: 5, height: 5)
            }

            Spacer(minLength: 4)

            Text(actionBadge(rule.action))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Button {
                state.removeAppRule(id: rule.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isActive ? Color.signalOrange.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func actionBadge(_ action: AppRuleAction) -> String {
        switch action {
        case .pause:
            return l10n.appRulePauseLabel
        case .overridePlay(let key):
            return state.settings.displayName(forKeyText: key, emptyLabel: key, l10n: l10n)
        }
    }

    private func customKeyEditor(for app: RunningAppInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(l10n.appRuleCustomTitle(app.name))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 5) {
                TextField(
                    l10n.manualKeyPlaceholder,
                    text: Binding(
                        get: { customKeyText },
                        set: { val in
                            customKeyText = val
                            if customKeyError != nil { customKeyError = nil }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .focused($customFieldFocused)
                .onSubmit { commitCustomKeyEdit(for: app) }

                Button(l10n.cancelButton) {
                    customTarget = nil
                    customKeyError = nil
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)

                Button(l10n.okButton) {
                    commitCustomKeyEdit(for: app)
                }
                .controlSize(.mini)
                .buttonStyle(.borderedProminent)
                .tint(.signalOrange)
            }
            if let err = customKeyError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func beginCustomKeyEdit(for app: RunningAppInfo) {
        customTarget = app
        customKeyText = "command+shift+d"
        customKeyError = nil
        DispatchQueue.main.async {
            customFieldFocused = true
        }
    }

    private func commitCustomKeyEdit(for app: RunningAppInfo) {
        let trimmed = customKeyText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, KeyCombo.parse(trimmed) != nil else {
            customKeyError = l10n.invalidKeyInline(trimmed)
            customFieldFocused = true
            return
        }
        let canonical = AppSettings.canonicalKeyText(trimmed)
        state.addAppRule(AppRule(bundleID: app.bundleID, appName: app.name, action: .overridePlay(canonical)))
        customTarget = nil
        customKeyText = ""
        customKeyError = nil
    }
}
