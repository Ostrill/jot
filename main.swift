import AppKit
import CoreImage
import UniformTypeIdentifiers

struct PanelSettings {
    enum DocumentIndicatorStyle: Int, CaseIterable {
        case dot
        case star
        case square
        case diamond
        case plus

        var title: String {
            switch self {
            case .dot: return "Dot"
            case .star: return "Star"
            case .square: return "Square"
            case .diamond: return "Diamond"
            case .plus: return "Plus"
            }
        }

        var symbol: String {
            switch self {
            case .dot: return "\u{2022}"
            case .star: return "\u{2736}"
            case .square: return "\u{25AA}"
            case .diamond: return "\u{25C6}"
            case .plus: return "+"
            }
        }
    }

    enum GlassStyle: Int {
        case clear
        case regular

        var appKitStyle: NSGlassEffectView.Style {
            switch self {
            case .clear: return .clear
            case .regular: return .regular
            }
        }
    }

    var glassStyle: GlassStyle = .clear
    var cornerRadius: CGFloat = 30.0
    var tintStrength: CGFloat = 0.0
    var warmth: CGFloat = 0.0
    var fillOpacity: CGFloat = 0.0
    var borderOpacity: CGFloat = 0.05
    var sheenOpacity: CGFloat = 0.01
    var shadowOpacity: CGFloat = 0.0
    var shadowBlur: CGFloat = 0.0
    // The appearance defaults below are the maintainer's calibrated setup, baked in
    // so a fresh install opens looking the same as the reference configuration
    // (rather than the bare AppKit defaults). Kept in sync with the `load` fallbacks.
    var darkeningOpacity: CGFloat = 0.5952995867768595
    var colorStrength: CGFloat = 0.1984762396694215
    var rainbowHue: CGFloat = 0.4089982857132796
    var rainbowEnabled: Bool = true
    var rainbowSpeed: CGFloat = 0.05283514616487946
    var alwaysOnTop: Bool = false
    var editorFontSize: CGFloat = 19.61813446969697
    var textColorStrength: CGFloat = 0.5045408105713924
    var textShadowStrength: CGFloat = 0.1968333431523143   // dark halo behind the text for legibility over any backdrop (0 = off)
    var blurStrength: CGFloat = 0.0
    var menuSliderOffset: CGFloat = 25.0
    var wordWrap: Bool = true
    var showWrapGuides: Bool = true
    var renderInlineFormulas: Bool = true   // render $$…$$ as images (off → plain source text)
    var wrapGuideXOffset: CGFloat = 0.0
    var wrapGuideThickness: CGFloat = 1.5
    var wrapGuideTopTrim: CGFloat = 1.0
    var wrapGuideBottomTrim: CGFloat = 1.0
    var wrapGuideOpacity: CGFloat = 0.18
    var wrapGuideRounded: Bool = false
    var documentIndicatorStyle: DocumentIndicatorStyle = .dot

    var tintColor: NSColor? {
        guard tintStrength > 0.001 else { return nil }

        let warm = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.86, alpha: 1.0)
        let cool = NSColor(calibratedRed: 0.84, green: 0.93, blue: 1.0, alpha: 1.0)
        let neutral = NSColor(calibratedWhite: 0.98, alpha: 1.0)

        let mix = max(-1.0, min(1.0, warmth))
        let baseColor: NSColor

        if mix > 0.001 {
            baseColor = neutral.blended(withFraction: mix, of: warm) ?? warm
        } else if mix < -0.001 {
            baseColor = neutral.blended(withFraction: abs(mix), of: cool) ?? cool
        } else {
            baseColor = neutral
        }

