import AppKit

/// A card beside the pill: the transcript with a Copy button when no text box is selected, or a
/// word just added to the dictionary with Undo. The panel never takes focus, so the app in front
/// keeps it.
@MainActor
final class PillCard {
    /// What the card shows: a heading, the main text, an optional line below it, and one action.
    struct Content: Equatable {
        var heading: String
        var body: String
        var detail: String?
        var action: String
        var actionSymbol: String
    }

    var onAction: () -> Void = {}
    var onClose: () -> Void = {}

    private let panel: NSPanel
    private let card = CardView(frame: .zero)
    /// Bumped on every show, so a fade-out that finishes after it does not hide the new card.
    private var generation = 0

    init() {
        panel = NonActivatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = card
        card.onAction = { [weak self] in self?.onAction() }
        card.onClose = { [weak self] in self?.onClose() }
    }

    /// Fills the card in and returns its size, for placing it.
    func prepare(_ content: Content) -> NSSize {
        card.fill(content)
    }

    func show(at origin: NSPoint) {
        generation += 1
        panel.setFrame(NSRect(origin: origin, size: card.frame.size), display: true)
        panel.invalidateShadow()
        guard !panel.isVisible || panel.alphaValue < 1 else { return }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        generation += 1
        let shown = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// The card: a heading, the main text (up to six lines), an optional detail line, an action
/// button and a close button.
private final class CardView: NSView {
    var onAction: () -> Void = {}
    var onClose: () -> Void = {}

    private static let width: CGFloat = 320
    private static let padding: CGFloat = 14
    private static let maxLines = 6

    private let heading = NSTextField(labelWithString: "")
    private let transcript = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let copyButton = CardButton()
    private let closeButton = CardButton()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.96).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor

        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = NSColor(white: 1, alpha: 0.5)
        transcript.font = .systemFont(ofSize: 13)
        transcript.textColor = .white
        transcript.maximumNumberOfLines = Self.maxLines
        transcript.cell?.truncatesLastVisibleLine = true
        transcript.isSelectable = false
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = NSColor(white: 1, alpha: 0.55)
        detail.maximumNumberOfLines = 3
        detail.isSelectable = false
        copyButton.prominent = true
        copyButton.onPress = { [weak self] in self?.onAction() }
        closeButton.symbol = "xmark"
        closeButton.onPress = { [weak self] in self?.onClose() }
        [heading, transcript, detail, copyButton, closeButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Clicks land on the buttons without first activating Humm.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Lays the card out for `content` and returns its size.
    func fill(_ content: PillCard.Content) -> NSSize {
        let inner = Self.width - 2 * Self.padding
        var y = Self.padding
        heading.stringValue = content.heading
        heading.sizeToFit()
        heading.frame = NSRect(x: Self.padding, y: y, width: inner - 24, height: heading.frame.height)
        closeButton.frame = NSRect(x: Self.width - Self.padding - 16, y: y - 3, width: 20, height: 20)
        y += heading.frame.height + 6

        transcript.stringValue = content.body
        transcript.preferredMaxLayoutWidth = inner
        let lineHeight = ceil((transcript.font?.boundingRectForFont.height ?? 16))
        let height = min(ceil(transcript.sizeThatFits(NSSize(width: inner, height: 10_000)).height),
                         lineHeight * CGFloat(Self.maxLines))
        transcript.frame = NSRect(x: Self.padding, y: y, width: inner, height: height)
        y += height + 12

        detail.isHidden = content.detail == nil
        if let text = content.detail {
            detail.stringValue = text
            detail.preferredMaxLayoutWidth = inner
            let detailHeight = ceil(detail.sizeThatFits(NSSize(width: inner, height: 1_000)).height)
            detail.frame = NSRect(x: Self.padding, y: y - 6, width: inner, height: detailHeight)
            y += detailHeight + 6
        }

        copyButton.title = content.action
        copyButton.symbol = content.actionSymbol
        copyButton.frame = NSRect(x: Self.width - Self.padding - 88, y: y, width: 88, height: 26)
        y += 26 + Self.padding

        let size = NSSize(width: Self.width, height: y)
        setFrameSize(size)
        return size
    }
}

/// A capsule button drawn by hand: a symbol, an optional title, and a hover highlight.
private final class CardButton: NSView {
    var onPress: () -> Void = {}
    var title: String? { didSet { needsDisplay = true } }
    var symbol = "" { didSet { needsDisplay = true } }
    /// Filled, for the main action; otherwise only a hover highlight.
    var prominent = false
    private var hovering = false { didSet { needsDisplay = true } }
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let fill = prominent ? (hovering ? 0.28 : 0.18) : (hovering ? 0.16 : 0)
        NSColor(white: 1, alpha: fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
        let text = title.map {
            NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                        .foregroundColor: NSColor.white])
        }
        let imageSize = image?.size ?? .zero
        let textSize = text?.size() ?? .zero
        let gap: CGFloat = text == nil ? 0 : 5
        var x = (bounds.width - imageSize.width - gap - textSize.width) / 2
        image?.draw(in: NSRect(x: x, y: (bounds.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height))
        x += imageSize.width + gap
        text?.draw(at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2))
    }
}
