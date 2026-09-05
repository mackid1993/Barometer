import AppKit
import MenuBarStatsCore
import SwiftUI

enum UpdateOfferChoice {
    case install
    case later
    case skip
}

/// Presents a release on the normal application event loop so scrolling never enters an alert's modal loop.
@MainActor
final class UpdateOfferWindowController: NSWindowController, NSWindowDelegate {
    private let completion: (UpdateOfferChoice) -> Void
    private var didComplete = false
    private weak var offerContentView: UpdateOfferContentView?

    var releaseNotesViewport: ReleaseNotesViewport? {
        offerContentView?.releaseNotesViewport
    }

    init(release: UpdateRelease, completion: @escaping (UpdateOfferChoice) -> Void) {
        self.completion = completion
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let releaseURL = URL(
            string: "https://github.com/mackid1993/Barometer/releases/tag/v\(release.version)"
        )
        let contentView = UpdateOfferContentView(
            version: release.version.description,
            releaseNotes: ReleaseNotesFormatter.attributedString(markdown: release.notes),
            releaseURL: releaseURL,
            installAction: { [weak self] in self?.complete(.install) },
            laterAction: { [weak self] in self?.complete(.later) },
            skipAction: { [weak self] in self?.complete(.skip) }
        )
        offerContentView = contentView
        window.contentView = contentView
        window.title = "Barometer Update"
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 650, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UpdateOfferWindowController does not support storyboards")
    }

    func windowWillClose(_ notification: Notification) {
        complete(.later, closeWindow: false)
    }

    private func complete(_ choice: UpdateOfferChoice, closeWindow: Bool = true) {
        guard !didComplete else { return }
        didComplete = true
        if closeWindow {
            close()
        }
        completion(choice)
    }
}

/// AppKit owns the complete update hierarchy. Keeping the scrolling path out of an `NSHostingView` avoids a full
/// SwiftUI hit-test, display-list update, and glass-effect animation for every trackpad event.
@MainActor
final class UpdateOfferContentView: NSView {
    let releaseNotesViewport: ReleaseNotesViewport

    private let releaseURL: URL?
    private let installAction: @MainActor @Sendable () -> Void
    private let laterAction: @MainActor @Sendable () -> Void
    private let skipAction: @MainActor @Sendable () -> Void
    private var didSetInitialScrollPosition = false

    init(
        version: String,
        releaseNotes: NSAttributedString,
        releaseURL: URL?,
        installAction: @escaping @MainActor @Sendable () -> Void,
        laterAction: @escaping @MainActor @Sendable () -> Void,
        skipAction: @escaping @MainActor @Sendable () -> Void
    ) {
        self.releaseURL = releaseURL
        self.installAction = installAction
        self.laterAction = laterAction
        self.skipAction = skipAction
        releaseNotesViewport = ReleaseNotesViewport(document: releaseNotes)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = UpdateOfferColors.window.cgColor

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        let header = makeHeader(version: version)
        let notes = makeReleaseNotesCard()
        let buttons = makeButtons()
        rootStack.addArrangedSubview(header)
        rootStack.addArrangedSubview(notes)
        rootStack.addArrangedSubview(buttons)
        notes.setContentHuggingPriority(.defaultLow, for: .vertical)
        notes.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            notes.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            releaseNotesViewport.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UpdateOfferContentView does not support storyboards")
    }

    override func layout() {
        super.layout()
        releaseNotesViewport.prepareForScrolling()
        if !didSetInitialScrollPosition {
            didSetInitialScrollPosition = true
            releaseNotesViewport.scroll(to: 0)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = UpdateOfferColors.window.cgColor
        releaseNotesViewport.updateAppearance()
    }

    private func makeHeader(version: String) -> NSView {
        let host = NSHostingView(rootView: UpdateOfferHeaderView(version: version))
        host.sizingOptions = [NSHostingSizingOptions.intrinsicContentSize]
        return host
    }

    private func makeReleaseNotesCard() -> NSView {
        let card = UpdateCardView(style: .plain)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let label = NSTextField(labelWithString: "RELEASE NOTES")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.alphaValue = 0.8
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(releaseNotesViewport)
        releaseNotesViewport.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            releaseNotesViewport.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return card
    }

    private func makeButtons() -> NSView {
        let host = NSHostingView(rootView: UpdateOfferButtonsView(
            releaseURL: releaseURL,
            installAction: installAction,
            laterAction: laterAction,
            skipAction: skipAction
        ))
        host.sizingOptions = [NSHostingSizingOptions.intrinsicContentSize]
        return host
    }
}

private struct UpdateOfferHeaderView: View {
    let version: String
    private let accent = ModuleAccent(primary: Color(hex: 0x2F7CF6), secondary: Color(hex: 0x38BDF8))

