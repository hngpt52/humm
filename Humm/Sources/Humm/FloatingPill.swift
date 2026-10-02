import AppKit
import QuartzCore

enum PillMetrics {
    /// The panel holds the pill and its caption: above or below a pill lying along the top or
    /// bottom edge, beside one standing on a side edge.
    static let lyingPanel = NSSize(width: 400, height: 104)
    static let standingPanel = NSSize(width: 420, height: 150)
    /// Minimum gap between the pill and the panel edge (room for its shadow).
    static let inset: CGFloat = 8
    /// Sizes along the rail (length) and across it (thickness), all even so edges land on whole
    /// pixels: a wave at rest, a pill for a status icon, a little bigger under the pointer and
    /// while transcribing, long enough for the live meter while recording.
    static let restLength: CGFloat = 52
    static let restThickness: CGFloat = 16
    /// At rest the pill itself is a wave: a band this wide, one and a half waves long.
    static let waveBand: CGFloat = 8
    static let waveAmplitude: CGFloat = 3.5
    static let wavePeriods: CGFloat = 1.5
    static let badgeLength: CGFloat = 60
    static let badgeThickness: CGFloat = 28
    static let activeLength: CGFloat = 68
    static let activeThickness: CGFloat = 32
    static let recordingLength: CGFloat = 124
    static let thickness: CGFloat = 34
    /// Distance between the pill and the screen edge it runs along.
    static let railGap: CGFloat = 12
    static let captionHeight: CGFloat = 26
    static let captionGap: CGFloat = 10
    /// Accent colour. The pill is monochrome: white on near-black.
    static let accent = NSColor.white
}

private enum Rail: String {
    case bottom, right, top, left
}

/// The loop the pill runs along on one screen: all four edges of the visible area.
/// Values are screen coordinates of the pill's centre unless stated otherwise.
private struct Rails {
    static let cornerRadius: CGFloat = 28

    let visible: NSRect

    /// The pill's centre line runs this far in from each edge.
    private var lineInset: CGFloat { PillMetrics.railGap + PillMetrics.thickness / 2 }

    var bottomY: CGFloat { visible.minY + lineInset }
    var topY: CGFloat { visible.maxY - lineInset }
    var leftX: CGFloat { visible.minX + lineInset }
    var rightX: CGFloat { visible.maxX - lineInset }

    /// Along each edge, leave room at the ends for the pill to lengthen while recording.
    var horizontal: ClosedRange<CGFloat> { Self.span(visible.minX, visible.maxX) }
    var vertical: ClosedRange<CGFloat> { Self.span(visible.minY, visible.maxY) }

    private static func span(_ low: CGFloat, _ high: CGFloat) -> ClosedRange<CGFloat> {
        let reach = PillMetrics.railGap + PillMetrics.recordingLength / 2
        return (low + reach)...max(low + reach, high - reach)
    }

    func centre(on rail: Rail, at fraction: CGFloat) -> NSPoint {
        switch rail {
        case .bottom: NSPoint(x: Self.lerp(horizontal, fraction), y: bottomY)
        case .top: NSPoint(x: Self.lerp(horizontal, fraction), y: topY)
        case .left: NSPoint(x: leftX, y: Self.lerp(vertical, fraction))
        case .right: NSPoint(x: rightX, y: Self.lerp(vertical, fraction))
        }
    }

    /// The rail position nearest to a desired pill centre.
    func nearest(to point: NSPoint) -> (rail: Rail, fraction: CGFloat) {
        let x = Self.clamp(point.x, horizontal)
        let y = Self.clamp(point.y, vertical)
        let candidates: [(rail: Rail, at: NSPoint, fraction: CGFloat)] = [
            (.bottom, NSPoint(x: x, y: bottomY), Self.fraction(x, in: horizontal)),
            (.top, NSPoint(x: x, y: topY), Self.fraction(x, in: horizontal)),
            (.left, NSPoint(x: leftX, y: y), Self.fraction(y, in: vertical)),
            (.right, NSPoint(x: rightX, y: y), Self.fraction(y, in: vertical)),
        ]
        let best = candidates.min { a, b in
            hypot(point.x - a.at.x, point.y - a.at.y) < hypot(point.x - b.at.x, point.y - b.at.y)
        }!
        return (best.rail, best.fraction)
    }

    // MARK: Guide loop

    private var loop: CGRect { CGRect(x: leftX, y: bottomY, width: rightX - leftX, height: topY - bottomY) }
    private var radius: CGFloat { min(Self.cornerRadius, loop.width / 2, loop.height / 2) }

