import SwiftUI

extension Color {
    static let signalOrange = Color(red: 0.976, green: 0.341, blue: 0.133)
}

struct SectionTitleView: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.leading, 2)
    }
}

extension View {
    func cordCardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func cordBannerStyle(color: Color, strokeOpacity: Double = 0.3) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(color.opacity(0.11))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(strokeOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Full-width equal-segment selector that stretches edge-to-edge across popover cards
/// and keeps crisp active-segment contrast in Light, Dark, and unfocused popover states.
struct FullWidthSegmentedControl<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = (selection == option)
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.signalOrange : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .frame(maxWidth: .infinity)
    }
}

/// Crisp, focus-independent capsule toggle switch using Signal Orange when ON and a clearly
/// delineated neutral track when OFF so state is unmistakable on macOS popover surfaces.
struct TactileSwitchStyle: ToggleStyle {
    var onColor: Color = .signalOrange

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        Button {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? onColor : Color.primary.opacity(0.16))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 34, height: 19)

                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
                    .padding(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Solid, vivid CTA button style that never washes out to flat gray if the popover loses focus.
struct ProminentCTAButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
