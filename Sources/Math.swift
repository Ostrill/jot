//
//  Math.swift
//  Inline LaTeX: syntax parser, renderer, attachment, live preview.
//

import AppKit

// MARK: - Inline LaTeX math rendering

/// The single parser for `$$…$$` formula syntax, used everywhere (file load,
/// serialization, and live editing) so behaviour is identical. A formula is any
/// text between an unescaped `$$` pair; `\$` is a literal dollar (also valid
/// LaTeX). Pairing is greedy, left→right, non-overlapping.
enum MathSyntax {
    private static let dollar: unichar = 0x24
    private static let backslash: unichar = 0x5C

    /// A `$` at `idx` is escaped iff preceded by an odd run of backslashes.
    static func isEscaped(_ ns: NSString, _ idx: Int) -> Bool {
        var count = 0
        var j = idx - 1
        while j >= 0, ns.character(at: j) == backslash { count += 1; j -= 1 }
        return count % 2 == 1
    }

    private static func isEscaped(_ characters: [unichar], _ idx: Int) -> Bool {
        var count = 0
        var j = idx - 1
        while j >= 0, characters[j] == backslash { count += 1; j -= 1 }
        return count % 2 == 1
    }

    /// Ranges of complete `$$…$$` spans (delimiters included), left→right and
    /// non-overlapping. A trailing unmatched `$$` yields no span.
    ///
    /// The characters are copied into a flat buffer first and scanned there:
    /// `NSString.character(at:)` is an Objective-C message per character, and this
    /// parse runs on every keystroke over the whole document.
    static func completeSpans(in ns: NSString) -> [NSRange] {
        let length = ns.length
        guard length > 3 else { return [] }
        var characters = [unichar](repeating: 0, count: length)
        ns.getCharacters(&characters, range: NSRange(location: 0, length: length))

        var spans: [NSRange] = []
        var openAt: Int?
        var i = 0
        while i + 1 < length {
            guard characters[i] == dollar, characters[i + 1] == dollar, !isEscaped(characters, i) else {
                i += 1
                continue
            }
            if let open = openAt {
                spans.append(NSRange(location: open, length: i + 2 - open))
                openAt = nil
            } else {
                openAt = i
            }
            i += 2
        }
        return spans
    }

    /// The latex content between a span's `$$…$$` delimiters.
    static func latex(of span: NSRange, in ns: NSString) -> String {
        ns.substring(with: NSRange(location: span.location + 2, length: span.length - 4))
    }

    /// The complete span whose interior contains `caret` (strictly between the
    /// delimiters), i.e. the formula currently being edited — if any.
    static func activeSpan(in spans: [NSRange], caret: Int) -> NSRange? {
        spans.first { caret > $0.location && caret < $0.location + $0.length }
    }

    static func activeSpan(in ns: NSString, caret: Int) -> NSRange? {
        activeSpan(in: completeSpans(in: ns), caret: caret)
    }
}

enum MathRenderer {
    /// Transparent margin baked around inline formula images (x = horizontal,
    /// y = vertical) so neighbouring text and the next line aren't flush against
    /// the glyphs. Tweak to taste.
    static let inlinePadding = NSSize(width: 2.0, height: 4.0)

    /// Renders a LaTeX string to an NSImage via SwiftMath. Returns nil on
    /// empty input or parse error.
    static func renderImage(latex: String, fontSize: CGFloat, color: NSColor) -> NSImage? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let mathImage = MTMathImage(latex: trimmed, fontSize: fontSize, textColor: color, labelMode: .display)
        let (error, image) = mathImage.asImage()
        guard error == nil, let image else { return nil }
        return image
    }

    /// White base image for an inline formula attachment: rendered glyphs plus
    /// transparent padding. Recolored later to follow the text tint.
    static func renderInlineBase(latex: String, fontSize: CGFloat) -> NSImage? {
        renderImage(latex: latex, fontSize: fontSize, color: .white)?
            .padded(dx: inlinePadding.width, dy: inlinePadding.height)
    }
}

