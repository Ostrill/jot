//
//  GlassEditorView.swift
//  The per-window editor: glass stack, two-layer text, status block.
//

import AppKit

final class GlassEditorView: NSView {
    enum TitleBarLayout {
        static let buttonSpacing: CGFloat = 6.0
        static let trailingInset: CGFloat = 22.0
        static let editorTopInset: CGFloat = 46.0
        static let titleGapAfterButtons: CGFloat = 90.0
    }

    var settings = PanelSettings() {
        didSet { applySettings(previous: oldValue) }
    }

    var onTextDidChange: (() -> Void)?

    // MARK: Inactive-window transparency
    //
    // The WindowServer renders NSGlassEffectView "subdued" (that milky, near-opaque
    // look) whenever its window isn't key — decided at composite time by the system, so
    // there is no app-side lever to keep the glass truly live. (Verified at runtime: the
    // view's private state is byte-for-byte identical active vs inactive.) The best we
    // can do with public API is lower the *whole window's* opacity when it's inactive,
    // so the desktop shows through and it reads as semi-transparent rather than an opaque
    // plate. Tune to taste.
    private static let inactiveWindowAlpha: CGFloat = 0.8

    private let glassContainer = NSGlassEffectContainerView(frame: .zero)
    private let glassView = NSGlassEffectView(frame: .zero)
    private let contentHost = NSView(frame: .zero)
    private let hitShield = HitTestShieldView(frame: .zero)
    private let colorLayer = CALayer()
    private let dimLayer = CALayer()
    private let editorScrollView = NSScrollView(frame: .zero)
    private let edgeFadeMask = EdgeFadeMaskLayer()
    private let editorContentView = FlippedContentView(frame: .zero)
    private let wrapGuideView = WrapGuideView(frame: .zero)
    private var backdropTextView: BackdropTextView!
    private var editorTextView = EditorTextView(frame: .zero)
    private let fileStatusStack = NSStackView()
    private let fileIndicatorField = NSTextField(labelWithString: "")
    private let fileNameField = NSTextField(labelWithString: "")
    private var currentFileName: String?
    private var currentFilePath: String?
    private var fileIsEdited = false

    // Inline LaTeX editing state.
    private let mathPreview = MathPreviewView(frame: .zero)
    private var mathEditRange: NSRange?        // the raw "$$…$$" span the caret is inside (recomputed, not grown)
    private var isProcessingMath = false       // re-entrancy guard for programmatic edits
    private var isReconciling = false          // re-entrancy guard around reconcileMath()
    private var reconcilePending = false       // a reconcile is queued for the next runloop tick
    private var pendingAutoCloseAt: Int?       // caret pos where "$$" should auto-close
    private var highlightedMathRange: NSRange? // the span currently greyed, so it can be un-greyed cheaply

    /// Find & replace — built the first time it is asked for (see FindBar.swift).
    private var finder: EditorFindController?

    /// Measuring the document's exact height makes the layout manager lay out everything
    /// that changed — the one thing that can still make a big document stutter (an edit in
    /// the middle of 8000 lines cost ~150 ms; opening 2000 lines, ~230 ms). Above this size
    /// the height is not measured while typing, opening or resizing: the content is grown
    /// just enough to cover the viewport and the caret's own line (cheap — that line is
    /// laid out anyway), and the exact measurement runs shortly after things settle.
    /// Below this size nothing is deferred.
    private static let inlineHeightMeasurementLimit = 40_000        // characters
    private static let deferredHeightSyncDelay: TimeInterval = 0.1
    private var pendingHeightSync: DispatchWorkItem?

