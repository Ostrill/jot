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
              textView.textContainer != nil else {
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
        var index = 0

        while index < string.length {
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

/// Layout manager for the backdrop text layer: draws every glyph in one colour with
/// the legibility halo, ignoring whatever colours the storage carries.
///
/// This is what lets the two text layers **share a single NSTextStorage**: the backdrop
/// needs no attributes of its own, so there is nothing to copy on each keystroke and the
/// layers can never drift out of alignment. The halo is set on the context here (rather
/// than as a `.shadow` attribute) so it applies to glyphs only — formula attachments keep
/// the halo baked into their bitmap, exactly as before.
final class BackdropLayoutManager: NSLayoutManager {
    var glyphColor: NSColor = .white {
        didSet { if glyphColor != oldValue { invalidateDisplay(forCharacterRange: fullRange) } }
    }
    var glyphShadow: NSShadow?

    private var fullRange: NSRange {
        NSRange(location: 0, length: textStorage?.length ?? 0)
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

final class HitTestShieldView: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }
}
