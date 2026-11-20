import AppKit
import Foundation
import SwiftUI

enum HUDPosition: String, CaseIterable, Identifiable, Codable {
    case topCenter
    case bottomCenter

    var id: String { rawValue }
}

/// Manages a borderless, non-activating floating pill HUD showing the currently held key,
/// elapsed duration, and a one-click release button without stealing keyboard focus.
final class FloatingHUDController {
    var isEnabled: Bool = false {
        didSet { if !isEnabled { hide() } }
    }

    var position: HUDPosition = .topCenter {
        didSet {
            guard oldValue != position else { return }
            onMain { [weak self] in
                guard let self, self.isVisible else { return }
                self.repositionPanel(preferMouseScreen: true)
            }
        }
    }

    var onReleaseRequested: (() -> Void)?

    private let model = HUDViewModel()
    private var panel: NonActivatingHUDPanel?
    private var hostingView: FirstMouseHostingView<FloatingHUDPillView>?
    private var activeScreen: NSScreen?
    private var isVisible: Bool = false
    private var animationGeneration: UInt64 = 0

    deinit {
        guard let panel else { return }
        let closePanel = { panel.orderOut(nil); panel.close() }
        if Thread.isMainThread { closePanel() } else { DispatchQueue.main.async(execute: closePanel) }
    }

    func update(heldLabel: String?, elapsedSeconds: Int, releaseHint: String) {
        onMain { [weak self] in
            guard let self else { return }
            guard self.isEnabled, let label = heldLabel else {
                self.fadeOut()
                return
            }
            self.model.heldLabel = label
            self.model.elapsedSeconds = max(0, elapsedSeconds)
            self.model.releaseHint = releaseHint
            if !self.model.isActive { self.model.isActive = true }
            self.ensurePanel()
            self.fadeInAndLayout()
        }
    }

    func hide() {
        onMain { [weak self] in
            guard let self else { return }
            self.animationGeneration &+= 1
            if self.model.isActive { self.model.isActive = false }
            self.isVisible = false
            self.activeScreen = nil
            self.panel?.alphaValue = 0
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let pill = FloatingHUDPillView(model: model) { [weak self] in self?.onReleaseRequested?() }
        let hosting = FirstMouseHostingView(rootView: pill)
        hosting.sizingOptions = .preferredContentSize
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let hudPanel = NonActivatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hudPanel.level = .floating
        hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hudPanel.isOpaque = false
        hudPanel.backgroundColor = .clear
        hudPanel.hasShadow = true
        hudPanel.hidesOnDeactivate = false
        hudPanel.ignoresMouseEvents = false
        hudPanel.isMovableByWindowBackground = false
        hudPanel.becomesKeyOnlyIfNeeded = true
        hudPanel.contentView = hosting
        self.hostingView = hosting
        self.panel = hudPanel
    }

    private func fadeInAndLayout() {
        guard let panel else { return }
        let wasVisible = isVisible
        animationGeneration &+= 1
        repositionPanel(preferMouseScreen: !wasVisible)
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            isVisible = true
            animateAlpha(panel: panel, to: 1, duration: 0.16, timing: .easeOut)
        } else if panel.alphaValue < 1 {
            panel.orderFrontRegardless()
            animateAlpha(panel: panel, to: 1, duration: 0.14, timing: .easeOut)
        }
    }

    private func fadeOut() {
        guard let panel, isVisible else {
            if model.isActive { model.isActive = false }
            return
        }
        animationGeneration &+= 1
        let token = animationGeneration
        isVisible = false
        if model.isActive { model.isActive = false }
        activeScreen = nil
        animateAlpha(panel: panel, to: 0, duration: 0.14, timing: .easeIn) { [weak self, weak panel] in
            DispatchQueue.main.async {
                guard let self, self.animationGeneration == token else { return }
                panel?.orderOut(nil)
            }
        }
    }