    private var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)
    }
    /// Current tint for rendered formulas — the composite "white-with-accent-tint"
    /// color. Kept in sync as Rainbow animates so formulas cycle hue with the text.
    private var currentFormulaTint: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.92)

    var text: String {
        get { serializedText() }
        set { setText(newValue) }
    }

    var selectedRange: NSRange {
        get { editorTextView.selectedRange() }
        set { editorTextView.setSelectedRange(newValue) }
    }

    private func makeEditorTextView() -> EditorTextView {
        let textView = EditorTextView(frame: .zero)
        textView.minSize = NSSize(width: 160.0, height: 160.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 10.0, height: 6.0)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        return textView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()

        let titleMetrics = titleBarMetrics()
        // Each branch of titleBarMetrics already applies its own floor.
        let topInset = titleMetrics.editorTopInset
        let outerInset: CGFloat = 18.0
        let editorRect = CGRect(
            x: outerInset,
            y: outerInset,
            width: max(bounds.width - (outerInset * 2.0), 120.0),
            height: max(bounds.height - topInset - outerInset, 120.0)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassContainer.frame = bounds
        glassView.frame = bounds
        contentHost.frame = bounds
        hitShield.frame = bounds
        colorLayer.frame = bounds
        dimLayer.frame = bounds
        CATransaction.commit()

        editorScrollView.frame = editorRect
        layoutFindBar()
        updateEdgeFade()
        // Only when there is a document to show: laying the stack out at zero width
        // otherwise breaks its own internal spacing constraint.
        if !fileStatusStack.isHidden {
            let maxStatusWidth = max(bounds.width - titleMetrics.leadingReserve - TitleBarLayout.trailingInset, 120.0)
            let statusSize = fileStatusStack.fittingSize
            let clampedWidth = max(min(statusSize.width, maxStatusWidth), 1.0)
            fileStatusStack.frame = CGRect(
                x: bounds.width - clampedWidth - TitleBarLayout.trailingInset,
                y: titleMetrics.statusOriginY,
                width: clampedWidth,
                height: statusSize.height
            )
        }
        syncEditorLayout(deferHeightInLargeDocuments: true)
        // Keep the preview under the formula when the window is resized (not only on
        // keystrokes), so it no longer drifts relative to the window's bottom edge.
        if let r = mathEditRange, !mathPreview.isHidden {
            positionMathPreview(belowFormulaRange: r, size: mathPreview.frame.size)
        }

        updateChrome()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        glassContainer.contentView = glassView
        addSubview(glassContainer)

        // The app's content sits ON TOP of the glass as a sibling, NOT inside
        // `glassView.contentView`. Anything inside the glass view is drawn by the
        // WindowServer only while the window is composited live: in a snapshot —
        // Mission Control, the window switcher, a screenshot, the minimise animation —
        // the glass collapses to a flat plate and its contentView is not drawn at all,
        // so the window appeared completely empty there.
        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentHost, positioned: .above, relativeTo: glassContainer)

        if let hostLayer = contentHost.layer {
            for layer in [colorLayer, dimLayer] {
                layer.actions = [
                    "bounds": NSNull(),
                    "position": NSNull(),
                    "backgroundColor": NSNull(),
                    "cornerRadius": NSNull(),
                    "opacity": NSNull()
                ]
                hostLayer.addSublayer(layer)
            }
        }

        colorLayer.backgroundColor = settings.accentColor.cgColor
        dimLayer.backgroundColor = settings.dimColor.cgColor

        hitShield.wantsLayer = true
        hitShield.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.001).cgColor
        contentHost.addSubview(hitShield)

        setupEditor()
        applySettings(previous: nil)
    }

    private func setupEditor() {
        editorScrollView.borderType = .noBorder
        editorScrollView.hasVerticalScroller = true
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.drawsBackground = false
        editorScrollView.automaticallyAdjustsContentInsets = false
        editorScrollView.scrollerStyle = .overlay
        // Fade the text out against the glass at the top and bottom of the viewport.
        // The mask goes on the clip view, so it stays put while the content scrolls
        // under it, and it covers every layer of the editor at once.
        let clipView = editorScrollView.contentView
        clipView.wantsLayer = true
        clipView.layer?.mask = edgeFadeMask
        // With a mask in place the viewport has to be redrawn as a whole: the scroll
        // view's default optimisation copies the existing pixels and redraws only the
        // newly exposed strip, which under a mask leaves torn, stale text behind.
        clipView.copiesOnScroll = false
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportDidScroll),
            name: NSView.boundsDidChangeNotification, object: clipView
        )

        editorTextView = makeEditorTextView()
        editorTextView.string = ""
        editorTextView.cancelHandler = { [weak self] in
            guard let finder = self?.finder, finder.isVisible else { return false }
            finder.hide()
            return true
        }

        // The backdrop shares the editor's text storage — one storage, two layout
        // managers — so it mirrors every edit for free. (It used to be a second,
        // independent text view whose whole content was copied over on every
        // keystroke, which meant a full relayout of the document per character.)
        // It carries no attributes of its own and is not a text view: it just draws the
        // shared storage through its own layout manager (see BackdropTextView).
        backdropTextView = BackdropTextView(sharing: editorTextView.textStorage!)
        backdropTextView.textContainerInset = editorTextView.textContainerInset
        backdropTextView.mirroredContainer = editorTextView.textContainer

        editorContentView.wantsLayer = true
        editorContentView.layer?.backgroundColor = NSColor.clear.cgColor
        wrapGuideView.textView = editorTextView
        wrapGuideView.isHidden = true
        editorContentView.addSubview(wrapGuideView)
        editorContentView.addSubview(backdropTextView)
        editorContentView.addSubview(editorTextView)
        editorTextView.mathHost = self

        editorScrollView.documentView = editorContentView
        contentHost.addSubview(editorScrollView)

        fileIndicatorField.font = .systemFont(ofSize: 12.0, weight: .semibold)
        fileIndicatorField.alignment = .right
        fileIndicatorField.setContentHuggingPriority(.required, for: .horizontal)
        fileIndicatorField.setContentCompressionResistancePriority(.required, for: .horizontal)

        fileNameField.font = .systemFont(ofSize: 12.0, weight: .semibold)
        fileNameField.alignment = .right
        fileNameField.lineBreakMode = .byTruncatingMiddle
        fileNameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileNameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        fileStatusStack.orientation = .horizontal
        fileStatusStack.alignment = .centerY
        fileStatusStack.distribution = .fill
        fileStatusStack.spacing = 4.0
        fileStatusStack.addArrangedSubview(fileIndicatorField)
        fileStatusStack.addArrangedSubview(fileNameField)
        fileStatusStack.isHidden = true
        contentHost.addSubview(fileStatusStack)

        mathPreview.isHidden = true
        contentHost.addSubview(mathPreview)
    }

    /// `previous` is nil the first time round, when everything has to be applied.
    /// Otherwise only what actually changed is pushed into the document: rewriting the
    /// font or colour across the storage invalidates the layout of the whole document,
    /// and settings arrive on *every mouse move* while a menu slider is being dragged.
    private func applySettings(previous: PanelSettings?) {
        applyGlassAppearance()
        let textAttributesChanged = previous.map {
            $0.editorFontSize != settings.editorFontSize || $0.editorTextColor != settings.editorTextColor
        } ?? true
        let formulaTintChanged = previous.map {
            $0.editorCompositeTextColor != settings.editorCompositeTextColor
                || $0.textShadowStrength != settings.textShadowStrength
                || $0.editorFontSize != settings.editorFontSize
        } ?? true
        applyEditorAppearance(
            using: settings,
            updateExistingText: textAttributesChanged,
            updateSelection: true,
            retintFormulas: formulaTintChanged
        )
        updateChrome()
    }

    private func applyGlassAppearance() {
        glassView.style = PanelSettings.Fixed.glassStyle
        glassContainer.spacing = 0.0

        colorLayer.backgroundColor = settings.accentColor.cgColor
        dimLayer.backgroundColor = settings.dimColor.cgColor
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        nc.addObserver(self, selector: #selector(windowActiveStateChanged), name: NSWindow.didBecomeKeyNotification, object: window)
        nc.addObserver(self, selector: #selector(windowActiveStateChanged), name: NSWindow.didResignKeyNotification, object: window)
        applyGlassActiveState()
    }

    @objc private func windowActiveStateChanged() {
        applyGlassActiveState()
    }

    /// An inactive window can't keep the live glass (the system forces it opaque/frosted),
    /// so instead make the whole window semi-transparent when it loses focus — the desktop
    /// shows through and it stops reading as a heavy opaque plate.
    private func applyGlassActiveState() {
        guard let window else { return }
        window.alphaValue = window.isKeyWindow ? 1.0 : Self.inactiveWindowAlpha
    }

    func applyAnimatedColorUpdate(_ updatedSettings: PanelSettings, refreshEditorTint: Bool) {
        colorLayer.backgroundColor = updatedSettings.accentColor.cgColor
        backdropTextView.layoutManager.glyphColor = updatedSettings.backdropTextColor
        backdropTextView.needsDisplay = true
        // Formulas are bitmaps, so they can't ride the backdrop's glyph colour like
        // the text — retint them (throttled via refreshEditorTint) so they
        // cycle hue with Rainbow too. Cheap: cached-image recolor, no re-render.
        currentFormulaTint = updatedSettings.editorCompositeTextColor
        if refreshEditorTint {
            recolorFormulas(to: currentFormulaTint)
            if !mathPreview.isHidden { mathPreview.applyTint(currentFormulaTint) }
        }
        wrapGuideView.guideColor = updatedSettings.wrapGuideColor
        // Update label colors directly — do NOT call updateFileStatusAppearance here.
        // That function sets needsLayout = true on GlassEditorView, which at 30fps
        // triggers syncEditorLayout() → textContainer invalidation, killing the
        // insertion point blink timer.
        fileIndicatorField.textColor = updatedSettings.documentIndicatorColor
        fileNameField.textColor = updatedSettings.statusTextColor
    }

    func setDocumentPresentation(fileURL: URL?, isEdited: Bool) {
        guard let fileURL else {
            currentFileName = nil
            currentFilePath = nil
            fileIsEdited = false
            fileStatusStack.isHidden = true
            fileNameField.toolTip = nil
            fileIndicatorField.stringValue = ""
            fileNameField.stringValue = ""
            return
        }

        currentFileName = fileURL.lastPathComponent
        currentFilePath = fileURL.path
        fileIsEdited = isEdited
        updateFileStatusAppearance(using: settings)
    }

    func setText(_ text: String) {
        let attributed = attributedStringRenderingFormulas(from: text)
        editorTextView.textStorage?.setAttributedString(attributed)
        mathEditRange = nil
        highlightedMathRange = nil
        pendingAutoCloseAt = nil
        hideMathPreview()
        syncEditorLayout(deferHeightInLargeDocuments: true)
    }

    /// Re-runs the document through the parser under the current renderInlineFormulas
    /// setting: turns rendered images back into `$$…$$` source (off) or renders the
    /// source into images (on). Call after toggling the setting.
    func reprocessFormulaRendering() {
        let caret = editorTextView.selectedRange().location
        setText(serializedText())
        let len = (editorTextView.string as NSString).length
        editorTextView.setSelectedRange(NSRange(location: min(caret, len), length: 0))
    }

    /// Serializes the document, turning rendered formula attachments back into
    /// `$$latex$$` source so files round-trip and stay editable elsewhere.
    private func serializedText() -> String {
        guard let storage = editorTextView.textStorage else { return editorTextView.string }
        let result = NSMutableString()
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            if let att = value as? MathAttachment {
                result.append("$$\(att.latex)$$")
            } else {
                result.append((storage.string as NSString).substring(with: range))
            }
        }
        return result as String
    }

    /// Parses `$$…$$` spans (via the shared MathSyntax parser) into rendered
    /// formula attachments; empty/invalid spans stay as raw source text.
    private func attributedStringRenderingFormulas(from text: String) -> NSAttributedString {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: settings.editorTextColor
        ]
        guard settings.renderInlineFormulas else {
            return NSAttributedString(string: text, attributes: baseAttrs)   // rendering off → plain source
        }
        let result = NSMutableAttributedString()
        let ns = text as NSString
        var cursor = 0
        for span in MathSyntax.completeSpans(in: ns) {
            if span.location > cursor {
                result.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: span.location - cursor)), attributes: baseAttrs))
            }
            let raw = MathSyntax.latex(of: span, in: ns)
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let base = MathRenderer.renderInlineBase(latex: raw, fontSize: settings.editorFontSize) {
                result.append(NSAttributedString(attachment: MathAttachment(latex: raw, baseImage: base, font: editorFont, tint: currentFormulaTint, shadow: settings.editorTextShadow)))
            } else {
                result.append(NSAttributedString(string: ns.substring(with: span), attributes: baseAttrs))
            }
            cursor = span.location + span.length
        }
        if cursor < ns.length {
            result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: baseAttrs))
        }
        return result
    }

    func focusEditor() {
        guard let window else { return }
        window.makeFirstResponder(editorTextView)
        editorTextView.updateInsertionPointStateAndRestartTimer(true)
        editorTextView.needsDisplay = true
    }

    private func applyEditorAppearance(
        using appearanceSettings: PanelSettings,
        updateExistingText: Bool,
        updateSelection: Bool,
        retintFormulas: Bool = true
    ) {
        let font = NSFont.monospacedSystemFont(ofSize: appearanceSettings.editorFontSize, weight: .regular)
        // NSTextView.font/.textColor write through to the storage, so they are set only
        // when they change — see updateExistingText below. An empty document costs
        // nothing to write, and skipping it there would leave the caret at the system
        // default font until the first edit.
        if updateExistingText || (editorTextView.textStorage?.length ?? 0) == 0 {
            editorTextView.font = font
            editorTextView.textColor = appearanceSettings.editorTextColor
        }
        editorTextView.insertionPointColor = appearanceSettings.caretColor
        editorTextView.typingAttributes = [
            .font: font,
            .foregroundColor: appearanceSettings.editorTextColor
        ]
        wrapGuideView.guideColor = appearanceSettings.wrapGuideColor
        wrapGuideView.guideXOffset = PanelSettings.Fixed.wrapGuideXOffset
        wrapGuideView.guideThickness = PanelSettings.Fixed.wrapGuideThickness
        wrapGuideView.guideTopTrim = PanelSettings.Fixed.wrapGuideTopTrim
        wrapGuideView.guideBottomTrim = PanelSettings.Fixed.wrapGuideBottomTrim
        wrapGuideView.roundedCaps = PanelSettings.Fixed.wrapGuideRounded
        if updateSelection {
            editorTextView.selectedTextAttributes = [
                .backgroundColor: appearanceSettings.selectionColor,
                .foregroundColor: appearanceSettings.editorTextColor
            ]
        }
        applyWordWrap(using: appearanceSettings)
        updateFileStatusAppearance(using: appearanceSettings)

        let range = NSRange(location: 0, length: editorTextView.string.utf16.count)
        if updateExistingText, let storage = editorTextView.textStorage, range.length > 0 {
            storage.beginEditing()
            storage.addAttributes([.font: font, .foregroundColor: appearanceSettings.editorTextColor], range: range)
            storage.endEditing()
            highlightedMathRange = nil          // the full-range repaint above wiped it
            applyMathHighlight()
        }
        currentFormulaTint = appearanceSettings.editorCompositeTextColor
        if retintFormulas { recolorFormulas(to: currentFormulaTint) }
        applyBackdropAppearance(using: appearanceSettings)
        syncEditorLayout(deferHeightInLargeDocuments: true)
    }

    private func applyWordWrap(using appearanceSettings: PanelSettings) {
        let showsGuides = appearanceSettings.wordWrap && appearanceSettings.showWrapGuides

        editorScrollView.hasHorizontalScroller = !appearanceSettings.wordWrap
        editorTextView.isHorizontallyResizable = !appearanceSettings.wordWrap
        editorTextView.textContainerInset = NSSize(width: 10.0, height: 6.0)
        backdropTextView.textContainerInset = editorTextView.textContainerInset
        wrapGuideView.isGuideVisible = showsGuides

        // Written only when they change: assigning NSTextContainer.size invalidates the
        // layout of the whole document (see syncEditorLayout).
        let containerSize = NSSize(
            width: appearanceSettings.wordWrap
                ? wrappingContainerWidth(forContentWidth: max(editorScrollView.contentSize.width, 120.0))
                : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let editorContainer = editorTextView.textContainer {
            if editorContainer.widthTracksTextView != appearanceSettings.wordWrap {
                editorContainer.widthTracksTextView = appearanceSettings.wordWrap
            }
            if editorContainer.size != containerSize { editorContainer.size = containerSize }
        }
        mirrorBackdropContainer()
    }

    /// The backdrop layer carries no attributes of its own — it shares the editor's
    /// storage and gets its colour and legibility halo forced at draw time. The halo
    /// lives ONLY here, never on the translucent editor glyphs on top: a shadow drawn
    /// under a translucent glyph shows through and dims it, whereas the ~0.94-opaque
    /// backdrop glyph covers it, leaving only the halo *around* the text.
    private func applyBackdropAppearance(using appearanceSettings: PanelSettings) {
        backdropTextView.layoutManager.glyphShadow = appearanceSettings.editorTextShadow
        backdropTextView.layoutManager.glyphColor = appearanceSettings.backdropTextColor
        backdropTextView.needsDisplay = true
    }

    /// Keeps the two text layers and the scrolled content the same size. This runs on
    /// every keystroke, so it is deliberately cheap: it never forces a full-document
    /// layout (the layout managers lay out lazily, on demand, for what is drawn) and it
    /// writes frames only when they actually change — assigning the same frame would
    /// still repaint the wrap guides over the whole document.
    @objc private func viewportDidScroll() {
        invalidateTextLayers()
        updateEdgeFade()
    }

    /// Both of these are plain views as tall as the document whose drawing depends on the
    /// text layout, so they scroll with the text exactly like the editor does — no chance
    /// of a layer separating by a frame. The price is that AppKit caches their drawing per
    /// region, and a region drawn under an older layout would stay on screen: that is what
    /// made the text appear doubled. Neither has an NSTextView to invalidate them, so they
    /// are marked for redraw on every scroll as well as on every layout change.
    private func invalidateTextLayers() {
        backdropTextView.needsDisplay = true
        wrapGuideView.needsDisplay = true
    }

    /// Keeps the viewport's fade in step with the scroll position and the window size.
    private func updateEdgeFade() {
        let clipView = editorScrollView.contentView
        let viewport = clipView.bounds
        let documentHeight = editorContentView.frame.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The clip view scrolls by moving its own bounds origin, so the mask has to be
        // placed at that origin to stay over the viewport. Pinning it at .zero left it
        // sitting at the top of the *document*: everything scrolled past it vanished.
        edgeFadeMask.frame = viewport
        CATransaction.commit()
        edgeFadeMask.update(
            topHidden: viewport.minY,
            bottomHidden: documentHeight - viewport.maxY,
            viewportHeight: viewport.height
        )
    }

    private func syncEditorLayout(deferHeightInLargeDocuments: Bool = false) {
        let visibleWidth = max(editorScrollView.contentSize.width, 120.0)
        let visibleHeight = max(editorScrollView.contentSize.height, 120.0)
        let contentWidth = settings.wordWrap ? visibleWidth : max(measuredTextWidth(), visibleWidth)
        let containerSize = NSSize(
            width: settings.wordWrap ? wrappingContainerWidth(forContentWidth: contentWidth) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        if let editorContainer = editorTextView.textContainer {
            if editorContainer.size != containerSize { editorContainer.size = containerSize }
            if editorContainer.widthTracksTextView != settings.wordWrap {
                editorContainer.widthTracksTextView = settings.wordWrap
            }
        }
        mirrorBackdropContainer()

        // Both layers share one storage and one container width, so one measurement
        // covers them both.
        let length = editorTextView.textStorage?.length ?? 0
        let deferHeight = deferHeightInLargeDocuments && length > Self.inlineHeightMeasurementLimit
        let height: CGFloat
        if deferHeight {
            height = max(editorContentView.frame.height, caretLineBottom())
            scheduleExactHeightSync()
        } else {
            pendingHeightSync?.cancel()
            pendingHeightSync = nil
            height = measuredTextHeight()
        }
        let contentFrame = NSRect(x: 0.0, y: 0.0, width: contentWidth, height: max(height, visibleHeight))
        guard editorContentView.frame != contentFrame else { return }

        editorContentView.frame = contentFrame
        updateEdgeFade()
        wrapGuideView.frame = editorContentView.bounds
        editorTextView.frame = editorContentView.bounds
        backdropTextView.frame = editorContentView.bounds
        mirrorBackdropContainer()
        invalidateTextLayers()
    }

    /// The width a wrapping container must have in a text view `contentWidth` wide — the
    /// same width NSTextView itself gives a container that tracks it: its own width less
    /// the inset on both sides. Anything else is a tug of war: this code used to write the
    /// full width, the text view put it back whenever its frame changed, and every flip
    /// threw away the layout of the whole document in both text layers (~1 s of CPU per
    /// burst of typing in a 4000-line file, most of it re-drawing the halo). It also let
    /// lines run 10 pt past the right edge.
    private func wrappingContainerWidth(forContentWidth contentWidth: CGFloat) -> CGFloat {
        max(contentWidth - (editorTextView.textContainerInset.width * 2.0), 1.0)
    }

    /// The editor's text view owns its container's width — NSTextView keeps it at its own
    /// width minus the inset (`widthTracksTextView`), which our plain backdrop view cannot
    /// do for itself, so the backdrop copies it verbatim. If the two differ by even a few
    /// points, the lines wrap differently and the two text layers drift further apart the
    /// further down the document you look.
    private func mirrorBackdropContainer() {
        guard let editorContainer = editorTextView.textContainer else { return }
        let container = backdropTextView.textContainer
        if container.widthTracksTextView { container.widthTracksTextView = false }
        backdropTextView.mirroredContainer = editorContainer
        backdropTextView.mirrorContainerGeometry()
    }

    /// An NSTextView updates its container width from its frame on its own schedule, and
    /// during a live resize that can land after our own layout pass — so both layers are
    /// re-synced once the drag ends.
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        mirrorBackdropContainer()
        invalidateTextLayers()
        syncEditorLayout()
    }

    /// Runs the exact height measurement once the user stops typing.
    private func scheduleExactHeightSync() {
        pendingHeightSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHeightSync = nil
            self?.syncEditorLayout()
        }
        pendingHeightSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deferredHeightSyncDelay, execute: work)
    }

    /// Bottom of the line the caret is on, so the content can be grown enough to keep the
    /// caret visible without measuring the whole document. Cheap: that line has just been
    /// laid out, and everything before it still is.
    private func caretLineBottom() -> CGFloat {
        guard let layoutManager = editorTextView.layoutManager,
              editorTextView.textContainer != nil,
              let storage = editorTextView.textStorage else { return 0.0 }
        let caret = min(editorTextView.selectedRange().location, storage.length)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: caret)
        let rect: CGRect
        if glyphIndex < layoutManager.numberOfGlyphs {
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        } else if layoutManager.extraLineFragmentTextContainer != nil {
            rect = layoutManager.extraLineFragmentRect
        } else {
            return 0.0
        }
        return ceil(rect.maxY + (editorTextView.textContainerInset.height * 2.0) + 6.0)
    }

    private func measuredTextHeight() -> CGFloat {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else {
            return max(editorScrollView.contentSize.height, 120.0)
        }
        // Measured from the glyphs' bounding rect rather than usedRect: usedRect is
        // updated *during* the layout pass that the same call triggers, so right after a
        // large change the first call comes back stale (18 pt for a 2000-line document)
        // and only a second call is correct. The old code hid that by measuring twice.
        // This only has to catch up on what an edit invalidated — which is why the
        // container size is written above only when it actually changes: assigning
        // NSTextContainer.size invalidates the layout of the *whole* document, and doing
        // that on every keystroke used to cost ~90 ms in a 2000-line file.
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var bottom = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).maxY
        // The empty line after a trailing newline is a fragment of its own.
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            bottom = max(bottom, layoutManager.extraLineFragmentRect.maxY)
        }
        return ceil(bottom + (editorTextView.textContainerInset.height * 2.0) + 6.0)
    }

    private func measuredTextWidth() -> CGFloat {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else {
            return max(editorScrollView.contentSize.width, 120.0)
        }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let usedWidth = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).maxX
        return ceil(usedWidth + (editorTextView.textContainerInset.width * 2.0) + 40.0)
    }

    private func updateChrome() {
        let radius = PanelSettings.Fixed.cornerRadius
        glassView.cornerRadius = radius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorLayer.cornerRadius = radius
        dimLayer.cornerRadius = radius
        CATransaction.commit()
    }

    private func updateFileStatusAppearance(using appearanceSettings: PanelSettings) {
        guard let currentFileName else {
            fileStatusStack.isHidden = true
            fileNameField.toolTip = nil
            fileIndicatorField.stringValue = ""
            fileNameField.stringValue = ""
            return
        }

        fileIndicatorField.stringValue = fileIsEdited ? PanelSettings.Fixed.documentIndicatorSymbol : ""
        fileIndicatorField.textColor = appearanceSettings.documentIndicatorColor
        fileIndicatorField.isHidden = !fileIsEdited
        fileNameField.stringValue = currentFileName
        fileNameField.textColor = appearanceSettings.statusTextColor
        fileNameField.toolTip = currentFilePath
        fileStatusStack.isHidden = false
        needsLayout = true
    }

    private func titleBarMetrics() -> (statusOriginY: CGFloat, leadingReserve: CGFloat, editorTopInset: CGFloat) {
        guard let window,
              let closeButton = window.standardWindowButton(.closeButton),
              let buttonSuperview = closeButton.superview else {
            let fallbackTopInset = max(safeAreaInsets.top + 10.0, 46.0)
            return (bounds.height - fallbackTopInset + 8.0, 110.0, fallbackTopInset)
        }

        // Read where AppKit actually placed the traffic lights (in window/content
        // coordinates — the content view fills the window with fullSizeContentView)
        // so the status block and editor inset follow the buttons automatically.
        let buttonFrame = buttonSuperview.convert(closeButton.frame, to: nil)
        let buttonCenterY = buttonFrame.midY
        let buttonsWidth = (buttonFrame.width * 3.0) + (TitleBarLayout.buttonSpacing * 2.0)
        let leadingReserve = buttonFrame.minX + buttonsWidth + TitleBarLayout.titleGapAfterButtons
        let statusHeight = fileStatusStack.fittingSize.height
        let statusOriginY = buttonCenterY - (statusHeight / 2.0)
        let editorTopInset = max(TitleBarLayout.editorTopInset, bounds.height - buttonFrame.minY + 12.0)
        return (statusOriginY, leadingReserve, editorTopInset)
    }
}