        return baseColor.withAlphaComponent(tintStrength)
    }

    var fillColor: NSColor {
        let alpha = max(0.0, min(1.0, fillOpacity))

        if let tintColor {
            return tintColor.withAlphaComponent(alpha)
        }

        return NSColor(calibratedWhite: 1.0, alpha: alpha)
    }

    var accentColor: NSColor {
        NSColor(
            calibratedHue: max(0.0, min(1.0, rainbowHue)),
            saturation: 0.78,
            brightness: 1.0,
            alpha: max(0.0, min(1.0, colorStrength))
        )
    }

    var dimColor: NSColor {
        NSColor(calibratedWhite: 0.0, alpha: max(0.0, min(0.90, darkeningOpacity)))
    }

    var editorTextColor: NSColor {
        let alpha = 0.56 + (max(0.0, min(1.0, textColorStrength)) * 0.28)
        return NSColor(calibratedWhite: 1.0, alpha: alpha)
    }

    var editorCompositeTextColor: NSColor {
        let alpha = 0.56 + (max(0.0, min(1.0, textColorStrength)) * 0.28)
        return accentReferenceColor.blended(withFraction: alpha, of: .white) ?? .white
    }

    var backdropTextColor: NSColor {
        let reference = accentReferenceColor
        return reference.withAlphaComponent(0.94)
    }

    var selectionColor: NSColor {
        let alpha = 0.16 + (max(0.0, min(1.0, textColorStrength)) * 0.08)
        return NSColor(calibratedWhite: 1.0, alpha: alpha)
    }

    var caretColor: NSColor {
        let reference = accentReferenceColor
        return NSColor.white.blended(withFraction: 0.10, of: reference) ?? .white
    }

    /// A soft, centred dark halo drawn behind the glyphs so the text stays legible
    /// over any backdrop (light or dark) showing through the glass — the subtitle
    /// trick. A single flat colour can't be readable everywhere; this is why. Fully
    /// transparent (no shadow) when the strength is 0.
    var editorTextShadow: NSShadow {
        let s = max(0.0, min(1.0, textShadowStrength))
        let shadow = NSShadow()
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = s <= 0.001 ? 0.0 : 2.0 + (14.0 * s)
        shadow.shadowColor = s <= 0.001 ? nil : NSColor.black.withAlphaComponent(0.6 + (0.4 * s))
        return shadow
    }

    var documentIndicatorColor: NSColor {
        let reference = accentReferenceColor
        return NSColor.white.blended(withFraction: 0.55, of: reference) ?? reference
    }

    var statusTextColor: NSColor {
        editorCompositeTextColor
    }

    private var accentReferenceColor: NSColor {
        if colorStrength > 0.001 {
            return NSColor(calibratedHue: max(0.0, min(1.0, rainbowHue)), saturation: 0.55, brightness: 1.0, alpha: 1.0)
        }

        if let tintColor {
            return tintColor.withAlphaComponent(1.0)
        }

        return NSColor(calibratedWhite: 1.0, alpha: 1.0)
    }

    private static let defaultsKey = "Jot.settings"
    private static let legacyDefaultsKey = "GlassPanel.settings"

    init() {}

    init(defaults: UserDefaults) {
        let key: String
        if defaults.dictionary(forKey: Self.defaultsKey) != nil {
            key = Self.defaultsKey
        } else if defaults.dictionary(forKey: Self.legacyDefaultsKey) != nil {
            key = Self.legacyDefaultsKey
        } else {
            self.init()
            return
        }
        guard let dictionary = defaults.dictionary(forKey: key) else {
            self.init()
            return
        }

        self = PanelSettings()
        self.glassStyle = GlassStyle(rawValue: dictionary["glassStyle"] as? Int ?? GlassStyle.clear.rawValue) ?? .clear
        self.cornerRadius = CGFloat(dictionary["cornerRadius"] as? Double ?? 30.0)
        self.tintStrength = CGFloat(dictionary["tintStrength"] as? Double ?? 0.0)
        self.warmth = CGFloat(dictionary["warmth"] as? Double ?? 0.0)
        self.fillOpacity = CGFloat(dictionary["fillOpacity"] as? Double ?? 0.0)
        self.borderOpacity = CGFloat(dictionary["borderOpacity"] as? Double ?? 0.05)
        self.sheenOpacity = CGFloat(dictionary["sheenOpacity"] as? Double ?? 0.01)
        self.shadowOpacity = CGFloat(dictionary["shadowOpacity"] as? Double ?? 0.0)
        self.shadowBlur = CGFloat(dictionary["shadowBlur"] as? Double ?? 0.0)
        self.darkeningOpacity = CGFloat(dictionary["darkeningOpacity"] as? Double ?? 0.5952995867768595)
        self.colorStrength = CGFloat(dictionary["colorStrength"] as? Double ?? 0.1984762396694215)
        self.rainbowHue = CGFloat(dictionary["rainbowHue"] as? Double ?? 0.4089982857132796)
        self.rainbowEnabled = dictionary["rainbowEnabled"] as? Bool ?? true
        self.rainbowSpeed = CGFloat(dictionary["rainbowSpeed"] as? Double ?? 0.05283514616487946)
        self.alwaysOnTop = dictionary["alwaysOnTop"] as? Bool ?? false
        self.editorFontSize = CGFloat(dictionary["editorFontSize"] as? Double ?? 19.61813446969697)
        self.textColorStrength = CGFloat(dictionary["textColorStrength"] as? Double ?? 0.5045408105713924)
        self.textShadowStrength = CGFloat(dictionary["textShadowStrength"] as? Double ?? 0.1968333431523143)
        self.blurStrength = CGFloat(dictionary["blurStrength"] as? Double ?? 0.0)
        self.menuSliderOffset = CGFloat(dictionary["menuSliderOffset"] as? Double ?? 25.0)
        self.wordWrap = dictionary["wordWrap"] as? Bool ?? true
        self.showWrapGuides = dictionary["showWrapGuides"] as? Bool ?? true
        self.renderInlineFormulas = dictionary["renderInlineFormulas"] as? Bool ?? true
        self.wrapGuideXOffset = CGFloat(dictionary["wrapGuideXOffset"] as? Double ?? 0.0)
        self.wrapGuideThickness = CGFloat(dictionary["wrapGuideThickness"] as? Double ?? 1.5)
        self.wrapGuideTopTrim = CGFloat(dictionary["wrapGuideTopTrim"] as? Double ?? 1.0)
        self.wrapGuideBottomTrim = CGFloat(dictionary["wrapGuideBottomTrim"] as? Double ?? 1.0)
        self.wrapGuideOpacity = CGFloat(dictionary["wrapGuideOpacity"] as? Double ?? 0.18)
        self.wrapGuideRounded = dictionary["wrapGuideRounded"] as? Bool ?? false
        self.documentIndicatorStyle = DocumentIndicatorStyle(rawValue: dictionary["documentIndicatorStyle"] as? Int ?? DocumentIndicatorStyle.dot.rawValue) ?? .dot
    }

    func save(to defaults: UserDefaults) {
        defaults.set([
            "glassStyle": glassStyle.rawValue,
            "cornerRadius": cornerRadius,
            "tintStrength": tintStrength,
            "warmth": warmth,
            "fillOpacity": fillOpacity,
            "borderOpacity": borderOpacity,
            "sheenOpacity": sheenOpacity,
            "shadowOpacity": shadowOpacity,
            "shadowBlur": shadowBlur,
            "darkeningOpacity": darkeningOpacity,
            "colorStrength": colorStrength,
            "rainbowHue": rainbowHue,
            "rainbowEnabled": rainbowEnabled,
            "rainbowSpeed": rainbowSpeed,
            "alwaysOnTop": alwaysOnTop,
            "editorFontSize": editorFontSize,
            "textColorStrength": textColorStrength,
            "textShadowStrength": textShadowStrength,
            "blurStrength": blurStrength,
            "menuSliderOffset": menuSliderOffset,
            "wordWrap": wordWrap,
            "showWrapGuides": showWrapGuides,
            "renderInlineFormulas": renderInlineFormulas,
            "wrapGuideXOffset": wrapGuideXOffset,
            "wrapGuideThickness": wrapGuideThickness,
            "wrapGuideTopTrim": wrapGuideTopTrim,
            "wrapGuideBottomTrim": wrapGuideBottomTrim,
            "wrapGuideOpacity": wrapGuideOpacity,
            "wrapGuideRounded": wrapGuideRounded,
            "documentIndicatorStyle": documentIndicatorStyle.rawValue
        ], forKey: Self.defaultsKey)
    }
}

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

final class HitTestShieldView: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }
}

/// Implemented by GlassEditorView to drive inline LaTeX editing from key events.
protocol MathEditingHost: AnyObject {
    var isEditingMath: Bool { get }
    func mathExitRight() -> Bool               // →  at latex end steps out past the closing "$$"
    func mathExitLeft() -> Bool                // ←  at latex start steps out before the opening "$$"
    func mathEnterAttachment(fromLeft: Bool) -> Bool   // →/← into a rendered formula opens it
    func mathClick(at point: NSPoint) -> Bool          // click a rendered formula → open at the click
    func mathDeleteBackwardAtStart() -> Bool   // ⌫ at the opening "$$" unwraps the formula
}

final class EditorTextView: NSTextView {
    weak var mathHost: MathEditingHost?

    private enum KeyCode {
        static let a: UInt16 = 0
        static let z: UInt16 = 6
        static let x: UInt16 = 7
        static let c: UInt16 = 8
        static let v: UInt16 = 9
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if modifiers == [.command] {
            switch keyCode {
            case KeyCode.a:
                selectAll(nil)
                return true
            case KeyCode.z:
                undoManager?.undo()
                return true
            case KeyCode.x:
                cut(nil)
                return true
            case KeyCode.c:
                copy(nil)
                return true
            case KeyCode.v:
                paste(nil)
                return true
            default:
                break
            }
        }