extension NSImage {
    /// Recolors a single-color glyph image to `color`, keeping the shape's alpha.
    /// Cheap (one offscreen draw, no LaTeX re-layout) so formula tint can follow
    /// the Rainbow animation without re-running SwiftMath every frame.
    ///
    /// Draws the shape first, then fills the color with `.sourceAtop` so the tint
    /// lands only where the shape is opaque. (Filling the whole rect and masking
    /// with `.destinationIn` instead left a colored 1px strip on the top/right
    /// edges where the masking draw under-covered the fractional-size canvas.)
    func recolored(to color: NSColor) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        color.setFill()
        rect.fill()
        result.unlockFocus()
        return result
    }

    /// Returns a copy with transparent margins (`dx` left/right, `dy` top/bottom)
    /// so inline formulas aren't flush against neighbouring text and lines.
    func padded(dx: CGFloat, dy: CGFloat) -> NSImage {
        let result = NSImage(size: NSSize(width: size.width + dx * 2.0, height: size.height + dy * 2.0))
        result.lockFocus()
        draw(in: NSRect(x: dx, y: dy, width: size.width, height: size.height),
             from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Returns a copy enlarged by `padding` on every side with a soft dark halo (from
    /// `shadow`) drawn behind the opaque glyphs — the image equivalent of the text's
    /// `.shadow`, so a rendered formula stays legible over any backdrop. No-op when
    /// there's no padding/shadow.
    func haloed(shadow: NSShadow, padding: CGFloat) -> NSImage {
        guard padding > 0.0, shadow.shadowColor != nil else { return self }
        let result = NSImage(size: NSSize(width: size.width + padding * 2.0, height: size.height + padding * 2.0))
        result.lockFocus()
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        draw(in: NSRect(x: padding, y: padding, width: size.width, height: size.height),
             from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        result.unlockFocus()
        return result
    }
}

/// A rendered formula embedded inline in the text. Stores its LaTeX source so
/// it can be expanded back into an editable `$$…` span and serialized on save,
/// plus a white base image so its tint can be re-applied cheaply (Rainbow).
final class MathAttachment: NSTextAttachment {
    let latex: String
    private let baseImage: NSImage          // white shape, kept for cheap retinting
    private let fontMid: CGFloat            // text mid-line, to re-centre when the size changes
    private var verticalOffset: CGFloat = 0.0
    private var renderedSize: NSSize = .zero

    init(latex: String, baseImage: NSImage, font: NSFont, tint: NSColor, shadow: NSShadow) {
        self.latex = latex
        self.baseImage = baseImage
        // Center the formula image vertically on the text's mid-line.
        self.fontMid = (font.ascender + font.descender) / 2.0
        super.init(data: nil, ofType: nil)
        applyTint(tint, shadow: shadow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Re-tints the rendered image to `color` and bakes the legibility halo into it:
    /// the layout manager doesn't apply the text `.shadow` attribute to attachment
    /// images, so the glow has to live in the bitmap. The image (and thus the
    /// attachment's size) grows to fit the halo, but the glyph stays centred on the
    /// text mid-line. At shadow-strength 0 there's no padding, so size is unchanged.
    func applyTint(_ color: NSColor, shadow: NSShadow) {
        let pad: CGFloat = shadow.shadowColor == nil ? 0.0 : ceil(shadow.shadowBlurRadius) + 2.0
        let img = baseImage.recolored(to: color).haloed(shadow: shadow, padding: pad)
        self.image = img
        self.renderedSize = img.size
        self.verticalOffset = fontMid - (img.size.height / 2.0)
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        CGRect(x: 0, y: verticalOffset, width: renderedSize.width, height: renderedSize.height)
    }
}

/// Floating glass panel that shows the live-rendered formula while editing.
final class MathPreviewView: NSView {
    private let glass = NSGlassEffectView(frame: .zero)
    private let contentContainer = NSView(frame: .zero)
    private let imageView = NSImageView(frame: .zero)
    private let padding: CGFloat = 22.0
    private var baseImage: NSImage?           // white render, kept so the tint can follow Rainbow

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glass.cornerRadius = 16.0
        // Putting the image in the glass's contentView composites it ON TOP of
        // the glass material (a plain sibling sits behind/under the refraction).
        contentContainer.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        contentContainer.addSubview(imageView)
        glass.contentView = contentContainer
        addSubview(glass)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        glass.frame = bounds
        contentContainer.frame = bounds
        // Generous inset keeps the formula away from the glass edge, where the
        // refraction would otherwise smear its strokes.
        imageView.frame = bounds.insetBy(dx: padding, dy: padding)
    }

    /// Stores the white base render and shows it tinted. Keeping the base lets the
    /// tint be refreshed as Rainbow animates (see applyTint), so the preview never
    /// drifts out of sync with the window colour.
    func setImage(_ base: NSImage?, tint: NSColor) {
        baseImage = base
        imageView.image = base?.recolored(to: tint)
    }

    /// Re-tints the current preview image to `color` (cheap; no re-render).
    func applyTint(_ color: NSColor) {
        imageView.image = baseImage?.recolored(to: color)
    }

    func contentSize(for image: NSImage?) -> NSSize {
        guard let image, image.size.width > 1 else {
            return NSSize(width: 110.0, height: 60.0)
        }
        let maxWidth: CGFloat = 360.0
        var w = image.size.width
        var h = image.size.height
        if w > maxWidth {
            let scale = maxWidth / w
            w *= scale
            h *= scale
        }
        return NSSize(width: w + padding * 2.0, height: h + padding * 2.0)
    }
}