extension GlassEditorView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        syncEditorLayout(deferHeightInLargeDocuments: true)
        scheduleReconcile()
        onTextDidChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // A non-empty selection means the user is selecting text — don't reconcile.
        // reconcileMath() collapses the selection to a caret, which used to make
        // any selection vanish the instant it was made.
        guard editorTextView.selectedRange().length == 0 else { return }
        scheduleReconcile()
    }

    /// Queues reconcileMath() for the next runloop tick. Mutating the text storage
    /// and forcing layout *inside* the change/selection notifications corrupts the
    /// layout manager (crash in _fillLayoutHoleForCharacterRange), so the actual
    /// work is always done just after the notification returns. Coalesced.
    private func scheduleReconcile() {
        guard !reconcilePending, !isReconciling, !isProcessingMath else { return }
        reconcilePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconcilePending = false
            self.reconcileMath()
        }
    }

    /// AppKit's automatic substitutions follow the user's System Settings, and on a stock
    /// Mac several of them are on: smart quotes and dashes turn `--` into `–`, spelling
    /// correction can "fix" a command name like `\\frac`, text replacement can expand a
    /// shortcut. That's welcome in prose and destructive in LaTeX source, which has to
    /// reach the file exactly as typed — so they are switched off for any check that
    /// touches a `$$…$$` span and left alone everywhere else.
    func textView(
        _ view: NSTextView,
        willCheckTextIn range: NSRange,
        options: [NSSpellChecker.OptionKey: Any] = [:],
        types checkingTypes: UnsafeMutablePointer<NSTextCheckingTypes>
    ) -> [NSSpellChecker.OptionKey: Any] {
        if rangeTouchesFormulaSource(range) {
            let rewriting: NSTextCheckingResult.CheckingType = [.quote, .dash, .correction, .replacement]
            checkingTypes.pointee &= ~rewriting.rawValue
        }
        return options
    }

    /// Whether `range` overlaps formula *source*. Rendered formulas are attachments, not
    /// text, so the only `$$…$$` spans the parser finds are the ones still being edited
    /// (or all of them, when rendering is switched off).
    private func rangeTouchesFormulaSource(_ range: NSRange) -> Bool {
        guard let storage = editorTextView.textStorage else { return false }
        return MathSyntax.completeSpans(in: storage.string as NSString).contains {
            NSIntersectionRange($0, range).length > 0 || NSLocationInRange(range.location, $0)
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isProcessingMath else { return true }
        // The ONLY automatic behaviour: typing the second "$" of an unescaped "$$"
        // *outside* a formula queues an auto-inserted closing "$$". Typing "$$"
        // *inside* a formula is left alone — the parser then closes it there.
        if replacementString == "$", affectedCharRange.length == 0, mathEditRange == nil, settings.renderInlineFormulas {
            let loc = affectedCharRange.location
            let ns = textView.string as NSString
            if loc >= 1, ns.substring(with: NSRange(location: loc - 1, length: 1)) == "$",
               !MathSyntax.isEscaped(ns, loc - 1) {
                pendingAutoCloseAt = loc + 1
            }
        }
        return true
    }
}