    /// Rounded rectangle through the rail centre lines: along the bottom from the left,
    /// up the right side, back along the top, down the left side.
    var loopPath: CGPath {
        let rect = loop
        let r = radius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }

    private var straightWidth: CGFloat { loop.width - 2 * radius }
    private var straightHeight: CGFloat { loop.height - 2 * radius }
    private var cornerLength: CGFloat { .pi * radius / 2 }

    var loopLength: CGFloat { 2 * straightWidth + 2 * straightHeight + 4 * cornerLength }

    /// How far along the loop a pill position is, as a fraction of its length.
    func loopFraction(of rail: Rail, at fraction: CGFloat) -> CGFloat {
        let rect = loop
        let r = radius
        let point = centre(on: rail, at: fraction)
        let distance: CGFloat = switch rail {
        case .bottom: point.x - (rect.minX + r)
        case .right: straightWidth + cornerLength + (point.y - (rect.minY + r))
        case .top: straightWidth + straightHeight + 2 * cornerLength + ((rect.maxX - r) - point.x)
        case .left: 2 * straightWidth + straightHeight + 3 * cornerLength + ((rect.maxY - r) - point.y)
        }
        return loopLength > 0 ? distance / loopLength : 0
    }

    private static func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func lerp(_ range: ClosedRange<CGFloat>, _ fraction: CGFloat) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(max(fraction, 0), 1)
    }

    private static func fraction(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0.5
    }
}

/// Always-on-top dictation pill that lives on a loop round the screen edges. The panel never
/// takes focus, so the transcript pastes into the app you were working in. Click to toggle;
/// drag to slide it round the loop (a guide appears while dragging); the spot is remembered.
@MainActor
final class FloatingPill {
    private struct Placement {
        var screenID: UInt32
        var rail: Rail
        var fraction: CGFloat
    }

    nonisolated private static let placementKey = "pillPlacement"
    /// Half the length of the glowing stretch of track around the pill, in points.
    private static let highlightReach: CGFloat = 70

    private let panel: NSPanel
    private let view: PillView
    private let state: AppState
    private let guides = RailGuides()
    private let card = PillCard()
    private var placement: Placement
    private var grabOffset = NSPoint.zero
    private var levelTimer: Timer?
    private var isDragging = false
    private var pointerMonitor: Any?
    /// The display the pointer moved to, while waiting to see that it stays there.
    private var pendingScreenID: UInt32?
    /// Developer previews put the pill on a chosen display, so there it stays.
    private let mayFollowPointer = !CommandLine.arguments.contains { $0.hasPrefix("--preview") }

