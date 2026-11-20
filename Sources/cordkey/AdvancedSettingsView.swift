import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var state: AppState

    private var l10n: L10n { state.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 2)

            HStack {
                Label(l10n.exclusiveMode, systemImage: "lock.shield")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.settings.seize },
                    set: { state.setSeize($0) }
                ))
                .toggleStyle(TactileSwitchStyle())
                .labelsHidden()
            }

            HStack {
                Label(l10n.keyRepeatLabel, systemImage: "repeat")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.settings.keyRepeat },
                    set: { state.setKeyRepeat($0) }
                ))
                .toggleStyle(TactileSwitchStyle())
                .labelsHidden()
            }

            HStack {
                Label(l10n.usbHeadset, systemImage: "cable.connector")
                    .font(.system(size: 11.5))
                Spacer()
                Menu {
                    if state.hidDevices.isEmpty {
                        Text(l10n.noHeadsetsFound)
                    } else {
                        ForEach(Array(state.hidDevices.enumerated()), id: \.offset) { _, dev in
                            Button {
                                state.selectHIDDevice(vendorID: dev.vendorID, productID: dev.productID)
                            } label: {
                                let label = String(
                                    format: "%@ · %@ [%@] (0x%04x:0x%04x)",
                                    dev.product, dev.transport, dev.pagesLabel, dev.vendorID, dev.productID
                                )
                                HStack {
                                    Text(label)
                                    if dev.vendorID == state.settings.vendorID && dev.productID == state.settings.productID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button(l10n.resetToEarPods) {
                        state.selectHIDDevice(vendorID: 0x05ac, productID: 0x110b)
                    }
                    Button(l10n.refreshDevices) {
                        state.refreshDevices()
                    }
                } label: {
                    Text(String(format: "0x%04x:0x%04x", state.settings.vendorID, state.settings.productID))
                        .font(.system(size: 11, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(l10n.autoSwitchProfiles, systemImage: "headphones")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.settings.autoSwitchProfiles },
                        set: { state.setAutoSwitchProfiles($0) }
                    ))
                    .toggleStyle(TactileSwitchStyle())
                    .labelsHidden()
                }

                HStack(spacing: 6) {
                    Text(l10n.savedProfilesCount(state.savedProfiles.count))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !state.savedProfiles.isEmpty {
                        Menu {
                            ForEach(state.savedProfiles) { profile in
                                Button {
                                    state.deleteProfile(id: profile.id)
                                } label: {
                                    let title = profile.deviceName.isEmpty ? profile.id : "\(profile.deviceName) (\(profile.id))"
                                    Label(title, systemImage: "trash")
                                }
                            }
                            Divider()
                            Button(l10n.clearProfilesButton, role: .destructive) {
                                state.clearAllProfiles()
                            }
                        } label: {
                            Text(l10n.manageProfilesLabel)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.leading, 20)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(l10n.bluetoothModeLabel, systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.settings.bluetoothMode },
                        set: { state.setBluetoothMode($0) }
                    ))
                    .toggleStyle(TactileSwitchStyle())
                    .labelsHidden()
                }

                Text(l10n.bluetoothModeNote)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)

                if state.settings.bluetoothMode && state.bluetoothTapFailed {
                    Text(l10n.bluetoothTapFailedStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                }
            }

            Divider()

            AppRulesSectionView(state: state)
        }
        .padding(.top, 4)
    }
}
