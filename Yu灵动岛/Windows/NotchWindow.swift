import AppKit
import SwiftUI

/// The one and only island window. Following boring.notch's architecture, the
/// window is created ONCE at the largest extent any state can reach and never
/// resizes afterwards (except when the target display changes). Every visual
/// state change — idle / playing / hover / peek / expanded — happens INSIDE
/// SwiftUI via `.frame` + spring animation, which Core Animation composites on
/// the GPU. No per-frame `setFrame`, so there is no window-server churn, no
/// drift/judder, and no diagonal "gap" as edges chase a moving window.
///
/// Because the window is large and mostly transparent, hit-testing and hover
/// tracking are driven by the CURRENT island geometry (`islandRect(for:)`), not
/// the window bounds: clicks on the transparent margin pass straight through to
/// whatever is behind, and hover only fires over the actual island.
final class NotchWindow: NSWindow {
    private let appState: AppState
    private let container: IslandContainerView

    init(appState: AppState) {
        self.appState = appState
        self.container = IslandContainerView(appState: appState)

        super.init(
            contentRect: NotchDetector.fixedWindowFrame(),
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

    /// Monitors the cursor so the (large, transparent) window only intercepts
    /// mouse events while the pointer is actually over the island. Everywhere
    /// else the window is click-through so the menu bar and other apps behind
    /// the transparent margin stay usable.
    private var mouseMonitor: Any?

    private func setupWindow() {
        isOpaque = false
        backgroundColor = .clear
        // The window is fixed and large; a native window shadow would frame the
        // whole rectangle rather than the island. The shadow is drawn inside
        // SwiftUI (on the shaped panel) so it tracks the animated shape.
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        isMovableByWindowBackground = false
        // Start click-through; the mouse monitor flips this on only while the
        // cursor is over the island. A view-level hitTest returning nil is NOT
        // enough — it doesn't forward the click to the menu bar / window behind;
        // only ignoresMouseEvents actually lets the click pass through.
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        setFrame(NotchDetector.fixedWindowFrame(), display: true)
        container.frame = contentRect(forFrameRect: frame)
        container.autoresizingMask = [.width, .height]
        self.contentView = container

        // Seed the initial hit/hover geometry.
        container.updateMode(appState.islandMode)

        installMouseMonitor()
        orderFront(nil)
    }

    /// Global + local mouse-moved monitor. This single monitor does two jobs:
    ///   1. Toggles `ignoresMouseEvents` so the (large, transparent) window only
    ///      intercepts clicks while the cursor is over the island; everywhere else
    ///      it is click-through so the menu bar / other apps stay usable.
    ///   2. Drives hover enter/exit DIRECTLY. We can't use an NSTrackingArea for
    ///      this: the window starts click-through, and by the time the monitor
    ///      flips it interactive the cursor is already inside the rect, so no
    ///      boundary is crossed and `mouseEntered` never fires. Computing hover
    ///      from the cursor position here is reliable regardless of that toggle.
    private func installMouseMonitor() {
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            let over = self.container.islandContains(screenPoint: NSEvent.mouseLocation)
            if self.ignoresMouseEvents == over {
                self.ignoresMouseEvents = !over
            }
            self.container.pointerOverIsland(over)
        }
        // Local (events already routed to this app) + global (other apps focused).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in update() }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in update(); return event }
    }

    /// Called by the island observer whenever the visual mode changes. The
    /// SwiftUI content animates itself (it observes `appState`); here we only
    /// keep the window's key state and the hit/hover geometry in sync with the
    /// new mode. No window resize.
    func animate(to mode: IslandMode) {
        if mode == .expanded {
            makeKeyAndOrderFront(nil)
        } else if isKeyWindow {
            resignKey()
        }
        appState.notchSize = NotchDetector.idleSize()
        container.updateMode(mode)
    }

    /// Repositions the island after display arrangement, mirroring, or hot-plug
    /// changes. The island always follows the built-in notched display. This is
    /// the ONLY path that moves the window.
    func relocateToBuiltInDisplay() {
        guard NotchDetector.builtInNotchScreen != nil else {
            orderOut(nil)
            return
        }
        setFrame(NotchDetector.fixedWindowFrame(), display: true)
        appState.notchSize = NotchDetector.idleSize()
        container.updateMode(appState.islandMode)
        orderFront(nil)
    }
}

/// An NSHostingView that delivers the first click even when the window isn't
/// key, so a tap on the island advances the reveal immediately rather than just
/// activating the window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts the SwiftUI island inside the fixed-size window. Owns:
///   • geometry-based hit-testing — only the current island rect is clickable,
///     so the transparent margin passes clicks through to windows behind it;
///   • a tracking area matching the current island rect — hover enter/exit fire
///     only over the actual island, not the whole (large) window.
private final class IslandContainerView: NSView {
    private let appState: AppState
    private var exitTask: Task<Void, Never>?
    /// The visual mode whose geometry currently defines the clickable/hover rect.
    private var mode: IslandMode = .idle
    /// Whether the cursor is currently considered over the island, so we only
    /// fire enter/exit on transitions (the monitor calls us on every move).
    private var isPointerOver = false

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

    /// Update the geometry that defines the clickable/hover region. Called by the
    /// window on every mode change.
    func updateMode(_ mode: IslandMode) {
        self.mode = mode
    }

    /// The island's rect in this view's (non-flipped, bottom-left origin)
    /// coordinates: horizontally centered, pinned to the top edge (the window top
    /// is flush with the screen top), sized to the current mode.
    private func islandRect(for mode: IslandMode) -> NSRect {
        let size = mode.size(notchSize: appState.notchSize)
        let x = (bounds.width - size.width) / 2
        let y = bounds.height - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Called by the window's mouse monitor on every move event. Fires
    /// enter/exit only on transitions so `mouseEnteredNotch` / `mouseExitedNotch`
    /// are called exactly once per crossing — not on every mouse-moved event.
    /// This replaces NSTrackingArea, which misses entries when the window is
    /// click-through and the cursor is already inside the rect.
    func pointerOverIsland(_ over: Bool) {
        guard over != isPointerOver else { return }
        isPointerOver = over
        if over {
            exitTask?.cancel()
            exitTask = nil
            appState.mouseEnteredNotch()
        } else {
            exitTask?.cancel()
            exitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                let still = self.islandContains(screenPoint: NSEvent.mouseLocation)
                guard !still else { return }
                self.isPointerOver = false
                self.appState.mouseExitedNotch()
            }
        }
    }

    func islandContains(screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        let local = convert(inWindow, from: nil)
        return islandRect(for: mode).contains(local)
    }

    // Only the island area is interactive; transparent margin passes clicks through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandRect(for: mode).contains(local) else { return nil }
        return super.hitTest(point)
    }
}