// MARK: - Inline LaTeX editing logic
//
// Model: a formula in source form is a paired "$$latex$$" span; rendered form
// is a MathAttachment. Typing "$$" auto-inserts the closing "$$" and drops the
// caret between them. Enter / arrow-out / click-away commits to an attachment;
// clicking an attachment (or a leftover raw span) re-opens it for editing.

extension GlassEditorView: MathEditingHost {
    // MARK: Key handling — each just moves the caret; reconcileMath() renders.

    /// → at the latex end steps out past the closing "$$" (commits the formula).
    func mathExitRight() -> Bool {
        guard let r = mathEditRange,
              editorTextView.selectedRange().location >= r.location + r.length - 2 else { return false }
        editorTextView.setSelectedRange(NSRange(location: r.location + r.length, length: 0))
        return true
    }

    /// ← at the latex start steps out before the opening "$$" (commits the formula).
    func mathExitLeft() -> Bool {
        guard let r = mathEditRange,
              editorTextView.selectedRange().location <= r.location + 2 else { return false }
        editorTextView.setSelectedRange(NSRange(location: r.location, length: 0))
        return true
    }

    /// Arrowing into a rendered formula opens it for editing, caret at the latex
    /// start when arriving from the left (→) or the end when arriving from the
    /// right (←). A direct mutation (safe here — this is a key command, not a
    /// notification callback).
    func mathEnterAttachment(fromLeft: Bool) -> Bool {
        guard mathEditRange == nil, let storage = editorTextView.textStorage else { return false }
        let caret = editorTextView.selectedRange().location
        let idx = fromLeft ? caret : caret - 1
        guard idx >= 0, idx < storage.length,
              storage.attribute(.attachment, at: idx, effectiveRange: nil) is MathAttachment else { return false }
        isProcessingMath = true
        expandMathAttachment(at: NSRange(location: idx, length: 1), caretAtStart: fromLeft)
        isProcessingMath = false
        mathEditRange = MathSyntax.activeSpan(in: storage.string as NSString, caret: editorTextView.selectedRange().location)
        applyMathHighlight()
        updateMathPreview()
        syncEditorLayout()
        return true
    }