        if modifiers == [.command, .shift], keyCode == KeyCode.z {
            undoManager?.redo()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            updateInsertionPointStateAndRestartTimer(true)
            // A second restart on the next runloop tick ensures the blink timer
            // starts even when becomeFirstResponder fires before the window has
            // fully settled its key state (e.g. right after sheet dismissal).
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window?.firstResponder === self else { return }
                self.updateInsertionPointStateAndRestartTimer(true)
            }
        }
        return became
    }

    // Arrow / delete keys drive the formula edit lifecycle. Each just repositions
    // the caret; reconcileMath() (on the resulting selection change) does the
    // rendering. Enter is deliberately NOT intercepted, so it inserts a newline
    // inside the formula source — multi-line formulas (LaTeX "\\") are supported.
    override func moveRight(_ sender: Any?) {
        if let host = mathHost, host.mathExitRight() || host.mathEnterAttachment(fromLeft: true) { return }
        super.moveRight(sender)
    }

    override func moveLeft(_ sender: Any?) {
        if let host = mathHost, host.mathExitLeft() || host.mathEnterAttachment(fromLeft: false) { return }
        super.moveLeft(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if let host = mathHost, host.mathDeleteBackwardAtStart() { return }
        super.deleteBackward(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let host = mathHost, host.mathClick(at: point) { return }
        super.mouseDown(with: event)
    }
}

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

    /// Start indices of every unescaped `$$` delimiter, left→right.
    static func delimiters(in ns: NSString) -> [Int] {
        var result: [Int] = []
        var i = 0
        while i + 1 < ns.length {
            if ns.character(at: i) == dollar, ns.character(at: i + 1) == dollar, !isEscaped(ns, i) {
                result.append(i)
                i += 2
            } else {
                i += 1
            }
        }
        return result
    }

    /// Ranges of complete `$$…$$` spans (delimiters included). A trailing
    /// unmatched `$$` yields no span.
    static func completeSpans(in ns: NSString) -> [NSRange] {
        let d = delimiters(in: ns)
        var spans: [NSRange] = []
        var i = 0
        while i + 1 < d.count {
            spans.append(NSRange(location: d[i], length: d[i + 1] + 2 - d[i]))
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
    static func activeSpan(in ns: NSString, caret: Int) -> NSRange? {
        completeSpans(in: ns).first { caret > $0.location && caret < $0.location + $0.length }
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

final class SliderMenuItemView: NSView {
    private let preferredWidth: CGFloat
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let stackView = NSStackView()
    private let headerRow = NSStackView()

    var formatter: (Double) -> String = { String(format: "%.2f", $0) }
    var onChange: ((Double) -> Void)?
    var horizontalOffset: CGFloat = 12.0 {
        didSet {
            leadingConstraint?.constant = horizontalOffset
            trailingConstraint?.constant = -(16.0 - horizontalOffset)
            needsLayout = true
        }
    }

    init(title: String, minValue: Double, maxValue: Double, initialValue: Double, width: CGFloat = 220.0) {
        self.preferredWidth = width
        super.init(frame: NSRect(x: 0.0, y: 0.0, width: width, height: 44.0))
        titleField.stringValue = title
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = initialValue
        setupView(width: width)
        updateValueLabel()
    }

    required init?(coder: NSCoder) {
        self.preferredWidth = 220.0
        super.init(coder: coder)
        setupView(width: 220.0)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 44.0)
    }

    override var fittingSize: NSSize {
        intrinsicContentSize
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: preferredWidth, height: 44.0))
    }

    var doubleValue: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            updateValueLabel()
        }
    }

    private func setupView(width: CGFloat) {
        frame.size.width = width

        titleField.font = .systemFont(ofSize: 11.0, weight: .medium)
        titleField.textColor = NSColor.labelColor

        valueField.font = .monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        valueField.textColor = NSColor.secondaryLabelColor
        valueField.alignment = .right
        valueField.setContentHuggingPriority(.required, for: .horizontal)

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill
        headerRow.spacing = 10.0
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(titleField)
        headerRow.addArrangedSubview(valueField)

        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 4.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(headerRow)
        stackView.addArrangedSubview(slider)

        addSubview(stackView)

        leadingConstraint = stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalOffset)
        trailingConstraint = stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(16.0 - horizontalOffset))

        NSLayoutConstraint.activate([
            leadingConstraint!,
            trailingConstraint!,
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2.0),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2.0),
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            slider.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    private func updateValueLabel() {
        valueField.stringValue = formatter(slider.doubleValue)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabel()
        onChange?(sender.doubleValue)
    }
}

final class GlassEditorView: NSView {
    enum TitleBarLayout {
        static let buttonSpacing: CGFloat = 6.0
        static let trailingInset: CGFloat = 22.0
        static let editorTopInset: CGFloat = 46.0
        static let titleGapAfterButtons: CGFloat = 90.0
    }

    var settings = PanelSettings() {
        didSet { applySettings() }
    }

    var onTextDidChange: (() -> Void)?

    private let glassContainer = NSGlassEffectContainerView(frame: .zero)
    private let glassView = NSGlassEffectView(frame: .zero)
    private let contentHost = NSView(frame: .zero)
    private let hitShield = HitTestShieldView(frame: .zero)
    private let supplementalBlurView = NSVisualEffectView(frame: .zero)
    private let blurLayer = CALayer()
    private let fillLayer = CALayer()
    private let colorLayer = CALayer()
    private let dimLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let editorScrollView = NSScrollView(frame: .zero)
    private let editorContentView = FlippedContentView(frame: .zero)
    private let wrapGuideView = WrapGuideView(frame: .zero)
    private let backdropTextView = NSTextView(frame: .zero)
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
        let topInset = max(titleMetrics.editorTopInset, TitleBarLayout.editorTopInset)
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
        blurLayer.frame = bounds
        fillLayer.frame = bounds
        colorLayer.frame = bounds
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        sheenLayer.frame = bounds
        CATransaction.commit()

        editorScrollView.frame = editorRect
        supplementalBlurView.frame = bounds
        let maxStatusWidth = max(bounds.width - titleMetrics.leadingReserve - TitleBarLayout.trailingInset, 120.0)
        let statusSize = fileStatusStack.fittingSize
        let clampedWidth = min(statusSize.width, maxStatusWidth)
        fileStatusStack.frame = CGRect(
            x: bounds.width - clampedWidth - TitleBarLayout.trailingInset,
            y: titleMetrics.statusOriginY,
            width: clampedWidth,
            height: statusSize.height
        )
        syncEditorLayout()
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

        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor.clear.cgColor
        glassView.contentView = contentHost

