import AppKit
import SwiftUI

/// The one and only island window. It sits centered under the notch and grows
/// or shrinks in place between four states:
///   • idle     — collapsed into the notch (just a black pill)
///   • hover    — mouse over it: a subtle bulge (no content)
///   • peek     — dwelled ~1s: the music player drapes down
///   • expanded — clicked open: a wide bar wrapping around the notch
/// Idle/hover/peek keep the notch width and grow downward; expanded also grows
/// symmetrically sideways, staying centered on the notch.
final class NotchWindow: NSWindow {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        let startFrame = NotchDetector.islandFrame(for: NotchDetector.idleSize())

        super.init(
            contentRect: startFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setupWindow()
    }

    // Allow the window to key so buttons/sliders in the expanded UI respond,
    // without showing a title bar.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func setupWindow() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = IslandContainerView(appState: appState)
        container.frame = contentRect(forFrameRect: frame)
        self.contentView = container

        orderFront(nil)
    }

    // Animation state. The island snaps between sizes on a damped spring, so it
    // reads as a quick, springy "Q弹" pop with a touch of overshoot rather than
    // a slow drape.
    private var animTimer: Timer?
    private var animStart = NSRect.zero
    private var animTarget = NSRect.zero
    private var animElapsed: TimeInterval = 0
    /// Seconds per frame for the current animation, matched to the display's
    /// refresh rate so we don't schedule redraws the screen can't show.
    private var animFrameInterval: TimeInterval = 1.0 / 60.0
    /// Animation-speed multiplier, sampled once when the animation starts rather
    /// than re-read from UserDefaults on every frame.
    private var animSpeed: Double = 1

    /// Spring "response" (roughly the settling period) in seconds. Small = snappy.
    private let springResponse: TimeInterval = 0.34
    /// Damping ratio. < 1 underdamps → a little overshoot/bounce (the Q弹 feel).
    private let springDamping: Double = 0.62

    /// Resizes/repositions the window to match the island's current mode.
    /// Width/x and height/y all spring toward the target; expanding grows
    /// symmetrically around the notch, collapsing snaps crisply back in.
    func animate(to mode: IslandMode) {
        if mode == .expanded {
            makeKeyAndOrderFront(nil)
        }

        // Idle uses the real notch size so the collapsed pill matches exactly.
        let targetSize = mode == .idle ? NotchDetector.idleSize() : mode.size
        animTarget = NotchDetector.islandFrame(for: targetSize)
        animStart = frame
        animElapsed = 0

        // Sample the (fixed-for-this-run) inputs once, up front.
        let speed = SettingsManager.shared.animationSpeed
        animSpeed = speed > 0 ? speed : 1
        let fps = (screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60
        animFrameInterval = 1.0 / Double(max(fps, 30))

        animTimer?.invalidate()
        // Step the spring toward the target at the display's cadence.
        animTimer = Timer.scheduledTimer(withTimeInterval: animFrameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepAnimation()
            }
        }
    }

    /// Normalized position (0→1, with overshoot) of an underdamped spring at
    /// time `t`, parameterized like SwiftUI's `.spring(response:dampingFraction:)`.
    /// Returns the fraction of the way from start to target, plus whether the
    /// spring has effectively settled.
    private func springValue(_ t: Double) -> (value: CGFloat, settled: Bool) {
        let zeta = springDamping
        let omega0 = 2 * Double.pi / springResponse           // natural frequency
        if zeta < 1 {
            // Underdamped: decaying oscillation → gentle overshoot.
            let omegaD = omega0 * (1 - zeta * zeta).squareRoot()  // damped frequency
            let decay = exp(-zeta * omega0 * t)
            let p = 1 - decay * (cos(omegaD * t) + (zeta * omega0 / omegaD) * sin(omegaD * t))
            // Settled once the envelope has decayed to a hair.
            let settled = decay < 0.01 && t > springResponse * 0.5
            return (CGFloat(p), settled)
        } else {
            // Critically damped fallback: no overshoot.
            let decay = exp(-omega0 * t)
            let p = 1 - decay * (1 + omega0 * t)
            return (CGFloat(p), decay < 0.01 && t > springResponse * 0.5)
        }
    }

    private func stepAnimation() {
        animElapsed += animFrameInterval * animSpeed

        let (eased, settled) = springValue(animElapsed)

        // Every frame stays centered on the notch (x = midX - w/2), so growing
        // the width expands symmetrically toward BOTH sides — the expanded bar
        // wraps out around the notch evenly. All edges spring together.
        let newFrame = NSRect(
            x: animStart.origin.x + (animTarget.origin.x - animStart.origin.x) * eased,
            y: animStart.origin.y + (animTarget.origin.y - animStart.origin.y) * eased,
            width: animStart.width + (animTarget.width - animStart.width) * eased,
            height: animStart.height + (animTarget.height - animStart.height) * eased
        )
        setFrame(newFrame, display: true)

        if settled {
            setFrame(animTarget, display: true)
            animTimer?.invalidate()
            animTimer = nil
        }
    }
}

/// An NSHostingView that delivers the first click even when the window isn't
/// key, so a tap on the island advances the reveal immediately rather than just
/// activating the window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts the SwiftUI island and owns the tracking area that drives hover state.
/// Using an explicit tracking area (rather than SwiftUI `.onHover`) makes the
/// enter/exit reliable as the window resizes.
private final class IslandContainerView: NSView {
    private let appState: AppState
    private var trackingArea: NSTrackingArea?

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)

        let hosting = FirstMouseHostingView(rootView: IslandView(appState: appState))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // React to clicks even when the window isn't key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        appState.mouseEnteredNotch()
    }

    override func mouseExited(with event: NSEvent) {
        // Leaving the island collapses everything back into the notch.
        appState.mouseExitedNotch()
    }
}
