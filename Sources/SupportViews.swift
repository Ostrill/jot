//
//  SupportViews.swift
//  Small building blocks: window, flipped host, wrap guides, hit shield.
//

import AppKit

final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

final class WrapGuideView: NSView {
    override var isFlipped: Bool { true }
    weak var textView: NSTextView?
    var guideColor: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.16) {
        didSet { needsDisplay = true }
    }
    var guideXOffset: CGFloat = 0.0 {
        didSet { needsDisplay = true }
    }
    var guideThickness: CGFloat = 1.5 {
        didSet { needsDisplay = true }
    }
    var guideTopTrim: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    var guideBottomTrim: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    var roundedCaps = false {
        didSet { needsDisplay = true }
    }
    var isGuideVisible = false {
        didSet {
            isHidden = !isGuideVisible
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard isGuideVisible,
              let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        guideColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = guideThickness
        if roundedCaps {
            path.lineCapStyle = .round
        }

        let string = textView.string as NSString
        let containerOrigin = textView.textContainerOrigin
        let textStartX = containerOrigin.x + textView.textContainerInset.width
        let lineX = max(2.0, floor((textStartX * 0.5) + guideXOffset))

        // Walk only the lines that intersect the area being redrawn. This view is as
        // tall as the whole document, so walking every line would make each repaint
        // cost O(document) — and it repaints on scroll.
        let boundingRect = dirtyRect.offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: boundingRect, in: textContainer)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        guard visibleChars.length > 0 || string.length == 0 else { return }
        // Start at the beginning of the logical line the dirty area starts inside: its
        // guide may begin above the dirty rect and still cross it.
        var index = string.lineRange(for: NSRange(location: min(visibleChars.location, string.length), length: 0)).location
        let limit = NSMaxRange(visibleChars)

        while index < string.length, index <= limit {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var fragments: [CGRect] = []

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                fragments.append(usedRect)
            }

            if fragments.count > 1, let first = fragments.first, let last = fragments.last {
                let startY = containerOrigin.y + first.minY + guideTopTrim
                let endY = containerOrigin.y + last.maxY - guideBottomTrim
                path.move(to: NSPoint(x: lineX, y: startY))
                path.line(to: NSPoint(x: lineX, y: endY))
            }

            index = NSMaxRange(lineRange)
        }

        path.stroke()
    }
}

/// The backdrop text layer: the editor's text drawn a second time underneath the
/// translucent editor glyphs, as a near-opaque sheet in one colour with the legibility
/// halo behind it.
///
/// It shares the editor's `NSTextStorage` through its own layout manager, so it mirrors
/// every edit with nothing to copy and the two layers can never drift apart. It is a
/// plain view rather than a second NSTextView on purpose: a second text view over the
/// same storage brings its own selection, responder and undo machinery along, and that
/// **broke the editor's undo** (verified — ⌘Z stopped reverting anything).
final class BackdropTextView: NSView {
    let layoutManager = BackdropLayoutManager()
    let textContainer: NSTextContainer
    var textContainerInset: NSSize = NSSize(width: 10.0, height: 6.0)

    init(sharing storage: NSTextStorage) {
        textContainer = NSTextContainer(size: NSSize(width: 0.0, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        super.init(frame: .zero)
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.onDisplayInvalidated = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y),
            in: textContainer
        )
        guard glyphRange.length > 0 else { return }
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

/// Forces every glyph to one colour with the legibility halo, ignoring whatever colours
/// the shared storage carries — which is what lets the backdrop hold no attributes of
/// its own. The halo is set on the context here rather than as a `.shadow` attribute so
/// it applies to glyphs only: formula attachments keep the halo baked into their bitmap.
final class BackdropLayoutManager: NSLayoutManager {
    // Both are pure draw-time state — the caller marks the backdrop view for redraw.
    var glyphColor: NSColor = .white
    var glyphShadow: NSShadow?
    /// The layout manager has no text view to ask for a redraw, so it asks its view here.
    var onDisplayInvalidated: (() -> Void)?

    override func invalidateDisplay(forCharacterRange charRange: NSRange) {
        super.invalidateDisplay(forCharacterRange: charRange)
        onDisplayInvalidated?()
    }

    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<CGPoint>,
        count glyphCount: Int,
        font: NSFont,
        textMatrix: CGAffineTransform,
        attributes: [NSAttributedString.Key: Any],
        in graphicsContext: CGContext
    ) {
        graphicsContext.saveGState()
        if let shadow = glyphShadow, let shadowColor = shadow.shadowColor {
            graphicsContext.setShadow(
                offset: shadow.shadowOffset,
                blur: shadow.shadowBlurRadius,
                color: shadowColor.cgColor
            )
        }
        graphicsContext.setFillColor(glyphColor.cgColor)
        super.showCGGlyphs(
            glyphs, positions: positions, count: glyphCount, font: font,
            textMatrix: textMatrix, attributes: attributes, in: graphicsContext
        )
        graphicsContext.restoreGState()
    }
}

/// Softens the top and bottom edges of the scrolled text, so a document doesn't end in a
/// hard cut against the glass. It is an alpha gradient used as the viewport's mask, and
/// each edge only fades in once there is actually text hidden past it — a document that
/// fits in the window is not faded at all.
final class EdgeFadeMaskLayer: CAGradientLayer {
    static let fadeHeight: CGFloat = 26.0

    override init() {
        super.init()
        startPoint = CGPoint(x: 0.5, y: 0.0)
        endPoint = CGPoint(x: 0.5, y: 1.0)
        actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull(), "locations": NSNull()]
        update(topHidden: 0.0, bottomHidden: 0.0, viewportHeight: 0.0)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `topHidden`/`bottomHidden` are how much content is scrolled out of view on each
    /// side; the fade ramps in over the first `fadeHeight` points of it.
    func update(topHidden: CGFloat, bottomHidden: CGFloat, viewportHeight: CGFloat) {
        let height = max(viewportHeight, 1.0)
        let fade = min(Self.fadeHeight, height / 3.0)
        let top = min(max(topHidden, 0.0) / Self.fadeHeight, 1.0)
        let bottom = min(max(bottomHidden, 0.0) / Self.fadeHeight, 1.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colors = [
            NSColor(calibratedWhite: 1.0, alpha: 1.0 - top).cgColor,
            NSColor(calibratedWhite: 1.0, alpha: 1.0).cgColor,
            NSColor(calibratedWhite: 1.0, alpha: 1.0).cgColor,
            NSColor(calibratedWhite: 1.0, alpha: 1.0 - bottom).cgColor
        ]
        locations = [0.0, NSNumber(value: Double(fade / height)),
                     NSNumber(value: Double(1.0 - fade / height)), 1.0]
        CATransaction.commit()
    }
}

final class HitTestShieldView: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }
}
