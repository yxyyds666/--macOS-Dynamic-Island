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

    // Animation state. The island drapes straight down out of the notch on a
    // cubic-bézier ease (no spring/overshoot) over a fixed, unhurried duration.
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

    /// The reveal duration, in seconds, at animation-speed 1. Kept deliberately
    /// slow so the downward drape is easy to read.
    private let animDuration: TimeInterval = 0.55

    /// Resizes/repositions the window to match the island's current mode. Only
    /// the height/y animate (width/x are pinned), so it reads as a top-down drop.
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
        // Step a bézier-eased frame toward the target at the display's cadence.
        animTimer = Timer.scheduledTimer(withTimeInterval: animFrameInterval, repeats: true) { [weak self] _ in
            self?.stepAnimation()
        }
    }

    /// Solves the standard cubic-bézier timing curve with control points
    /// (0,0)-(x1,y1)-(x2,y2)-(1,1) for the eased output at fractional time `x`.
    /// This is the same math CSS/CoreAnimation use for `cubic-bezier(...)`.
    private func bezierEase(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        // Bézier basis for a coordinate given control values c1, c2 (p0=0, p3=1).
        func value(_ t: Double, _ c1: Double, _ c2: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * c1 + 3 * mt * t * t * c2 + t * t * t
        }
        // Invert x(t) = x to find t, then evaluate y(t). Bisection is plenty here.
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            let xt = value(t, x1, x2)
            if abs(xt - x) < 1e-5 { break }
            if xt < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return value(t, y1, y2)
    }

    private func stepAnimation() {
        animElapsed += animFrameInterval * animSpeed

        let fraction = min(animElapsed / animDuration, 1)
        // Gentle iOS-style ease-in-out. Slow start, slow finish, no overshoot.
        let eased = CGFloat(bezierEase(fraction, 0.33, 0.0, 0.15, 1.0))

        // Every frame stays centered on the notch (x = midX - w/2), so growing
        // the width expands symmetrically toward BOTH sides — the expanded bar
        // wraps out around the notch evenly. Height eases at the same time so
        // peek (unchanged width) reads as a straight-down drape.
        let newFrame = NSRect(
            x: animStart.origin.x + (animTarget.origin.x - animStart.origin.x) * eased,
            y: animStart.origin.y + (animTarget.origin.y - animStart.origin.y) * eased,
            width: animStart.width + (animTarget.width - animStart.width) * eased,
            height: animStart.height + (animTarget.height - animStart.height) * eased
        )
        setFrame(newFrame, display: true)

        if fraction >= 1 {
            setFrame(animTarget, display: true)
            animTimer?.invalidate()
            animTimer = nil
        }
    }
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

        let hosting = NSHostingView(rootView: IslandView(appState: appState))
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