    init(state: AppState) {
        self.state = state
        let frame = NSRect(origin: .zero, size: PillMetrics.lyingPanel)
        view = PillView(frame: frame)
        panel = NonActivatingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = view
        placement = Self.savedPlacement() ?? Self.homePlacement

        view.onClick = { [weak state] in
            Log.input.notice("pill click")
            state?.toggle()
        }
        view.onDragBegan = { [weak self] mouse in self?.dragBegan(at: mouse) }
        view.onDragMoved = { [weak self] mouse in self?.dragMoved(to: mouse) }
        view.onDragEnded = { [weak self] in self?.dragEnded() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPlacement() }
        }
        // Mouse movement in other apps; no permission needed.
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
        if let screen = screenToFollow() { placement.screenID = Self.id(of: screen) }  // start where the pointer is
        applyPlacement()
        refresh()
    }

    func refresh() {
        view.idleHint = state.keyboardShortcuts ? "Hold ⌃ Ctrl + ⌥ Opt  ·  + Space for hands-free" : "Click to dictate"
        view.handsFree = state.isHandsFree
        view.render(state.phase)
        if state.phase == .recording { startLevelTimer() } else { stopLevelTimer() }
        if state.showFloatingButton {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        placeCard()
        followPointer()  // e.g. just switched on, or the pointer moved while no event came
    }

    /// A card sits beside the pill, on the inward side: the transcript to copy when it had nowhere
    /// to go, otherwise a word just learned.
    private func placeCard() {
        let content: PillCard.Content
        if let text = state.transcriptToCopy {
            content = PillCard.Content(heading: "No text box selected", body: text, detail: nil,
                                       action: state.transcriptCopied ? "Copied" : "Copy",
                                       actionSymbol: state.transcriptCopied ? "checkmark" : "doc.on.doc")
            card.onAction = { [weak state] in state?.copyTranscript() }
            card.onClose = { [weak state] in state?.closeTranscript() }
        } else if let failed = state.failedRecording, state.phase != .recording, state.phase != .transcribing {
            content = PillCard.Content(heading: "Couldn't transcribe", body: failed.reason,
                                       detail: "Your \(CostTracker.duration(failed.duration)) recording is kept, so nothing is lost.",
                                       action: "Try Again", actionSymbol: "arrow.clockwise")
            card.onAction = { [weak state] in state?.retryFailedRecording() }
            card.onClose = { [weak state] in state?.discardFailedRecording() }
        } else if let notice = state.learnedNotice {
            content = PillCard.Content(heading: "Added to your dictionary", body: notice.words.joined(separator: ", "),
                                       detail: notice.detail, action: "Undo", actionSymbol: "arrow.uturn.backward")
            card.onAction = { [weak state] in state?.undoLearned() }
            card.onClose = { [weak state] in state?.closeLearned() }
        } else {
            view.cardShowing = false
            card.hide()
            return
        }
        view.cardShowing = true
        let size = card.prepare(content)
        let visible = currentScreen.visibleFrame
        let centre = NSPoint(x: panel.frame.minX + view.pillCentre.x, y: panel.frame.minY + view.pillCentre.y)
        let reach = PillMetrics.thickness / 2 + PillMetrics.captionGap
        var origin: NSPoint = switch placement.rail {
        case .bottom: NSPoint(x: centre.x - size.width / 2, y: centre.y + reach)
        case .top: NSPoint(x: centre.x - size.width / 2, y: centre.y - reach - size.height)
        case .left: NSPoint(x: centre.x + reach, y: centre.y - size.height / 2)
        case .right: NSPoint(x: centre.x - reach - size.width, y: centre.y - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8).rounded()
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8).rounded()
        card.show(at: origin)
    }

    /// Bottom centre of the main screen (the one with the menu bar): where the pill starts, and
    /// where Reset Pill Position brings it back to, e.g. when it is lost on another display.
    private static var homePlacement: Placement {
        Placement(screenID: id(of: NSScreen.screens.first), rail: .bottom, fraction: 0.5)
    }

    func resetPlacement() {
        placement = Self.homePlacement
        UserDefaults.standard.removeObject(forKey: Self.placementKey)
        applyPlacement()
        refresh()
        Log.input.notice("pill placement reset")
    }

    /// Developer preview: `--preview-rail bottom|right|top|left` puts the pill on that edge
    /// (not saved) and keeps the guide showing, for checking the look. `--preview-screen <n>`
    /// picks the display (1 is the main one).
    func previewRail(_ name: String, screen: Int?) {
        guard let rail = Rail(rawValue: name) else { return }
        let screens = NSScreen.screens
        let screenID = screen.flatMap { screens.indices.contains($0 - 1) ? Self.id(of: screens[$0 - 1]) : nil }
        placement = Placement(screenID: screenID ?? placement.screenID, rail: rail, fraction: 0.35)
        if CommandLine.arguments.contains("--preview-hover") { view.previewHover() }
        applyPlacement()
        showGuides(on: currentScreen)
    }

    // MARK: Level meter

    private func startLevelTimer() {
        guard levelTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.view.setLevel(self.state.inputLevel)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: Placement

    private var currentScreen: NSScreen {
        Self.screen(withID: placement.screenID) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func applyPlacement() {
        let visible = currentScreen.visibleFrame
        let centre = Rails(visible: visible).centre(on: placement.rail, at: placement.fraction)
        let standing = placement.rail == .left || placement.rail == .right
        let size = standing ? PillMetrics.standingPanel : PillMetrics.lyingPanel
        // The pill sits against the panel edge nearest the screen edge; its caption goes inwards.
        let reach = PillMetrics.thickness / 2 + PillMetrics.inset
        var origin: NSPoint = switch placement.rail {
        case .bottom: NSPoint(x: centre.x - size.width / 2, y: centre.y - reach)
        case .top: NSPoint(x: centre.x - size.width / 2, y: centre.y + reach - size.height)
        case .left: NSPoint(x: centre.x - reach, y: centre.y - size.height / 2)
        case .right: NSPoint(x: centre.x + reach - size.width, y: centre.y - size.height / 2)
        }
        // The panel always stays on screen.
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width).rounded()
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height).rounded()
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        view.anchor = PillView.Anchor(centre: NSPoint(x: centre.x - origin.x, y: centre.y - origin.y), edge: placement.rail)
        if view.cardShowing { placeCard() }  // any card follows the pill
    }

    // MARK: Following the pointer

    /// The display the pointer is on, when the pill should follow it there.
    private func screenToFollow() -> NSScreen? {
        guard mayFollowPointer, state.pillFollowsMouse, state.showFloatingButton, !isDragging, NSScreen.screens.count > 1 else { return nil }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    /// Once the pointer has stayed on another display for a moment (not just passed through a
    /// corner of it), the pill moves there, keeping its edge and its place along it. The saved
    /// placement is left alone: it is where the user put the pill, the display aside.
    private func followPointer() {
        guard let screen = screenToFollow() else { return }
        let target = Self.id(of: screen)
        guard target != placement.screenID else {
            pendingScreenID = nil
            return
        }
        guard pendingScreenID != target else { return }
        pendingScreenID = target
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.pendingScreenID == target else { return }
            self.pendingScreenID = nil
            guard let screen = self.screenToFollow(), Self.id(of: screen) == target else { return }
            self.placement.screenID = target
            Log.input.notice("pill followed the pointer to display \(target, privacy: .public)")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.applyPlacement()
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.15
                        self.panel.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    private func dragBegan(at mouse: NSPoint) {
        isDragging = true
        let centre = NSPoint(x: panel.frame.minX + view.pillCentre.x, y: panel.frame.minY + view.pillCentre.y)
        grabOffset = NSPoint(x: mouse.x - centre.x, y: mouse.y - centre.y)
        showGuides(on: currentScreen)
    }

    private func dragMoved(to mouse: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? currentScreen
        let rails = Rails(visible: screen.visibleFrame)
        let nearest = rails.nearest(to: NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
        let screenID = Self.id(of: screen)
        let changedScreen = screenID != placement.screenID
        placement = Placement(screenID: screenID, rail: nearest.rail, fraction: nearest.fraction)
        if changedScreen { showGuides(on: screen) }
        applyPlacement()
        highlightGuide(rails)
    }

    private func dragEnded() {
        isDragging = false
        guides.hide()
        UserDefaults.standard.set("\(placement.screenID)|\(placement.rail.rawValue)|\(placement.fraction)",
                                  forKey: Self.placementKey)
        Log.input.notice("pill placed on \(self.placement.rail.rawValue, privacy: .public) rail")
    }

    private func showGuides(on screen: NSScreen) {
        let rails = Rails(visible: screen.visibleFrame)
        guides.show(on: screen, path: rails.loopPath)
        highlightGuide(rails)
        panel.orderFrontRegardless()
    }

    private func highlightGuide(_ rails: Rails) {
        guard rails.loopLength > 0 else { return }
        guides.highlight(at: rails.loopFraction(of: placement.rail, at: placement.fraction),
                         reach: Self.highlightReach / rails.loopLength)
    }

    private static func savedPlacement() -> Placement? {
        let parts = UserDefaults.standard.string(forKey: placementKey)?.split(separator: "|") ?? []
        guard parts.count == 3, let id = UInt32(parts[0]), let rail = Rail(rawValue: String(parts[1])),
              let fraction = Double(parts[2]) else { return nil }
        return Placement(screenID: id, rail: rail, fraction: CGFloat(fraction))
    }

    private static func id(of screen: NSScreen?) -> UInt32 {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private static func screen(withID id: UInt32) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id }
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The track shown while dragging: a soft groove with a dotted line round the screen, and a
/// glow on the stretch where the pill is.
@MainActor
private final class RailGuides {
    private let panel: NSPanel
    private let groove = CAShapeLayer()
    private let dots = CAShapeLayer()
    private let glow = CAShapeLayer()
    private var showing = false

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0
        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content

        groove.fillColor = nil
        groove.strokeColor = NSColor(white: 0, alpha: 0.3).cgColor
        groove.lineWidth = 14
        groove.lineJoin = .round

        dots.fillColor = nil
        dots.strokeColor = NSColor(white: 1, alpha: 0.6).cgColor
        dots.lineWidth = 3
        dots.lineCap = .round
        dots.lineDashPattern = [0, 9]  // zero-length dashes with round caps draw dots

        glow.fillColor = nil
        glow.strokeColor = PillMetrics.accent.cgColor
        glow.lineWidth = 4
        glow.lineCap = .round
        glow.shadowColor = PillMetrics.accent.cgColor
        glow.shadowRadius = 8
        glow.shadowOpacity = 1
        glow.shadowOffset = .zero

        [groove, dots, glow].forEach { content.layer?.addSublayer($0) }
    }

    func show(on screen: NSScreen, path: CGPath) {
        let frame = screen.visibleFrame
        panel.setFrame(frame, display: false)
        var toPanel = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
        let local = path.copy(using: &toPanel)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [groove, dots, glow] {
            layer.frame = CGRect(origin: .zero, size: frame.size)
            layer.contentsScale = screen.backingScaleFactor
            layer.path = local
        }
        CATransaction.commit()
        showing = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.panel.animator().alphaValue = 1
        }
    }

    /// Glow the track from `at - reach` to `at + reach` (fractions of the loop length).
    func highlight(at position: CGFloat, reach: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.strokeStart = max(0, position - reach)
        glow.strokeEnd = min(1, position + reach)
        CATransaction.commit()
    }

    func hide() {
        showing = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.showing else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// Draws the pill with layers and handles its own mouse events (AppKit delivers them to
/// a non-key window when acceptsFirstMouse is true).
private final class PillView: NSView {
    struct Anchor: Equatable {
        /// The pill's centre, in view coordinates.
        var centre: NSPoint
        /// The screen edge the pill runs along. It lies along the top and bottom and stands up on
        /// the sides, with its caption on the inward side.
        var edge: Rail

        var standing: Bool { edge == .left || edge == .right }
    }

    var onClick: () -> Void = {}
    var onDragBegan: (NSPoint) -> Void = { _ in }
    var onDragMoved: (NSPoint) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    var anchor = Anchor(centre: NSPoint(x: PillMetrics.lyingPanel.width / 2, y: PillMetrics.inset + PillMetrics.thickness / 2),
                        edge: .bottom) {
        didSet {
            guard anchor != oldValue else { return }
            if anchor.standing != oldValue.standing { barMotion = nil }  // restart any motion on the new axis
            layoutPill(animated: false)
            updateBarMotion()
            updateCaption()
        }
    }

    var pillCentre: NSPoint { capsule.position }

    /// Developer preview (`--preview-hover`): shows the pointed-at look without the pointer.
    func previewHover() {
        hovering = true
        layoutPill(animated: false)
        updateBarMotion()
        updateCaption()
    }

    /// Hover caption while idle.
    var idleHint = "Click to dictate"
    /// The copy card is up beside the pill; it says enough, so no hover caption.
    var cardShowing = false {
        didSet { if cardShowing != oldValue { updateCaption() } }
    }
    /// Recording carries on until finished; the caption says how to finish.
    var handsFree = false

    /// Nine bars make Humm's sound wave. Under the pointer the middle five stand in the app icon's
    /// shape, the centre one glowing, and ripple; a wave runs through them while transcribing, and
    /// all nine follow the microphone while recording.
    private static let barWeights: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1, 0.9, 0.75, 0.55, 0.35]
    /// Bar lengths across the pill. Even lengths and whole-point spacing keep the bars sharp on
    /// 1x displays.
    private static let restingLengths: [CGFloat] = [0, 0, 6, 12, 16, 12, 6, 0, 0]
    private static let centreBar = 4
    private static let barThickness: CGFloat = 3
    private static let barPitch: CGFloat = 6
    private static let barMinLength: CGFloat = 4
    private static let barMaxLength: CGFloat = 22
    private static let waitingLength: CGFloat = 10

    private let capsule = CALayer()
    private let statusIcon = CALayer()
    private let recordingDot = CALayer()
    private let stopSquare = CALayer()
    private let bars = PillView.barWeights.map { _ in CALayer() }
    /// The pill at rest: a band shaped as a wave, drawn as two round-capped strokes of the same
    /// curve (the outline, then the fill 2 pt narrower), so it never tears at the bends.
    private let restOutline = CAShapeLayer()
    private let restFill = CAShapeLayer()
    private let captionBox = NSView()
    private let caption = NSTextField(labelWithString: "")

    private var phase: AppState.Phase = .idle
    private var hovering = false
    private var barMotion: BarMotion?
    private var smoothedLevel: CGFloat = 0
    private var downLocation: NSPoint?
    private var dragging = false
    private var hoverArea: NSTrackingArea?
    private var hoverRect = NSRect.zero
    private var hoverCheck: Timer?

    private enum BarMotion { case ripple, wave }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(capsule)
        capsule.borderWidth = 1
        capsule.shadowColor = NSColor.black.cgColor
        capsule.shadowOpacity = 0.35
        capsule.shadowRadius = 6
        capsule.shadowOffset = CGSize(width: 0, height: -2)

        statusIcon.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        statusIcon.contentsGravity = .center
        recordingDot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        recordingDot.cornerRadius = 4
        recordingDot.backgroundColor = NSColor.systemRed.cgColor
        stopSquare.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        stopSquare.cornerRadius = 2.5
        stopSquare.backgroundColor = NSColor.white.cgColor
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barThickness, height: Self.barMinLength)
            bar.cornerRadius = Self.barThickness / 2
            bar.backgroundColor = (index == Self.centreBar ? PillMetrics.accent : NSColor(white: 1, alpha: 0.96)).cgColor
        }
        // The accent bar glows, as in the app icon.
        bars[Self.centreBar].shadowColor = PillMetrics.accent.cgColor
        bars[Self.centreBar].shadowRadius = 3
        bars[Self.centreBar].shadowOpacity = 0.7
        bars[Self.centreBar].shadowOffset = .zero
        for (layer, width) in [(restOutline, PillMetrics.waveBand), (restFill, PillMetrics.waveBand - 2)] {
            layer.fillColor = nil
            layer.lineWidth = width
            layer.lineCap = .round
            layer.lineJoin = .round
        }
        restOutline.strokeColor = PillMetrics.accent.withAlphaComponent(0.85).cgColor
        restFill.strokeColor = NSColor(white: 0.08, alpha: 0.92).cgColor
        ([statusIcon, recordingDot, stopSquare, restOutline, restFill] + bars).forEach { capsule.addSublayer($0) }

        captionBox.wantsLayer = true
        captionBox.layer?.cornerRadius = PillMetrics.captionHeight / 2
        captionBox.layer?.backgroundColor = NSColor(white: 0, alpha: 0.85).cgColor
        captionBox.alphaValue = 0
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.textColor = .white
        caption.lineBreakMode = .byTruncatingTail
        captionBox.addSubview(caption)
        addSubview(captionBox)

        updateScale()
        layoutPill(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Rendering

    func render(_ phase: AppState.Phase) {
        let previous = self.phase
        self.phase = phase
        updateIcons()
        layoutPill(animated: true)

        if phase == .recording, previous != .recording {
            smoothedLevel = 0
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.3
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            recordingDot.add(pulse, forKey: "pulse")
        } else if phase != .recording {
            recordingDot.removeAnimation(forKey: "pulse")
        }
        updateBarMotion()
        updateCaption()
    }

    /// Live microphone level (0...1) while recording.
    func setLevel(_ level: Float) {
        guard phase == .recording else { return }
        smoothedLevel = max(CGFloat(level), smoothedLevel * 0.8)  // quick attack, gentle release
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        for (index, bar) in bars.enumerated() {
            let jitter = CGFloat.random(in: 0.65...1)
            let length = Self.barMinLength + (Self.barMaxLength - Self.barMinLength) * smoothedLevel * Self.barWeights[index] * jitter
            bar.bounds = barBounds(length)
        }
        CATransaction.commit()
    }

    /// Length along the rail and thickness across it, in the current state.
    private var extent: (length: CGFloat, thickness: CGFloat) {
        switch phase {
        case .recording: (PillMetrics.recordingLength, PillMetrics.thickness)
        case .transcribing: (PillMetrics.activeLength, PillMetrics.activeThickness)
        case .idle where hovering && !dragging: (PillMetrics.activeLength, PillMetrics.activeThickness)
        case .idle: (PillMetrics.restLength, PillMetrics.restThickness)
        default: (PillMetrics.badgeLength, PillMetrics.badgeThickness)
        }
    }

    /// Not in use: idle and not under the pointer. The pill becomes a wave, and grows back into
    /// a pill of bars when pointed at.
    private var resting: Bool { phase == .idle && (!hovering || dragging) }

    /// The centre line of the resting wave, filling the rest size (the round caps reach the ends).
    private func restWavePath(standing: Bool) -> CGPath {
        let path = CGMutablePath()
        let length = PillMetrics.restLength, middle = PillMetrics.restThickness / 2
        let inset = PillMetrics.waveBand / 2
        for step in 0...120 {
            let t = CGFloat(step) / 120
            let along = inset + (length - 2 * inset) * t
            let across = middle + PillMetrics.waveAmplitude * sin(2 * .pi * PillMetrics.wavePeriods * t)
            let point = standing ? CGPoint(x: across, y: length - along) : CGPoint(x: along, y: across)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }

    /// A bar of the given length, lying across the pill.
    private func barBounds(_ length: CGFloat) -> CGRect {
        anchor.standing ? CGRect(x: 0, y: 0, width: length, height: Self.barThickness)
            : CGRect(x: 0, y: 0, width: Self.barThickness, height: length)
    }

    private var fillColour: NSColor {
        if phase == .done { return NSColor.systemGreen.withAlphaComponent(0.95) }
        if resting { return .clear }  // the wave is the pill
        return NSColor(white: hovering ? 0.22 : 0.12, alpha: 0.96)
    }

    private var borderColour: NSColor {
        if resting { return .clear }
        return switch phase {
        case .recording: NSColor.systemRed.withAlphaComponent(0.6)
        case .error: NSColor.systemOrange.withAlphaComponent(0.7)
        default: NSColor(white: 1, alpha: 0.24)  // visible on dark wallpaper
        }
    }

    private func layoutPill(animated: Bool) {
        let (length, thickness) = extent
        let standing = anchor.standing
        let size = standing ? CGSize(width: thickness, height: length) : CGSize(width: length, height: thickness)
        /// A point on the pill's centre line, `along` from its start: the left end, or the top end
        /// of a standing pill.
        func point(_ along: CGFloat) -> CGPoint {
            standing ? CGPoint(x: size.width / 2, y: size.height - along) : CGPoint(x: along, y: size.height / 2)
        }
        let recording = phase == .recording
        let showsWave = (phase == .idle && !resting) || phase == .transcribing
        let showsStatus: Bool = switch phase {
        case .done, .notice, .error, .learned, .copied: true
        default: false
        }

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.28)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        capsule.bounds = CGRect(origin: .zero, size: size)
        capsule.cornerRadius = thickness / 2
        // Centred on its rail line whatever its size; whole points, so edges land on pixels.
        capsule.position = CGPoint(x: anchor.centre.x.rounded(), y: anchor.centre.y.rounded())
        capsule.backgroundColor = fillColour.cgColor
        capsule.borderColor = borderColour.cgColor

        statusIcon.position = CGPoint(x: size.width / 2, y: size.height / 2)  // icons stay upright
        statusIcon.opacity = showsStatus ? 1 : 0

        let wavePath = restWavePath(standing: standing)
        for layer in [restOutline, restFill] {
            layer.bounds = standing
                ? CGRect(x: 0, y: 0, width: PillMetrics.restThickness, height: PillMetrics.restLength)
                : CGRect(x: 0, y: 0, width: PillMetrics.restLength, height: PillMetrics.restThickness)
            layer.position = CGPoint(x: size.width / 2, y: size.height / 2)
            layer.path = wavePath
            layer.opacity = resting ? 1 : 0
        }

        recordingDot.position = point(16)
        recordingDot.opacity = recording ? 1 : 0
        stopSquare.position = point(length - 17)
        stopSquare.opacity = recording ? 1 : 0

        // Centred, or between the dot and the stop square while recording, where the level meter
        // sets the lengths. The odd-thickness bars sit on half points to stay sharp.
        let middle = (recording ? (28 + length - 30) / 2 : length / 2).rounded(.down) + 0.5
        for (index, bar) in bars.enumerated() {
            bar.position = point(middle + CGFloat(index - Self.centreBar) * Self.barPitch)
            let resting = Self.restingLengths[index]
            guard !recording else {
                bar.opacity = 1
                continue
            }
            bar.opacity = showsWave && resting > 0 ? 1 : 0
            bar.bounds = barBounds(phase == .transcribing && resting > 0 ? Self.waitingLength : max(resting, Self.barMinLength))
        }
        CATransaction.commit()
        updateHoverArea()
    }

    /// A gentle ripple under the pointer, a wave running across while transcribing.
    private func updateBarMotion() {
        let motion: BarMotion? = switch phase {
        case .transcribing: .wave
        case .idle where hovering && !dragging: .ripple
        default: nil
        }
        guard motion != barMotion else { return }
        barMotion = motion
        bars.forEach { $0.removeAnimation(forKey: "motion") }
        guard let motion else { return }
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() where Self.restingLengths[index] > 0 {
            let animation = CAKeyframeAnimation(keyPath: anchor.standing ? "transform.scale.x" : "transform.scale.y")
            switch motion {
            case .ripple:
                animation.values = [1, 1.35, 0.8, 1]
                animation.duration = 1.4
            case .wave:
                animation.values = [0.5, 1.7, 0.5]
                animation.duration = 0.9
            }
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.repeatCount = .infinity
            animation.beginTime = bar.convertTime(now, from: nil) + Double(index) * 0.11
            animation.fillMode = .backwards
            bar.add(animation, forKey: "motion")
        }
    }

    private func updateIcons() {
        let scale = window?.backingScaleFactor ?? 2
        let status: NSImage? = switch phase {
        case .done: Self.symbol("checkmark", size: 14, weight: .bold)
        case .notice: Self.symbol("doc.on.clipboard", size: 12)
        case .error: Self.symbol("exclamationmark", size: 14, weight: .bold, colour: .systemOrange)
        case .learned: Self.symbol("character.book.closed", size: 13, colour: PillMetrics.accent)
        case .copied: Self.symbol("doc.on.doc", size: 12)
        default: nil
        }
        if let status { setImage(status, on: statusIcon, scale: scale) }
    }

    private func setImage(_ image: NSImage?, on layer: CALayer, scale: CGFloat) {
        guard let image else { return }
        layer.contentsScale = image.recommendedLayerContentsScale(scale)
        layer.contents = image.layerContents(forContentsScale: layer.contentsScale)
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold,
                               colour: NSColor = .white) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? 2
        ([capsule, recordingDot, stopSquare, restOutline, restFill] + bars).forEach { $0.contentsScale = scale }
        updateIcons()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    private func updateCaption() {
        let text: String?
        if dragging {
            text = nil
        } else {
            text = switch phase {
            case .transcribing: "Transcribing…"
            case let .notice(message), let .error(message): message
            case let .learned(words): cardShowing ? nil : "Learned: \(words)"  // the card says it
            case .copied: "Copied"
            case .done: nil
            case .recording:
                handsFree ? "Hands-free  ·  ⌃ Ctrl + ⌥ Opt or click to finish"
                    : hovering ? "Click to finish  ·  Esc cancels" : nil
            case .idle: hovering && !cardShowing ? idleHint : nil
            }
        }
        if let text {
            caption.stringValue = text
            caption.sizeToFit()
            let height = PillMetrics.captionHeight
            let centre = anchor.centre
            let reach = PillMetrics.thickness / 2 + PillMetrics.captionGap
            let room = anchor.standing
                ? bounds.width - PillMetrics.inset - PillMetrics.thickness - PillMetrics.captionGap - 4
                : bounds.width - 8
            let width = min(caption.frame.width + 28, room)
            // Inwards from the screen edge: above, below, or beside the pill.
            var frame: NSRect = switch anchor.edge {
            case .bottom: NSRect(x: centre.x - width / 2, y: centre.y + reach, width: width, height: height)
            case .top: NSRect(x: centre.x - width / 2, y: centre.y - reach - height, width: width, height: height)
            case .left: NSRect(x: centre.x + reach, y: centre.y - height / 2, width: width, height: height)
            case .right: NSRect(x: centre.x - reach - width, y: centre.y - height / 2, width: width, height: height)
            }
            frame.origin.x = min(max(frame.origin.x, 4), bounds.width - 4 - width)
            frame.origin.y = min(max(frame.origin.y, 2), bounds.height - 2 - height)
            captionBox.frame = frame
            caption.frame = NSRect(x: 14, y: (height - caption.frame.height) / 2, width: width - 28, height: caption.frame.height)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.captionBox.animator().alphaValue = text == nil ? 0 : 1
        }
    }

    // MARK: Mouse

    /// The pill's footprint, ignoring the hover zoom, with a little slack for clicking.
    private var pillRect: NSRect {
        let size = capsule.bounds.size
        return NSRect(x: capsule.position.x - size.width / 2, y: capsule.position.y - size.height / 2,
                      width: size.width, height: size.height).insetBy(dx: -4, dy: -4)
    }

    // Only the pill is clickable; the rest of the panel is transparent.
    override func hitTest(_ point: NSPoint) -> NSView? {
        pillRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateHoverArea() {
        let rect = pillRect
        guard rect != hoverRect else { return }
        hoverRect = rect
        if let hoverArea { removeTrackingArea(hoverArea) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if hovering { options.insert(.assumeInside) }  // otherwise the exit would never be reported
        let area = NSTrackingArea(rect: rect, options: options, owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    private func setHovering(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        layoutPill(animated: true)
        updateBarMotion()
        updateCaption()
        hoverCheck?.invalidate()
        hoverCheck = nil
        guard value else { return }
        // Backstop for a missed exit: clear the hover once the pointer is no longer over the pill.
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.dragging, !self.pointerIsOverPill else { return }
                self.setHovering(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverCheck = timer
    }

    private var pointerIsOverPill: Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return pillRect.contains(point)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        Log.input.notice("pill mouseDown")
        downLocation = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downLocation else { return }
        let now = NSEvent.mouseLocation
        if !dragging {
            guard hypot(now.x - start.x, now.y - start.y) >= 4 else { return }
            dragging = true
            updateCaption()
            layoutPill(animated: true)
            updateBarMotion()
            onDragBegan(start)
        }
        onDragMoved(now)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        downLocation = nil
        dragging = false
        if wasDragging {
            onDragEnded()
            layoutPill(animated: true)
            updateBarMotion()
            updateCaption()
        } else {
            onClick()
        }
    }
}