    /// A click on a rendered formula opens it and drops the caret at the latex
    /// character nearest the click. SwiftMath doesn't map glyphs back to source, so
    /// this is a proportional estimate (fraction of the image width → fraction of
    /// the latex string) — approximate, but it tracks where you clicked.
    func mathClick(at point: NSPoint) -> Bool {
        guard mathEditRange == nil,
              let storage = editorTextView.textStorage,
              let lm = editorTextView.layoutManager,
              let tc = editorTextView.textContainer else { return false }
        let origin = editorTextView.textContainerOrigin
        let p = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var frac: CGFloat = 0
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let charIdx = lm.characterIndexForGlyph(at: glyph)
        guard charIdx >= 0, charIdx < storage.length,
              let att = storage.attribute(.attachment, at: charIdx, effectiveRange: nil) as? MathAttachment else { return false }
        if editorTextView.window?.firstResponder !== editorTextView {
            editorTextView.window?.makeFirstResponder(editorTextView)
        }
        let latexCount = (att.latex as NSString).length
        let offset = min(latexCount, max(0, Int((CGFloat(latexCount) * frac).rounded())))
        isProcessingMath = true
        expandMathAttachment(at: NSRange(location: charIdx, length: 1), caretAtStart: true)
        editorTextView.setSelectedRange(NSRange(location: charIdx + 2 + offset, length: 0))
        isProcessingMath = false
        mathEditRange = MathSyntax.activeSpan(in: storage.string as NSString, caret: editorTextView.selectedRange().location)
        applyMathHighlight()
        updateMathPreview()
        syncEditorLayout()
        return true
    }