        supplementalBlurView.blendingMode = .behindWindow
        supplementalBlurView.material = .hudWindow
        supplementalBlurView.state = .active
        supplementalBlurView.isEmphasized = false
        supplementalBlurView.alphaValue = 0.0
        supplementalBlurView.isHidden = true
        contentHost.addSubview(supplementalBlurView)

        if let hostLayer = contentHost.layer {
            blurLayer.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "backgroundColor": NSNull(),
                "cornerRadius": NSNull(),
                "opacity": NSNull(),
                "backgroundFilters": NSNull()
            ]
            hostLayer.addSublayer(blurLayer)

            [fillLayer, colorLayer, dimLayer].forEach { layer in
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

        fillLayer.backgroundColor = settings.fillColor.cgColor
        colorLayer.backgroundColor = settings.accentColor.cgColor
        dimLayer.backgroundColor = settings.dimColor.cgColor

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.0
        borderLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "path": NSNull(),
            "strokeColor": NSNull(),
            "opacity": NSNull()
        ]
        layer?.addSublayer(borderLayer)

        sheenLayer.colors = [
            NSColor(calibratedWhite: 1.0, alpha: 0.0).cgColor,
            NSColor(calibratedWhite: 1.0, alpha: 1.0).cgColor,
            NSColor(calibratedWhite: 1.0, alpha: 0.45).cgColor,
            NSColor.clear.cgColor
        ]
        sheenLayer.locations = [0.0, 0.14, 0.40, 1.0]
        sheenLayer.startPoint = CGPoint(x: 0.12, y: 1.0)
        sheenLayer.endPoint = CGPoint(x: 0.88, y: 0.0)
        sheenLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "cornerRadius": NSNull(),
            "opacity": NSNull()
        ]
        layer?.addSublayer(sheenLayer)

        hitShield.wantsLayer = true
        hitShield.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.001).cgColor
        contentHost.addSubview(hitShield)

        setupEditor()
        applySettings()
    }

    private func setupEditor() {
        editorScrollView.borderType = .noBorder
        editorScrollView.hasVerticalScroller = true
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.drawsBackground = false
        editorScrollView.automaticallyAdjustsContentInsets = false
        editorScrollView.scrollerStyle = .overlay

        editorTextView = makeEditorTextView()
        editorTextView.string = ""

        backdropTextView.minSize = editorTextView.minSize
        backdropTextView.maxSize = editorTextView.maxSize
        backdropTextView.isVerticallyResizable = true
        backdropTextView.isHorizontallyResizable = false
        backdropTextView.autoresizingMask = [.width]
        backdropTextView.drawsBackground = false
        backdropTextView.backgroundColor = .clear
        backdropTextView.textContainerInset = editorTextView.textContainerInset
        backdropTextView.isRichText = false
        backdropTextView.importsGraphics = false
        backdropTextView.isEditable = false
        backdropTextView.isSelectable = false
        backdropTextView.string = ""

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

    private func applySettings() {
        applyGlassAppearance()
        applyEditorAppearance(using: settings, updateExistingText: true, updateSelection: true)
        updateChrome()
    }

    private func applyGlassAppearance() {
        glassView.style = settings.glassStyle.appKitStyle
        glassView.cornerRadius = settings.cornerRadius
        glassView.tintColor = settings.tintColor
        glassContainer.spacing = 0.0

        fillLayer.backgroundColor = settings.fillColor.cgColor
        colorLayer.backgroundColor = settings.accentColor.cgColor
        dimLayer.backgroundColor = settings.dimColor.cgColor
        borderLayer.strokeColor = NSColor(calibratedWhite: 1.0, alpha: settings.borderOpacity).cgColor
        sheenLayer.opacity = Float(settings.sheenOpacity)
        supplementalBlurView.alphaValue = settings.blurStrength
        supplementalBlurView.isHidden = settings.blurStrength < 0.001
        if settings.blurStrength > 0.001 {
            let blurFilter = CIFilter(name: "CIGaussianBlur")
            blurFilter?.setDefaults()
            blurFilter?.setValue(settings.blurStrength * 24.0, forKey: kCIInputRadiusKey)
            blurLayer.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.015).cgColor
            blurLayer.backgroundFilters = blurFilter.map { [$0] } ?? []
            blurLayer.opacity = 1.0
        } else {
            blurLayer.backgroundFilters = []
            blurLayer.backgroundColor = NSColor.clear.cgColor
            blurLayer.opacity = 0.0
        }

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(settings.shadowOpacity)
        layer?.shadowRadius = settings.shadowBlur
        layer?.shadowOffset = CGSize(width: 0.0, height: -8.0)
    }

    func applyAnimatedColorUpdate(_ updatedSettings: PanelSettings, refreshEditorTint: Bool) {
        colorLayer.backgroundColor = updatedSettings.accentColor.cgColor
        applyBackdropTextColor(using: updatedSettings)
        // Formulas are bitmaps, so they can't ride backdropTextView.textColor like
        // the glyph text — retint them (throttled via refreshEditorTint) so they
        // cycle hue with Rainbow too. Cheap: cached-image recolor, no re-render.
        currentFormulaTint = updatedSettings.editorCompositeTextColor
        if refreshEditorTint {
            recolorFormulas(to: currentFormulaTint)
            if !mathPreview.isHidden { mathPreview.applyTint(currentFormulaTint) }
        }
        wrapGuideView.guideColor = updatedSettings.editorCompositeTextColor.withAlphaComponent(
            max(0.0, min(1.0, updatedSettings.wrapGuideOpacity))
        )
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
        pendingAutoCloseAt = nil
        hideMathPreview()
        syncBackdrop()
        syncEditorLayout()
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

    func rebuildEditorTextView() {
        let previousText = editorTextView.string
        let previousSelection = editorTextView.selectedRange()
        editorTextView.removeFromSuperview()
        editorTextView = makeEditorTextView()
        editorTextView.string = previousText
        editorTextView.setSelectedRange(previousSelection)
        wrapGuideView.textView = editorTextView
        editorContentView.addSubview(editorTextView)
        applyEditorAppearance(using: settings, updateExistingText: true, updateSelection: true)
        focusEditor()
    }

    func focusEditor() {
        guard let window else { return }
        window.makeFirstResponder(editorTextView)
        editorTextView.updateInsertionPointStateAndRestartTimer(true)
        editorTextView.needsDisplay = true
    }

    func adjustFontSize(delta: CGFloat) {
        let nextSize = min(max(settings.editorFontSize + delta, 11.0), 30.0)
        settings.editorFontSize = nextSize
        applyEditorAppearance(using: settings, updateExistingText: true, updateSelection: true)
    }

    private func applyEditorAppearance(using appearanceSettings: PanelSettings, updateExistingText: Bool, updateSelection: Bool) {
        let font = NSFont.monospacedSystemFont(ofSize: appearanceSettings.editorFontSize, weight: .regular)
        editorTextView.font = font
        editorTextView.textColor = appearanceSettings.editorTextColor
        editorTextView.insertionPointColor = appearanceSettings.caretColor
        editorTextView.typingAttributes = [
            .font: font,
            .foregroundColor: appearanceSettings.editorTextColor
        ]
        backdropTextView.font = font
        backdropTextView.textColor = appearanceSettings.backdropTextColor
        wrapGuideView.guideColor = appearanceSettings.editorCompositeTextColor.withAlphaComponent(
            max(0.0, min(1.0, appearanceSettings.wrapGuideOpacity))
        )
        wrapGuideView.guideXOffset = appearanceSettings.wrapGuideXOffset
        wrapGuideView.guideThickness = appearanceSettings.wrapGuideThickness
        wrapGuideView.guideTopTrim = appearanceSettings.wrapGuideTopTrim
        wrapGuideView.guideBottomTrim = appearanceSettings.wrapGuideBottomTrim
        wrapGuideView.roundedCaps = appearanceSettings.wrapGuideRounded
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
        }
        currentFormulaTint = appearanceSettings.editorCompositeTextColor
        recolorFormulas(to: currentFormulaTint)
        syncBackdrop()
        applyBackdropTextColor(using: appearanceSettings)
        syncEditorLayout()
    }

    private func applyWordWrap(using appearanceSettings: PanelSettings) {
        let showsGuides = appearanceSettings.wordWrap && appearanceSettings.showWrapGuides

        editorScrollView.hasHorizontalScroller = !appearanceSettings.wordWrap
        editorTextView.isHorizontallyResizable = !appearanceSettings.wordWrap
        backdropTextView.isHorizontallyResizable = !appearanceSettings.wordWrap
        editorTextView.textContainerInset = NSSize(width: 10.0, height: 6.0)
        backdropTextView.textContainerInset = editorTextView.textContainerInset
        wrapGuideView.isGuideVisible = showsGuides

        if let textContainer = editorTextView.textContainer {
            textContainer.widthTracksTextView = appearanceSettings.wordWrap
            textContainer.containerSize = NSSize(
                width: appearanceSettings.wordWrap ? max(editorScrollView.contentSize.width, 120.0) : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        if let textContainer = backdropTextView.textContainer {
            textContainer.widthTracksTextView = appearanceSettings.wordWrap
            textContainer.containerSize = NSSize(
                width: appearanceSettings.wordWrap ? max(editorScrollView.contentSize.width, 120.0) : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func applyBackdropTextColor(using appearanceSettings: PanelSettings) {
        backdropTextView.font = NSFont.monospacedSystemFont(ofSize: appearanceSettings.editorFontSize, weight: .regular)
        backdropTextView.textColor = appearanceSettings.backdropTextColor
    }

    private func syncEditorLayout() {
        let visibleWidth = max(editorScrollView.contentSize.width, 120.0)
        let contentWidth = settings.wordWrap ? visibleWidth : max(measuredTextWidth(for: editorTextView), measuredTextWidth(for: backdropTextView), visibleWidth)
        let targetSize = NSSize(
            width: settings.wordWrap ? contentWidth : CGFloat.greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        )

        if let textContainer = editorTextView.textContainer {
            textContainer.containerSize = targetSize
            textContainer.widthTracksTextView = settings.wordWrap
        }
        if let textContainer = backdropTextView.textContainer {
            textContainer.containerSize = targetSize
            textContainer.widthTracksTextView = settings.wordWrap
        }

        if let textContainer = editorTextView.textContainer {
            editorTextView.layoutManager?.ensureLayout(for: textContainer)
        }
        if let textContainer = backdropTextView.textContainer {
            backdropTextView.layoutManager?.ensureLayout(for: textContainer)
        }

        let frontHeight = measuredTextHeight(for: editorTextView)
        let backHeight = measuredTextHeight(for: backdropTextView)
        let visibleHeight = max(editorScrollView.contentSize.height, 120.0)
        let contentHeight = max(frontHeight, backHeight, visibleHeight)

        editorContentView.frame = NSRect(x: 0.0, y: 0.0, width: contentWidth, height: contentHeight)
        wrapGuideView.frame = editorContentView.bounds
        backdropTextView.frame = editorContentView.bounds
        editorTextView.frame = editorContentView.bounds
        wrapGuideView.needsDisplay = true
    }

    private func measuredTextHeight(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return max(editorScrollView.contentSize.height, 120.0)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return ceil(usedHeight + (textView.textContainerInset.height * 2.0) + 6.0)
    }

    private func measuredTextWidth(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return max(editorScrollView.contentSize.width, 120.0)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedWidth = layoutManager.usedRect(for: textContainer).width
        return ceil(usedWidth + (textView.textContainerInset.width * 2.0) + 40.0)
    }

    private func updateChrome() {
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: settings.cornerRadius,
            cornerHeight: settings.cornerRadius,
            transform: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurLayer.cornerRadius = settings.cornerRadius
        fillLayer.cornerRadius = settings.cornerRadius
        colorLayer.cornerRadius = settings.cornerRadius
        dimLayer.cornerRadius = settings.cornerRadius
        borderLayer.path = path
        sheenLayer.cornerRadius = settings.cornerRadius
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

        fileIndicatorField.stringValue = fileIsEdited ? appearanceSettings.documentIndicatorStyle.symbol : ""
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
        syncBackdrop()
        syncEditorLayout()
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
    var isEditingMath: Bool { mathEditRange != nil }

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
        syncTextLayersAndLayout()
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
        syncTextLayersAndLayout()
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
        syncTextLayersAndLayout()
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
        var caret = editorTextView.selectedRange().location
        let spans = MathSyntax.completeSpans(in: storage.string as NSString)
        let active = MathSyntax.activeSpan(in: storage.string as NSString, caret: caret)
        for span in spans.reversed() where !(active.map { NSEqualRanges($0, span) } ?? false) {
            caret = renderSpan(span, caret: caret)
        }
        editorTextView.setSelectedRange(NSRange(location: max(0, min(caret, storage.length)), length: 0))

        // Refresh the editing state/preview for wherever the caret ended up.
        mathEditRange = MathSyntax.activeSpan(in: storage.string as NSString, caret: editorTextView.selectedRange().location)
        if mathEditRange != nil {
            applyMathHighlight()
            updateMathPreview()
        } else {
            hideMathPreview()
            clearMathHighlight()
        }
        syncTextLayersAndLayout()
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
    /// invalid → left untouched). Returns the caret remapped across the change.
    private func renderSpan(_ span: NSRange, caret: Int) -> Int {
        guard let storage = editorTextView.textStorage,
              span.location + span.length <= storage.length else { return caret }
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
            return caret   // invalid LaTeX → leave the raw source in place
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
    private func applyMathHighlight() {
        guard let storage = editorTextView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: settings.editorTextColor, range: full)
        if let r = mathEditRange, r.location + r.length <= storage.length {
            storage.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.72, alpha: 1.0), range: r)
        }
    }

    private func clearMathHighlight() {
        guard let storage = editorTextView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: settings.editorTextColor, range: full)
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

    /// Mirrors the editor's content (including formula attachments, for exact
    /// alignment) into the colored backdrop layer, recolored and without the
    /// editing highlight.
    private func syncBackdrop() {
        guard let editorStorage = editorTextView.textStorage,
              let backStorage = backdropTextView.textStorage else { return }
        let copy = NSMutableAttributedString(attributedString: editorStorage)
        let full = NSRange(location: 0, length: copy.length)
        // Use the color the backdrop is *currently* showing, not settings.backdropTextColor:
        // during Rainbow the timer animates backdropTextView.textColor every frame but does
        // NOT update editorView.settings (that path is avoided to keep the blink timer alive,
        // see §7). Baking the stale settings color here made the backdrop flash to a frozen
        // hue for one frame on every keystroke — the returned text-color flicker.
        let backdropColor = backdropTextView.textColor ?? settings.backdropTextColor
        // The halo lives ONLY on this near-opaque backdrop layer, never on the
        // translucent editor glyphs on top: a shadow drawn under a translucent glyph
        // shows through and dims it. Here the ~0.94-opaque backdrop glyph covers the
        // dark shadow under the letter, so only the halo *around* the text remains.
        copy.addAttributes([.font: editorFont, .foregroundColor: backdropColor, .shadow: settings.editorTextShadow], range: full)
        backStorage.setAttributedString(copy)
    }

    /// Re-tints every rendered formula to `color` (cheap bitmap retint, no LaTeX
    /// re-layout) so formulas cycle hue with Rainbow alongside the text. Updates
    /// both the editor and its backdrop copies, then redraws.
    private func recolorFormulas(to color: NSColor) {
        guard let editorStorage = editorTextView.textStorage else { return }
        let shadow = settings.editorTextShadow
        let full = NSRange(location: 0, length: editorStorage.length)
        var tinted: [(NSRange, NSImage)] = []
        var sizeChanged = false
        editorStorage.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            guard let att = value as? MathAttachment else { return }
            let before = att.image?.size
            att.applyTint(color, shadow: shadow)
            if att.image?.size != before { sizeChanged = true }
            if let img = att.image { tinted.append((range, img)) }
        }
        guard !tinted.isEmpty else { return }
        // The backdrop layer holds attachment copies at the same ranges; point them
        // at the freshly tinted images so both layers stay in sync (this path does
        // not call syncBackdrop, to avoid a full backdrop rebuild every tick).
        if let backStorage = backdropTextView.textStorage {
            for (range, img) in tinted where NSMaxRange(range) <= backStorage.length {
                (backStorage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment)?.image = img
            }
        }
        // Baking the halo changes the attachment image size; the layout manager caches
        // glyph metrics, so a size change needs an explicit relayout. Skipped when only
        // the tint changed (e.g. every Rainbow frame) so that path stays cheap.
        if sizeChanged {
            relayoutAttachments(in: editorTextView)
            relayoutAttachments(in: backdropTextView)
        }
        editorTextView.needsDisplay = true
        backdropTextView.needsDisplay = true
    }

    private func relayoutAttachments(in textView: NSTextView) {
        guard let lm = textView.layoutManager, let tc = textView.textContainer,
              let length = textView.textStorage?.length else { return }
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
        lm.ensureLayout(for: tc)
    }

    private func syncTextLayersAndLayout() {
        syncBackdrop()
        syncEditorLayout()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: PanelWindow!
    private var editorView = GlassEditorView(frame: .zero)
    private let appearanceMenu = NSMenu(title: "Appearance")
    private let formatMenu = NSMenu(title: "Format")
    private let defaults = UserDefaults.standard
    private var settings = PanelSettings(defaults: .standard)
    private var rainbowTimer: Timer?
    private var currentFileURL: URL?
    private var isDocumentEdited = false
    private var lastAnimatedTextHue: CGFloat = 0.0

    private var alwaysOnTopItem: NSMenuItem!
    private var rainbowItem: NSMenuItem!
    private var wordWrapItem: NSMenuItem!
    private var wrapGuidesItem: NSMenuItem!
    private var renderFormulasItem: NSMenuItem!

    private var sliderViews: [String: SliderMenuItemView] = [:]
    private var pendingFocusRestore = false
    private let ciContext = CIContext()

    func applicationDidFinishLaunching(_ notification: Notification) {
        normalizeFixedSettings()
        setupWindow()
        setupMainMenu()
        bindEditorView(editorView)
        applySettings()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.positionTrafficLights()
        }
        clearCustomFinderIcon()
    }

    private func clearCustomFinderIcon() {
        // Remove any previously set custom Finder icon (e.g. the dark-background
        // version applied by an earlier build) so Finder uses the bundle icon.
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global(qos: .utility).async {
            NSWorkspace.shared.setIcon(nil, forFile: bundlePath, options: [])
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let firstPath = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        let fileURL = URL(fileURLWithPath: firstPath)
        openDocument(at: fileURL)
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAlwaysOnTop(_ sender: Any?) {
        settings.alwaysOnTop.toggle()
        applySettings()
    }

    @objc private func toggleRainbow(_ sender: Any?) {
        settings.rainbowEnabled.toggle()
        applySettings()
    }

    @objc private func setClearGlass(_ sender: Any?) {
        settings.glassStyle = .clear
        applySettings()
    }

    @objc private func setRegularGlass(_ sender: Any?) {
        settings.glassStyle = .regular
        applySettings()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Jot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileItem)
        fileItem.submenu = makeFileMenu()

        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        mainMenu.addItem(formatItem)
        formatItem.submenu = formatMenu

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        mainMenu.addItem(appearanceItem)
        appearanceItem.submenu = appearanceMenu

        setupFormatMenu()
        setupAppearanceMenu()
        finalizeMenuLayout(formatMenu)
        finalizeMenuLayout(appearanceMenu)

        NSApp.mainMenu = mainMenu
    }

    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")

        let openItem = NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let saveItem = NSMenuItem(title: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = self
        menu.addItem(saveItem)

        let saveAsItem = NSMenuItem(title: "Save As…", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.target = self
        menu.addItem(saveAsItem)

        return menu
    }

    private func setupWindow() {
        let initialFrame = NSRect(x: 0.0, y: 0.0, width: 637.5, height: 442.5)   // 1.5× the previous 425×295
        window = makeWindow(frame: initialFrame, editorView: editorView)
        window.center()
    }

    private func bindEditorView(_ view: GlassEditorView) {
        view.onTextDidChange = { [weak self] in
            guard let self, !self.isDocumentEdited else { return }
            self.markDocumentEdited(true)
        }
    }

    private func makeWindow(frame: NSRect, editorView: GlassEditorView) -> PanelWindow {
        let newWindow = PanelWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.delegate = self
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.title = currentFileURL?.lastPathComponent ?? "Jot"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        newWindow.minSize = NSSize(width: 360.0, height: 240.0)
        newWindow.level = settings.alwaysOnTop ? .floating : .normal
        newWindow.representedURL = currentFileURL
        newWindow.contentView = editorView
        installTitlebarToolbar(in: newWindow)
        return newWindow
    }

    // A transparent, empty unified toolbar raises the titlebar height so AppKit
    // itself lays the traffic lights out lower and more inset — clearing our big
    // rounded corner while keeping their hover tracking intact (AppKit owns the
    // positioning). The toolbar shows nothing; our fullSizeContentView glass
    // covers the titlebar area. (A titlebar *accessory* did NOT grow the titlebar
    // — measured: it left the buttons at the default 9,9.)
    private func installTitlebarToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "JotToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    private func setupFormatMenu() {
        formatMenu.removeAllItems()
        formatMenu.autoenablesItems = false
        formatMenu.minimumWidth = 248.0

        addSlider(
            to: formatMenu,
            key: "editorFontSize",
            title: "Font Size",
            range: 11.0 ... 30.0,
            value: settings.editorFontSize,
            formatter: { String(format: "%.0f", $0) }
        ) { [weak self] value in
            self?.settings.editorFontSize = CGFloat(value)
            self?.applySettings()
        }

        formatMenu.addItem(.separator())
        wordWrapItem = NSMenuItem(title: "Word Wrap", action: #selector(toggleWordWrap(_:)), keyEquivalent: "")
        wordWrapItem.target = self
        formatMenu.addItem(wordWrapItem)

        wrapGuidesItem = NSMenuItem(title: "Wrapped Line Guides", action: #selector(toggleWrapGuides(_:)), keyEquivalent: "")
        wrapGuidesItem.target = self
        formatMenu.addItem(wrapGuidesItem)

        formatMenu.addItem(.separator())
        renderFormulasItem = NSMenuItem(title: "Render LaTeX Formulas", action: #selector(toggleRenderFormulas(_:)), keyEquivalent: "")
        renderFormulasItem.target = self
        formatMenu.addItem(renderFormulasItem)
    }

    private func setupAppearanceMenu() {
        appearanceMenu.removeAllItems()
        appearanceMenu.autoenablesItems = false
        appearanceMenu.minimumWidth = 248.0

        alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop(_:)), keyEquivalent: "")
        alwaysOnTopItem.target = self
        appearanceMenu.addItem(alwaysOnTopItem)

        rainbowItem = NSMenuItem(title: "Rainbow Mode", action: #selector(toggleRainbow(_:)), keyEquivalent: "")
        rainbowItem.target = self
        appearanceMenu.addItem(rainbowItem)
        appearanceMenu.addItem(.separator())

        addSlider(
            to: appearanceMenu,
            key: "darkeningOpacity",
            title: "Darkening",
            range: 0.0 ... 1.0,
            value: settings.darkeningOpacity
        ) { [weak self] value in
            self?.settings.darkeningOpacity = CGFloat(value)
            self?.applySettings()
        }

        addSlider(
            to: appearanceMenu,
            key: "colorStrength",
            title: "Color Strength",
            range: 0.0 ... 1.0,
            value: settings.colorStrength
        ) { [weak self] value in
            self?.settings.colorStrength = CGFloat(value)
            self?.applySettings()
        }

        addSlider(
            to: appearanceMenu,
            key: "rainbowHue",
            title: "Hue",
            range: 0.0 ... 360.0,
            value: settings.rainbowHue * 360.0,
            formatter: { String(format: "%.0f", $0) }
        ) { [weak self] value in
            self?.settings.rainbowHue = CGFloat(value / 360.0)
            self?.applySettings()
        }

        addSlider(
            to: appearanceMenu,
            key: "rainbowSpeed",
            title: "Rainbow Speed",
            range: 0.0 ... 1.2,
            value: settings.rainbowSpeed
        ) { [weak self] value in
            self?.settings.rainbowSpeed = CGFloat(value)
            self?.applySettings()
        }

        addSlider(
            to: appearanceMenu,
            key: "textColorStrength",
            title: "Text Opacity",
            range: 0.0 ... 1.0,
            value: settings.textColorStrength
        ) { [weak self] value in
            self?.settings.textColorStrength = CGFloat(value)
            self?.applySettings()
        }

        addSlider(
            to: appearanceMenu,
            key: "textShadowStrength",
            title: "Text Shadow",
            range: 0.0 ... 1.0,
            value: settings.textShadowStrength
        ) { [weak self] value in
            self?.settings.textShadowStrength = CGFloat(value)
            self?.applySettings()
        }
    }

    private func normalizeFixedSettings() {
        settings.glassStyle = .clear
        settings.cornerRadius = 30.0
        settings.tintStrength = 0.0
        settings.warmth = 0.0
        settings.fillOpacity = 0.0
        settings.borderOpacity = 0.05
        settings.sheenOpacity = 0.01
        settings.shadowOpacity = 0.0
        settings.shadowBlur = 0.0
        settings.blurStrength = 0.0
        settings.menuSliderOffset = 25.0
        settings.documentIndicatorStyle = .star
        // Wrap guide values calibrated by the user; UI removed, preserved here.
        settings.wrapGuideXOffset = -10.37291937635512
        settings.wrapGuideThickness = 3.197090105162524
        settings.wrapGuideTopTrim = 8.003953657818043
        settings.wrapGuideBottomTrim = 2.254072375033705
        settings.wrapGuideOpacity = 0.3048133243984811
        settings.wrapGuideRounded = true
    }

    private func finalizeMenuLayout(_ menu: NSMenu) {
        for item in menu.items {
            if let view = item.view {
                view.frame = NSRect(x: 0.0, y: 0.0, width: 220.0, height: 44.0)
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
            }
            if let submenu = item.submenu {
                finalizeMenuLayout(submenu)
            }
        }
    }

    private func addSlider(
        to menu: NSMenu,
        key: String,
        title: String,
        range: ClosedRange<Double>,
        value: CGFloat,
        formatter: @escaping (Double) -> String = { String(format: "%.2f", $0) },
        onChange: @escaping (Double) -> Void
    ) {
        let item = NSMenuItem()
        let view = SliderMenuItemView(
            title: title,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            initialValue: value,
            width: 220.0
        )
        view.formatter = formatter
        view.onChange = onChange
        view.horizontalOffset = settings.menuSliderOffset
        view.frame = NSRect(x: 0.0, y: 0.0, width: 220.0, height: 44.0)
        item.view = view
        menu.addItem(item)
        sliderViews[key] = view
    }

    @objc private func saveDocument(_ sender: Any?) {
        if let currentFileURL {
            saveEditorText(to: currentFileURL)
        } else {
            saveDocumentAs(sender)
        }
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = currentFileURL?.deletingLastPathComponent() ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.pendingFocusRestore = true
            self?.openDocument(at: url)
            self?.scheduleFocusFallback()
        }
    }

    @objc private func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.txt"
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = currentFileURL?.deletingLastPathComponent() ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.pendingFocusRestore = true
            self?.saveEditorText(to: url)
            self?.scheduleFocusFallback()
        }
    }

    private func scheduleFocusFallback() {
        // Fires only if windowDidBecomeKey didn't already handle focus restoration.
        // Sheets sometimes don't cause the parent window to emit didBecomeKey.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.pendingFocusRestore else { return }
            self.pendingFocusRestore = false
            self.positionTrafficLights()
            self.window.makeFirstResponder(nil)
            DispatchQueue.main.async { [weak self] in
                self?.editorView.focusEditor()
            }
        }
    }

    private func saveEditorText(to url: URL) {
        do {
            try editorView.text.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url
            window.representedURL = url
            window.title = url.lastPathComponent
            markDocumentEdited(false)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not save file"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    private func openDocument(at url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            editorView.setText(text)
            currentFileURL = url
            window.representedURL = url
            window.title = url.lastPathComponent
            isDocumentEdited = false
            editorView.setDocumentPresentation(fileURL: url, isEdited: false)
            positionTrafficLights()
            editorView.needsLayout = true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not open file"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    @objc private func toggleWordWrap(_ sender: Any?) {
        settings.wordWrap.toggle()
        applySettings()
    }

    @objc private func toggleRenderFormulas(_ sender: Any?) {
        settings.renderInlineFormulas.toggle()
        applySettings()                         // pushes the setting into editorView
        editorView.reprocessFormulaRendering()  // re-render or un-render the current document
    }

    @objc private func toggleWrapGuides(_ sender: Any?) {
        settings.showWrapGuides.toggle()
        applySettings()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard pendingFocusRestore else { return }
        pendingFocusRestore = false
        positionTrafficLights()
        window.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in
            self?.editorView.focusEditor()
        }
    }

    func windowDidResize(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        positionTrafficLights()
    }

    // Traffic lights are positioned by AppKit (via the tall titlebar accessory);
    // we only need to re-flow the status block, which tracks their position.
    private func positionTrafficLights() {
        editorView.needsLayout = true
    }

    private func applySettings() {
        settings.save(to: defaults)
        lastAnimatedTextHue = settings.rainbowHue
        window.level = settings.alwaysOnTop ? .floating : .normal
        editorView.settings = settings
        editorView.setDocumentPresentation(fileURL: currentFileURL, isEdited: isDocumentEdited)
        updateMenuState()
        updateRainbowTimer()
    }

    private func updateMenuState() {
        alwaysOnTopItem.state = settings.alwaysOnTop ? .on : .off
        rainbowItem.state = settings.rainbowEnabled ? .on : .off
        wordWrapItem.state = settings.wordWrap ? .on : .off
        wrapGuidesItem.state = settings.showWrapGuides ? .on : .off
        wrapGuidesItem.isEnabled = settings.wordWrap
        renderFormulasItem.state = settings.renderInlineFormulas ? .on : .off

        for view in sliderViews.values {
            view.horizontalOffset = settings.menuSliderOffset
        }

        sliderViews["darkeningOpacity"]?.doubleValue = settings.darkeningOpacity
        sliderViews["colorStrength"]?.doubleValue = settings.colorStrength
        sliderViews["rainbowHue"]?.doubleValue = settings.rainbowHue * 360.0
        sliderViews["rainbowSpeed"]?.doubleValue = settings.rainbowSpeed
        sliderViews["editorFontSize"]?.doubleValue = settings.editorFontSize
        sliderViews["textColorStrength"]?.doubleValue = settings.textColorStrength
        sliderViews["textShadowStrength"]?.doubleValue = settings.textShadowStrength
    }

    private func updateRainbowTimer() {
        rainbowTimer?.invalidate()
        rainbowTimer = nil

        if !settings.rainbowEnabled { return }

        rainbowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.settings.rainbowHue += max(self.settings.rainbowSpeed, 0.0) / 360.0 * 6.0
            if self.settings.rainbowHue > 1.0 {
                self.settings.rainbowHue.formTruncatingRemainder(dividingBy: 1.0)
            }
            let hueDelta = self.circularHueDistance(from: self.lastAnimatedTextHue, to: self.settings.rainbowHue)
            let shouldRefreshTextTint = hueDelta >= 0.025
            self.editorView.applyAnimatedColorUpdate(self.settings, refreshEditorTint: shouldRefreshTextTint)
            if shouldRefreshTextTint {
                self.lastAnimatedTextHue = self.settings.rainbowHue
            }
            self.sliderViews["rainbowHue"]?.doubleValue = self.settings.rainbowHue * 360.0
            // (Dock-icon hue-tinting removed — the app now ships a static icon.
            //  See memory note jot-dock-icon-tint for the old implementation.)
        }
        RunLoop.main.add(rainbowTimer!, forMode: .common)
    }

    private func circularHueDistance(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let delta = abs(end - start)
        return min(delta, 1.0 - delta)
    }

    private func markDocumentEdited(_ edited: Bool) {
        guard isDocumentEdited != edited else { return }
        isDocumentEdited = edited
        editorView.setDocumentPresentation(fileURL: currentFileURL, isEdited: edited)
        positionTrafficLights()
        editorView.needsLayout = true
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = appDelegate
application.run()
