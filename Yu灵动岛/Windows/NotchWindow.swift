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
    //
    // The animation is driven by a CADisplayLink so ticks land exactly on the
    // display's vsync — no drift/judder like a free-running Timer — and each
    // frame only resizes the window (setFrame display:false), letting Core
    // Animation scale the hosting view's layer on the GPU instead of forcing a
    // synchronous CPU relayout+redraw of the whole SwiftUI tree every frame.
    private var displayLink: CADisplayLink?
    private var animStart = NSRect.zero
    private var animTarget = NSRect.zero
    private var animElapsed: TimeInterval = 0
    /// Wall-clock timestamp of the previous display-link tick, used to advance
    /// the spring by the real frame duration rather than a fixed 1/fps guess.
    private var lastTickTimestamp: CFTimeInterval = 0
    /// Animation-speed multiplier, sampled once when the animation starts rather
    /// than re-read from UserDefaults on every frame.
    private var animSpeed: Double = 1

    // The island animates on TWO independent springs — a horizontal one for
    // x/width and a vertical one for y/height. Keeping the axes separate is what
    // makes a reveal read as a clean straight-down "pull the blind" motion: the
    // width opens first and fast, then the panel drapes down on its own slower
    // curve, instead of sliding in diagonally on a single shared curve.
    private var springResponseH: TimeInterval = 0.30
    private var springDampingH: Double = 0.82
    private var springResponseV: TimeInterval = 0.34
    private var springDampingV: Double = 0.82

    /// Resizes/repositions the window to match the island's current mode.
    /// Width/x spring on the horizontal curve, height/y on the vertical curve;
    /// the top edge stays pinned so growth drapes straight down.
    func animate(to mode: IslandMode) {
        if mode == .expanded {
            makeKeyAndOrderFront(nil)
        } else if isKeyWindow {
            resignKey()
        }

        let notchSize = NotchDetector.idleSize()
        appState.notchSize = notchSize
        let targetSize = mode.size(notchSize: notchSize)
        animTarget = NotchDetector.islandFrame(for: targetSize)
        animStart = frame
        animElapsed = 0

        // The HORIZONTAL axis is always critically damped (damping = 1, no
        // overshoot). If width overshot it would dip narrower than the notch for
        // a frame or two and expose the screen beside the notch — the "gap" ring.
        // The vertical axis may overshoot softly since that only affects the
        // downward drape, which never uncovers the notch.
        switch mode {
        case .hover:
            // A quick, tight bulge with no drape.
            springResponseH = 0.24; springDampingH = 1.0
            springResponseV = 0.24; springDampingV = 1.0
        case .idle, .playing:
            // Snap crisply back in.
            springResponseH = 0.26; springDampingH = 1.0
            springResponseV = 0.26; springDampingV = 1.0
        case .activity:
            springResponseH = 0.28; springDampingH = 1.0
            springResponseV = 0.30; springDampingV = 0.84
        case .peek, .expanded:
            // Width opens fast (critically damped so the sides never uncover the
            // notch); height drapes down slower with a soft iPhone-like settle.
            springResponseH = 0.26; springDampingH = 1.0
            springResponseV = 0.42; springDampingV = 0.80
        }

        // Sample the (fixed-for-this-run) speed multiplier once, up front.
        let speed = SettingsManager.shared.animationSpeed
        animSpeed = speed > 0 ? speed : 1

        // Drive the spring off the display's vsync. Reuse an existing link if a
        // previous animation is still running so we retarget smoothly from the
        // current frame instead of restarting the clock.
        lastTickTimestamp = 0
        if displayLink == nil {
            let link = (contentView ?? self.contentView)?.displayLink(
                target: self,
                selector: #selector(stepAnimation(_:))
            )
            link?.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    /// Repositions the island after display arrangement, mirroring, or hot-plug
    /// changes. The island always follows the built-in notched display.
    func relocateToBuiltInDisplay() {
        guard NotchDetector.builtInNotchScreen != nil else {
            orderOut(nil)
            return
        }
        orderFront(nil)
        animate(to: appState.islandMode)
    }

    /// Evaluates a spring at time `t`, parameterized like SwiftUI's
    /// `.spring(response:dampingFraction:)`. Returns the fraction of the way from
    /// start to target, plus whether the spring has effectively settled.
    private func springValue(_ t: Double, response: TimeInterval, damping: Double) -> (value: CGFloat, settled: Bool) {
        let zeta = damping
        let omega0 = 2 * Double.pi / response                 // natural frequency
        if zeta < 1 {
            // Underdamped: decaying oscillation → gentle overshoot.
            let omegaD = omega0 * (1 - zeta * zeta).squareRoot()  // damped frequency
            let decay = exp(-zeta * omega0 * t)
            let p = 1 - decay * (cos(omegaD * t) + (zeta * omega0 / omegaD) * sin(omegaD * t))
            // Settled once the envelope has decayed to a hair.
            let settled = decay < 0.01 && t > response * 0.5
            return (CGFloat(p), settled)
        } else {
            // Critically damped fallback: no overshoot.
            let decay = exp(-omega0 * t)
            let p = 1 - decay * (1 + omega0 * t)
            return (CGFloat(p), decay < 0.01 && t > response * 0.5)
        }
    }

    /// Driven by the display link at each vsync. Advances the spring by the real
    /// elapsed frame time (not a fixed `1/fps`), so an occasional long frame does
    /// not accumulate error or judder.
    @objc private func stepAnimation(_ link: CADisplayLink) {
        // Real seconds since the previous tick, scaled by the speed multiplier.
        // The first tick of a run has no previous timestamp, so advance by one
        // vsync interval instead of a huge delta.
        let interval = link.targetTimestamp - link.timestamp
        let delta = lastTickTimestamp == 0
            ? interval
            : (link.timestamp - lastTickTimestamp)
        lastTickTimestamp = link.timestamp
        animElapsed += max(0, delta) * animSpeed

        // Horizontal (x/width) and vertical (y/height) advance on independent
        // springs. The top edge is pinned by islandFrame, so height growth reads
        // as a straight downward drape rather than a diagonal slide.
        let (easedH, settledH) = springValue(animElapsed, response: springResponseH, damping: springDampingH)
        let (easedV, settledV) = springValue(animElapsed, response: springResponseV, damping: springDampingV)

        // x/width stay centered on the notch so the panel opens symmetrically to
        // both sides; y/height drape down on the vertical curve.
        let newFrame = NSRect(
            x: animStart.origin.x + (animTarget.origin.x - animStart.origin.x) * easedH,
            y: animStart.origin.y + (animTarget.origin.y - animStart.origin.y) * easedV,
            width: animStart.width + (animTarget.width - animStart.width) * easedH,
            height: animStart.height + (animTarget.height - animStart.height) * easedV
        )
        // display: false — the content view is layer-backed, so Core Animation
        // scales the cached layer on the GPU each frame instead of forcing a
        // synchronous CPU relayout/redraw of the whole SwiftUI tree.
        setFrame(newFrame, display: false)

        let frameError = max(
            abs(newFrame.origin.x - animTarget.origin.x),
            abs(newFrame.origin.y - animTarget.origin.y),
            abs(newFrame.width - animTarget.width),
            abs(newFrame.height - animTarget.height)
        )
        if settledH && settledV && frameError < 0.5 {
            // Land on the exact target with one authoritative layout pass.
            setFrame(animTarget, display: true)
            stopDisplayLink()
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTickTimestamp = 0
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
    private var exitTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)

        // Layer-back the container and only redraw its layer when explicitly
        // invalidated. During the window's per-frame resize animation (which
        // calls setFrame display:false) Core Animation scales the cached layer
        // on the GPU instead of triggering a CPU redraw of the SwiftUI tree.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

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
        exitTask?.cancel()
        exitTask = nil
        appState.mouseEnteredNotch()
    }

    override func mouseExited(with event: NSEvent) {
        exitTask?.cancel()
        exitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled,
                  let self,
                  let window = self.window else { return }
            let mouseInScreen = NSEvent.mouseLocation
            let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
            guard !self.bounds.insetBy(dx: -2, dy: -2).contains(mouseInWindow) else { return }
            self.appState.mouseExitedNotch()
        }
    }
}