    /// ⌫ right after the opening "$$" unwraps the formula: both delimiters go and
    /// the content stays as plain text (so an empty formula simply disappears).
    func mathDeleteBackwardAtStart() -> Bool {
        guard let r = mathEditRange, let storage = editorTextView.textStorage,
              r.location + r.length <= storage.length,
              editorTextView.selectedRange().location == r.location + 2 else { return false }
        let content = MathSyntax.latex(of: r, in: storage.string as NSString)
        isProcessingMath = true
        storage.replaceCharacters(in: r, with: NSAttributedString(
            string: content, attributes: [.font: editorFont, .foregroundColor: settings.editorTextColor]))
        mathEditRange = nil
        hideMathPreview()
        clearMathHighlight()
        editorTextView.setSelectedRange(NSRange(location: r.location, length: 0))
        isProcessingMath = false
        syncEditorLayout()
        return true
    }

    // MARK: Reconciliation — the single source of truth.

    /// Makes the storage match the parse after any text/selection change: the one
    /// complete span the caret is inside stays raw (editable); every other complete
    /// span becomes a rendered image (empty → removed, invalid → left as raw). The
    /// caret is remapped across each replacement. Idempotent and re-entrancy-safe.
    private func reconcileMath() {
        guard !isReconciling, !isProcessingMath, let storage = editorTextView.textStorage else { return }
        guard settings.renderInlineFormulas else {
            if mathEditRange != nil { mathEditRange = nil; hideMathPreview(); clearMathHighlight() }
            return
        }
        // Never touch a live selection. The setSelectedRange below collapses to a
        // caret, so running this while the user has text selected would wipe the
        // selection out from under them.
        guard editorTextView.selectedRange().length == 0 else { return }

        isReconciling = true
        isProcessingMath = true
        defer { isProcessingMath = false; isReconciling = false }

        applyPendingAutoClose()

        // Caret on a rendered formula → expand it to raw source for editing. If the
        // caret is at/left of the image the caret goes to the latex start, otherwise
        // to the latex end (so it lands near where the click/caret was).
        let sel = editorTextView.selectedRange()
        if sel.length <= 1, let attRange = mathAttachmentRange(near: sel) {
            expandMathAttachment(at: attRange, caretAtStart: sel.location <= attRange.location)
        }

        // Render every complete span the caret is NOT inside (right→left keeps the
        // earlier spans' indices valid; the caret is remapped across each render).
        // One parse serves the whole pass — it walks the entire document, so doing it
        // three times per keystroke (as this used to) is the single most expensive
        // thing here after layout.
        var caret = editorTextView.selectedRange().location
        let spans = MathSyntax.completeSpans(in: storage.string as NSString)
        let active = MathSyntax.activeSpan(in: spans, caret: caret)
        var didRender = false
        for span in spans.reversed() where !(active.map { NSEqualRanges($0, span) } ?? false) {
            guard let remapped = renderSpan(span, caret: caret) else { continue }
            caret = remapped
            didRender = true
        }
        editorTextView.setSelectedRange(NSRange(location: max(0, min(caret, storage.length)), length: 0))

        // Refresh the editing state/preview for wherever the caret ended up. Re-parsing
        // is only needed when a span was actually replaced by an image above.
        let finalCaret = editorTextView.selectedRange().location
        mathEditRange = didRender
            ? MathSyntax.activeSpan(in: storage.string as NSString, caret: finalCaret)
            : MathSyntax.activeSpan(in: spans, caret: finalCaret)
        if mathEditRange != nil {
            applyMathHighlight()
            updateMathPreview()
        } else {
            hideMathPreview()
            clearMathHighlight()
        }
        syncEditorLayout(deferHeightInLargeDocuments: true)
    }