    var body: some View {
        GlassCard(tint: accent.primary) {
            HStack(spacing: 14) {
                IconTile(symbolName: "arrow.down.app.fill", accent: accent, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Barometer \(version) Is Available")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(
                        "Barometer will automatically download the disk image from GitHub, verify it, replace "
                            + "the app in Applications, and then reopen."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct UpdateOfferButtonsView: View {
    let releaseURL: URL?
    let installAction: @MainActor () -> Void
    let laterAction: @MainActor () -> Void
    let skipAction: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let releaseURL {
                Link(destination: releaseURL) {
                    Label("View Release on GitHub", systemImage: "safari")
                }
                .buttonStyle(.glass)
                .fixedSize(horizontal: true, vertical: false)
                .help("Inspect the release and choose the download directly on GitHub.")
            }
            Button("Skip This Version", action: skipAction)
                .buttonStyle(.glass)
            Spacer()
            Button("Later", action: laterAction)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button(action: installAction) {
                Label("Download and Install", systemImage: "arrow.down.app.fill")
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 4)
    }
}

@MainActor
private final class UpdateCardView: NSView {
    enum Style {
        case accent
        case plain
    }

    private let style: Style

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        updateSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UpdateCardView does not support storyboards")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }

    private func updateSurface() {
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = UpdateOfferColors.border.cgColor
        layer?.backgroundColor = switch style {
        case .accent:
            UpdateOfferColors.header.cgColor
        case .plain:
            UpdateOfferColors.card.cgColor
        }
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }
}

/// A read-only document viewport that deliberately avoids `NSScrollView`. On macOS 27, `NSScrollView` starts a
/// concurrent display-link animation for trackpad input even when its normal wheel handler is overridden.
@MainActor
final class ReleaseNotesViewport: NSView {
    private let document: NSAttributedString
    private let clipView = DirectClipView()
    private let documentView = FlippedDocumentView()
    let textField = DirectScrollTextField()
    private let scroller = NSScroller()
    private var preparedDocumentWidth: CGFloat = 0
    private(set) var layoutPreparationCount = 0

    var verticalOffset: CGFloat { clipView.bounds.origin.y }
    var maximumOffset: CGFloat { max(0, documentView.frame.height - clipView.bounds.height) }

    init(document: NSAttributedString) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        clipView.drawsBackground = true
        clipView.viewport = self
        addSubview(clipView)
        clipView.documentView = documentView

        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.attributedStringValue = document
        textField.viewport = self
        documentView.viewport = self
        documentView.addSubview(textField)

        scroller.scrollerStyle = .overlay
        scroller.controlSize = .small
        scroller.target = self
        scroller.action = #selector(scrollerChanged(_:))
        addSubview(scroller)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReleaseNotesViewport does not support storyboards")
    }

    override func layout() {
        super.layout()
        let scrollerWidth = NSScroller.scrollerWidth(for: .small, scrollerStyle: .overlay)
        clipView.frame = bounds
        scroller.frame = NSRect(x: bounds.maxX - scrollerWidth, y: 0, width: scrollerWidth, height: bounds.height)
        prepareForScrolling()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func prepareForScrolling() {
        let contentWidth = floor(max(1, clipView.bounds.width - 34))
        guard abs(contentWidth - preparedDocumentWidth) >= 1 else {
            updateScroller()
            return
        }
        preparedDocumentWidth = contentWidth
        layoutPreparationCount += 1
        let drawingBounds = document.boundingRect(
            with: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textHeight = max(1, ceil(drawingBounds.height))
        let documentHeight = max(clipView.bounds.height, textHeight + 20)
        documentView.frame = NSRect(x: 0, y: 0, width: clipView.bounds.width, height: documentHeight)
        textField.frame = NSRect(x: 12, y: 10, width: contentWidth, height: textHeight)
        scroll(to: verticalOffset)
    }

    func scroll(to offset: CGFloat) {
        clipView.scroll(to: NSPoint(x: 0, y: min(max(0, offset), maximumOffset)))
        updateScroller()
    }

    func handleScrollWheel(_ event: NSEvent) {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        scroll(to: verticalOffset - event.scrollingDeltaY * scale)
    }

    func updateAppearance() {
        layer?.backgroundColor = UpdateOfferColors.notesPlate.cgColor
        clipView.backgroundColor = UpdateOfferColors.notesPlate
    }

    @objc private func scrollerChanged(_ sender: NSScroller) {
        scroll(to: CGFloat(sender.doubleValue) * maximumOffset)
    }

    private func updateScroller() {
        let maximumOffset = maximumOffset
        scroller.isHidden = maximumOffset <= 0
        guard maximumOffset > 0 else { return }
        scroller.doubleValue = Double(verticalOffset / maximumOffset)
        scroller.knobProportion = min(1, clipView.bounds.height / documentView.frame.height)
    }
}

@MainActor
final class DirectClipView: NSClipView {
    weak var viewport: ReleaseNotesViewport?
    override func scrollWheel(with event: NSEvent) { viewport?.handleScrollWheel(event) }
}

@MainActor
final class DirectScrollTextField: NSTextField {
    weak var viewport: ReleaseNotesViewport?
    override func scrollWheel(with event: NSEvent) { viewport?.handleScrollWheel(event) }
}

@MainActor
final class FlippedDocumentView: NSView {
    weak var viewport: ReleaseNotesViewport?
    override var isFlipped: Bool { true }
    override func scrollWheel(with event: NSEvent) { viewport?.handleScrollWheel(event) }
}

@MainActor
private enum UpdateOfferColors {
    static let window = adaptive(darkWhite: 0.12, lightWhite: 0.94)
    static let header = adaptive(darkRed: 0.20, darkGreen: 0.25, darkBlue: 0.32, lightWhite: 0.90)
    static let card = adaptive(darkWhite: 0.22, lightWhite: 0.91)
    static let notesPlate = adaptive(darkWhite: 0.27, lightWhite: 0.98)
    static let border = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)
    }

    private static func adaptive(darkWhite: CGFloat, lightWhite: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(deviceWhite: isDark(appearance) ? darkWhite : lightWhite, alpha: 1)
        }
    }

    private static func adaptive(
        darkRed: CGFloat,
        darkGreen: CGFloat,
        darkBlue: CGFloat,
        lightWhite: CGFloat
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            if isDark(appearance) {
                return NSColor(deviceRed: darkRed, green: darkGreen, blue: darkBlue, alpha: 1)
            }
            return NSColor(deviceWhite: lightWhite, alpha: 1)
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
