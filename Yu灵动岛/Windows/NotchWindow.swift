import AppKit
import SwiftUI

/// One island window per screen. Following boring.notch's architecture, each
/// window is created at its largest possible extent for that screen and never
/// resizes afterwards. All visual state changes animate inside SwiftUI.
///
/// Per-screen interaction (hover, reveal, notch size) lives in `IslandState`.
/// Shared content (music, lyrics, files, settings) lives in `AppState`.
final class NotchWindow: NSWindow {
    private let island: IslandState
    private let appState: AppState
    private let container: IslandContainerView

    init(island: IslandState, appState: AppState) {
        self.island = island
        self.appState = appState
        self.container = IslandContainerView(island: island, appState: appState)

        let frame = NotchDetector.fixedWindowFrame(for: island.screen)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setupWindow(frame: frame)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func setupWindow(frame: NSRect) {
        // reconcileScreenControllers() calls close() on windows whose screen
        // dropped out (unplug, or turning off show-on-all-displays). NSWindow
        // defaults this to true, which under ARC over-releases a window we still
        // hold — a classic crash. Keep ownership with ARC.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        setFrame(frame, display: true)
        container.frame = contentRect(forFrameRect: self.frame)
        container.autoresizingMask = [.width, .height]
        self.contentView = container
        container.updateMode(island.islandMode)
        orderFront(nil)
    }

    /// Called by the app's single shared mouse monitor on every move. Toggles
    /// click-through and drives hover for THIS window's island. Centralizing the
    /// monitor in AppDelegate keeps it at one system monitor total instead of two
    /// per screen, and avoids leaking monitors when a window closes.
    func handlePointerMove(screenPoint: NSPoint) {
        let over = container.islandContains(screenPoint: screenPoint)
        if ignoresMouseEvents == over {
            ignoresMouseEvents = !over
        }
        container.pointerOverIsland(over)
    }

    /// Called by the island observer on each mode change.
    func animate(to mode: IslandMode) {
        if mode == .expanded {
            makeKeyAndOrderFront(nil)
        } else if isKeyWindow {
            resignKey()
        }
        island.updateNotchSize()
        container.updateMode(mode)
    }

    /// Reposition/resize the window for a potentially new screen geometry.
    /// Call when display parameters change or the target screen moves.
    func relocate() {
        let newFrame = NotchDetector.fixedWindowFrame(for: island.screen)
        if newFrame == .zero {
            orderOut(nil)
        } else {
            setFrame(newFrame, display: true)
            island.updateNotchSize()
            container.updateMode(island.islandMode)
            orderFront(nil)
        }
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class IslandContainerView: NSView {
    private let island: IslandState
    private let appState: AppState
    private var exitTask: Task<Void, Never>?
    private var enterTask: Task<Void, Never>?
    private var mode: IslandMode = .idle
    private var isPointerOver = false

    init(island: IslandState, appState: AppState) {
        self.island = island
        self.appState = appState
        super.init(frame: .zero)

        let hosting = FirstMouseHostingView(
            rootView: IslandView(island: island, appState: appState)
        )
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
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func updateMode(_ mode: IslandMode) { self.mode = mode }

    private func islandRect(for mode: IslandMode) -> NSRect {
        let size = mode.size(notchSize: island.notchSize)
        let x = (bounds.width - size.width) / 2
        let y = bounds.height - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func pointerOverIsland(_ over: Bool) {
        guard over != isPointerOver else { return }
        isPointerOver = over
        if over {
            exitTask?.cancel(); exitTask = nil
            let delay = appState.hoverDelay
            if delay <= 0 {
                island.mouseEnteredNotch()
            } else {
                enterTask?.cancel()
                enterTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self, self.isPointerOver,
                          self.islandContains(screenPoint: NSEvent.mouseLocation) else { return }
                    self.island.mouseEnteredNotch()
                }
            }
        } else {
            enterTask?.cancel(); enterTask = nil
            exitTask?.cancel()
            exitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                guard !self.islandContains(screenPoint: NSEvent.mouseLocation) else { return }
                self.isPointerOver = false
                self.island.mouseExitedNotch()
            }
        }
    }

    func islandContains(screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        let local = convert(inWindow, from: nil)
        return islandRect(for: mode).contains(local)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandRect(for: mode).contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// SwiftUI has no right-click gesture on macOS; unhandled rightMouseDown
    /// bubbles up the responder chain to here. On the hover capsule it toggles
    /// the pin; every other state passes it along untouched.
    override func rightMouseDown(with event: NSEvent) {
        switch island.revealState {
        case .activity, .hover:
            island.togglePinned()
        default:
            super.rightMouseDown(with: event)
        }
    }
}