    /// The only automatic edit: after a just-typed opening "$$", insert the closing
    /// "$$" and leave the caret between them.
    private func applyPendingAutoClose() {
        guard let pos = pendingAutoCloseAt else { return }
        pendingAutoCloseAt = nil
        guard let storage = editorTextView.textStorage else { return }
        let caret = editorTextView.selectedRange().location
        let ns = storage.string as NSString
        guard caret == pos, caret >= 2, caret <= ns.length,
              ns.substring(with: NSRange(location: caret - 2, length: 2)) == "$$",
              !MathSyntax.isEscaped(ns, caret - 2) else { return }
        storage.replaceCharacters(in: NSRange(location: caret, length: 0), with: NSAttributedString(
            string: "$$", attributes: [.font: editorFont, .foregroundColor: settings.editorTextColor]))
        editorTextView.setSelectedRange(NSRange(location: caret, length: 0))   // between $$|$$
    }

    /// Replaces one complete raw span with its rendered image (empty → removed,
    /// invalid → left untouched). Returns the caret remapped across the change, or nil
    /// if the storage was left untouched.
    private func renderSpan(_ span: NSRange, caret: Int) -> Int? {
        guard let storage = editorTextView.textStorage,
              span.location + span.length <= storage.length else { return nil }
        // Store the EXACT content between the delimiters (no trimming) so the source
        // round-trips byte-for-byte — the app must never silently edit the text.
        let raw = MathSyntax.latex(of: span, in: storage.string as NSString)
        let newLength: Int
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            storage.replaceCharacters(in: span, with: "")
            newLength = 0
        } else if let base = MathRenderer.renderInlineBase(latex: raw, fontSize: settings.editorFontSize) {
            storage.replaceCharacters(in: span, with: NSAttributedString(
                attachment: MathAttachment(latex: raw, baseImage: base, font: editorFont, tint: currentFormulaTint, shadow: settings.editorTextShadow)))
            newLength = 1
        } else {
            return nil   // invalid LaTeX → leave the raw source in place
        }
        return remapCaret(caret, across: span, newLength: newLength)
    }

    /// Maps a caret across replacing `r` (length r.length) with `newLength` chars.
    private func remapCaret(_ caret: Int, across r: NSRange, newLength: Int) -> Int {
        if caret <= r.location { return caret }
        if caret >= r.location + r.length { return caret + (newLength - r.length) }
        return r.location + newLength
    }

    /// A math attachment touching the caret — the char at the caret (to its right)
    /// or the char just before it (to its left), so a click/caret anywhere on a
    /// rendered formula finds it, not only at its left edge.
    private func mathAttachmentRange(near sel: NSRange) -> NSRange? {
        guard let storage = editorTextView.textStorage else { return nil }
        for idx in [sel.location, sel.location - 1] where idx >= 0 && idx < storage.length {
            if storage.attribute(.attachment, at: idx, effectiveRange: nil) is MathAttachment {
                return NSRange(location: idx, length: 1)
            }
        }
        return nil
    }

    /// Replaces a rendered attachment with its raw "$$latex$$" source and drops the
    /// caret at the latex start or end. A plain mutation — reconcileMath() (or the
    /// arrow handler) wraps it in the guards and does the follow-up layout/preview.
    private func expandMathAttachment(at range: NSRange, caretAtStart: Bool) {
        guard let storage = editorTextView.textStorage,
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? MathAttachment else { return }
        let source = "$$\(att.latex)$$"
        storage.replaceCharacters(in: range, with: NSAttributedString(string: source, attributes: [
            .font: editorFont,
            .foregroundColor: settings.editorTextColor
        ]))
        let caret = caretAtStart ? range.location + 2 : range.location + (source as NSString).length - 2
        editorTextView.setSelectedRange(NSRange(location: caret, length: 0))
    }

    private func updateMathPreview() {
        guard let r = mathEditRange else { hideMathPreview(); return }
        applyMathHighlight()
        let latex = MathSyntax.latex(of: r, in: editorTextView.string as NSString).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = latex.isEmpty ? nil
            : MathRenderer.renderImage(latex: latex, fontSize: max(settings.editorFontSize + 6.0, 22.0), color: .white)
        mathPreview.setImage(base, tint: currentFormulaTint)
        let size = mathPreview.contentSize(for: base)
        positionMathPreview(belowFormulaRange: mathEditRange!, size: size)
        mathPreview.isHidden = false
    }

    private func hideMathPreview() {
        mathPreview.isHidden = true
        mathPreview.setImage(nil, tint: .white)
    }

    /// Greys the editable "$$…$$" source so it stands out from the surrounding
    /// (white-with-accent) text — no background plate, the opaque grey is enough.
    ///
    /// Only the ranges whose colour actually changes are touched. Rewriting the
    /// attribute across the whole document (what this used to do, on every keystroke)
    /// invalidates the layout of the whole document along with it.
    private static let mathSourceColor = NSColor(calibratedWhite: 0.72, alpha: 1.0)

    private func applyMathHighlight() { setMathHighlight(to: mathEditRange) }

    private func clearMathHighlight() { setMathHighlight(to: nil) }

    private func setMathHighlight(to range: NSRange?) {
        guard let storage = editorTextView.textStorage else { return }
        let length = storage.length
        let target = range.flatMap { clamp($0, to: length) }
        if let previous = highlightedMathRange.flatMap({ clamp($0, to: length) }) {
            storage.addAttribute(.foregroundColor, value: settings.editorTextColor, range: previous)
        }
        if let target {
            storage.addAttribute(.foregroundColor, value: Self.mathSourceColor, range: target)
        }
        highlightedMathRange = target
    }

    /// The part of `range` that still exists in a storage of `length` characters — the
    /// remembered highlight can be stale after the text around it was edited.
    private func clamp(_ range: NSRange, to length: Int) -> NSRange? {
        let location = min(range.location, length)
        let clampedLength = min(range.length, length - location)
        return clampedLength > 0 ? NSRange(location: location, length: clampedLength) : nil
    }

    private func positionMathPreview(belowFormulaRange r: NSRange, size: NSSize) {
        guard let lm = editorTextView.layoutManager, let tc = editorTextView.textContainer,
              let storage = editorTextView.textStorage, r.location + r.length <= storage.length else { return }
        // Force layout for the formula's glyphs before measuring: right after a text
        // mutation the layout may not be ready, and boundingRect would return a zero
        // rect → the panel jumped to the top-left corner (bug #10).
        lm.ensureLayout(forCharacterRange: r)
        let glyphRange = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        guard rect.width > 0.5, rect.height > 0.5 else { return }   // not laid out yet → keep last position
        let origin = editorTextView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        let rectInHost = editorTextView.convert(rect, to: contentHost)

        let area = editorScrollView.frame
        var x = rectInHost.minX
        if x + size.width > area.maxX { x = area.maxX - size.width }
        if x < area.minX { x = area.minX }
        // contentHost is not flipped (y grows upward) → "below the line" = smaller y.
        var y = rectInHost.minY - size.height - 8.0
        if y < area.minY { y = rectInHost.maxY + 8.0 }   // no room below → place above
        mathPreview.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Re-tints every rendered formula to `color` (cheap bitmap retint, no LaTeX
    /// re-layout) so formulas cycle hue with Rainbow alongside the text. Both layers
    /// draw the same attachment objects, so one pass updates them both.
    private func recolorFormulas(to color: NSColor) {
        guard let storage = editorTextView.textStorage else { return }
        let shadow = settings.editorTextShadow
        let full = NSRange(location: 0, length: storage.length)
        var didTint = false
        var sizeChanged = false
        storage.enumerateAttribute(.attachment, in: full, options: []) { value, _, _ in
            guard let att = value as? MathAttachment else { return }
            let before = att.image?.size
            att.applyTint(color, shadow: shadow)
            if att.image?.size != before { sizeChanged = true }
            didTint = true
        }
        guard didTint else { return }
        // Baking the halo changes the attachment image size; the layout managers cache
        // glyph metrics, so a size change needs an explicit relayout. Skipped when only
        // the tint changed (e.g. every Rainbow frame) so that path stays cheap.
        if sizeChanged {
            for manager in storage.layoutManagers {
                manager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
                if let container = manager.textContainers.first { manager.ensureLayout(for: container) }
            }
        }
        editorTextView.needsDisplay = true
        backdropTextView.needsDisplay = true
    }

}

// MARK: - Find & replace
//
// The bar itself and the searching live in FindBar.swift; this is where the editor hosts
// it. Edit ▸ Find sends performFindBarAction(_:) up the responder chain — from the text
// view or from the bar's own fields alike — with an NSTextFinder.Action as the tag.

extension GlassEditorView: NSMenuItemValidation {
    @objc func performFindBarAction(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        findController().perform(action)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performFindBarAction(_:)) else { return true }
        if item.tag == NSTextFinder.Action.setSearchString.rawValue {
            return editorTextView.selectedRange().length > 0
        }
        return true
    }

    private func findController() -> EditorFindController {
        if let finder { return finder }
        let controller = EditorFindController(textView: editorTextView)
        controller.revealRange = { [weak self] in self?.revealFoundRange($0) }
        controller.onLayoutChange = { [weak self] in self?.layoutFindBar() }
        contentHost.addSubview(controller.bar)
        finder = controller
        return controller
    }

    /// The bar floats over the top-right corner of the text.
    private func layoutFindBar() {
        guard let bar = finder?.bar, !bar.isHidden else { return }
        let area = editorScrollView.frame
        let size = bar.preferredSize
        let width = min(size.width, area.width - 16.0)
        bar.frame = NSRect(x: area.maxX - width - 8.0, y: area.maxY - size.height - 2.0,
                           width: width, height: size.height)
    }

    /// Scrolls a found match into view, clear of the bar and of the faded edges.
    private func revealFoundRange(_ range: NSRange) {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer,
              let storage = editorTextView.textStorage, NSMaxRange(range) <= storage.length else { return }
        layoutManager.ensureLayout(forCharacterRange: range)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = editorTextView.textContainerOrigin
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: origin.x, dy: origin.y)
        // A large document's height is measured lazily and may not reach the match yet.
        if rect.maxY > editorContentView.frame.height { syncEditorLayout() }

        var barClearance: CGFloat = 0.0
        if let bar = finder?.bar, !bar.isHidden {
            barClearance = max(0.0, editorScrollView.frame.maxY - bar.frame.minY)
        }
        rect = rect.insetBy(dx: -24.0, dy: -(EdgeFadeMaskLayer.fadeHeight + 4.0))
        rect.origin.y -= barClearance           // the text view is flipped: this is "up"
        rect.size.height += barClearance
        editorTextView.scrollToVisible(rect)
    }
}