    private func animateAlpha(
        panel: NSPanel,
        to target: CGFloat,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = target
        }, completionHandler: completion)
    }

    private func repositionPanel(preferMouseScreen: Bool) {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let screen = targetScreen(preferMouseScreen: preferMouseScreen)
        activeScreen = screen
        let origin: NSPoint
        if let screen {
            let visible = screen.visibleFrame
            let rawX = visible.midX - (size.width / 2)
            let rawY = (position == .topCenter) ? (visible.maxY - size.height - 14) : (visible.minY + 20)
            let minX = visible.minX + 8
            let maxX = max(minX, visible.maxX - size.width - 8)
            let minY = visible.minY + 8
            let maxY = max(minY, visible.maxY - size.height - 8)
            origin = NSPoint(x: min(max(rawX.rounded(), minX), maxX), y: min(max(rawY.rounded(), minY), maxY))
        } else {
            origin = panel.frame.origin
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    private func targetScreen(preferMouseScreen: Bool) -> NSScreen? {
        if !preferMouseScreen, let activeScreen, NSScreen.screens.contains(activeScreen) { return activeScreen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}

private final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class HUDViewModel: ObservableObject {
    @Published var heldLabel: String = ""
    @Published var elapsedSeconds: Int = 0
    @Published var releaseHint: String = ""
    @Published var isActive: Bool = false
}

private struct HUDVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.state = .active }
}

private struct FloatingHUDPillView: View {
    @ObservedObject var model: HUDViewModel
    let onRelease: () -> Void
    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        Button(action: onRelease) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.signalOrange.opacity(0.35)).frame(width: 14, height: 14)
                        .scaleEffect(isPulsing ? 1.28 : 0.72).opacity(isPulsing ? 0.12 : 0.65)
                    Circle().fill(Color.signalOrange).frame(width: 7.5, height: 7.5)
                }
                Text(model.heldLabel)
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(.primary)
                    .lineLimit(1).fixedSize()
                Rectangle().fill(Color.primary.opacity(0.16)).frame(width: 1, height: 12)
                Text(String(format: "%d:%02d", model.elapsedSeconds / 60, model.elapsedSeconds % 60))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary).fixedSize()
                if !model.releaseHint.isEmpty {
                    Text(model.releaseHint)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(.secondary).lineLimit(1).fixedSize()
                }
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(isHovered ? Color.signalOrange : .secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(isHovered ? Color.signalOrange.opacity(0.18) : Color.primary.opacity(0.08)))
            }
            .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 6)
            .background(
                ZStack {
                    HUDVisualEffectView()
                    Color(nsColor: .windowBackgroundColor).opacity(0.18)
                }
            )
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isHovered ? Color.signalOrange.opacity(0.45) : Color.primary.opacity(0.14), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering } }
        .help(model.releaseHint)
        .onReceive(model.$isActive) { active in
            if active {
                guard !isPulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
            } else if isPulsing {
                withAnimation(.linear(duration: 0.05)) { isPulsing = false }
            }
        }
    }
}

/// Race-free one-shot timer on the main queue for Click-Toggle auto-release safety timeouts.
final class ToggleTimeoutController {
    static let presetSeconds: [Int] = [0, 60, 120, 300]

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    deinit { cancel() }

    func arm(seconds: Int, onTimeout: @escaping () -> Void) {
        lock.lock()
        timer?.cancel()
        timer = nil
        guard seconds > 0 else { lock.unlock(); return }

        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now() + .seconds(seconds), leeway: .milliseconds(250))
        newTimer.setEventHandler { [weak self, weak newTimer] in
            guard let self else { return }
            self.lock.lock()
            guard let activeTimer = newTimer, !activeTimer.isCancelled, self.timer === activeTimer else {
                self.lock.unlock()
                return
            }
            self.timer = nil
            activeTimer.cancel()
            self.lock.unlock()
            onTimeout()
        }
        self.timer = newTimer
        lock.unlock()
        newTimer.resume()
    }

    func cancel() {
        lock.lock()
        timer?.cancel()
        timer = nil
        lock.unlock()
    }
}
