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
    var darkeningOpacity: CGFloat = 0.10
    var colorStrength: CGFloat = 0.0
    var rainbowHue: CGFloat = 0.0
    var rainbowEnabled: Bool = false
    var rainbowSpeed: CGFloat = 0.20
    var alwaysOnTop: Bool = false
    var editorFontSize: CGFloat = 15.0
    var textColorStrength: CGFloat = 0.16
    var blurStrength: CGFloat = 0.0
    var menuSliderOffset: CGFloat = 25.0
    var wordWrap: Bool = true
    var showWrapGuides: Bool = true
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
        self.darkeningOpacity = CGFloat(dictionary["darkeningOpacity"] as? Double ?? 0.10)
        self.colorStrength = CGFloat(dictionary["colorStrength"] as? Double ?? 0.0)
        self.rainbowHue = CGFloat(dictionary["rainbowHue"] as? Double ?? 0.0)
        self.rainbowEnabled = dictionary["rainbowEnabled"] as? Bool ?? false
        self.rainbowSpeed = CGFloat(dictionary["rainbowSpeed"] as? Double ?? 0.20)
        self.alwaysOnTop = dictionary["alwaysOnTop"] as? Bool ?? false
        self.editorFontSize = CGFloat(dictionary["editorFontSize"] as? Double ?? 15.0)
        self.textColorStrength = CGFloat(dictionary["textColorStrength"] as? Double ?? 0.16)
        self.blurStrength = CGFloat(dictionary["blurStrength"] as? Double ?? 0.0)
        self.menuSliderOffset = CGFloat(dictionary["menuSliderOffset"] as? Double ?? 25.0)
        self.wordWrap = dictionary["wordWrap"] as? Bool ?? true
        self.showWrapGuides = dictionary["showWrapGuides"] as? Bool ?? true
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
            "blurStrength": blurStrength,
            "menuSliderOffset": menuSliderOffset,
            "wordWrap": wordWrap,
            "showWrapGuides": showWrapGuides,
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

final class EditorTextView: NSTextView {
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
        static let topInset: CGFloat = 15.0
        static let leadingInset: CGFloat = 14.0
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

    var text: String {
        get { editorTextView.string }
        set { editorTextView.string = newValue }
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
        editorTextView.string = text
        backdropTextView.string = text
        syncEditorLayout()
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
        if backdropTextView.string != editorTextView.string {
            backdropTextView.string = editorTextView.string
        }
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
              let closeButton = window.standardWindowButton(.closeButton) else {
            let fallbackTopInset = max(safeAreaInsets.top + 10.0, 46.0)
            return (bounds.height - fallbackTopInset + 8.0, 110.0, fallbackTopInset)
        }

        let buttonHeight = closeButton.frame.height
        let buttonWidth = closeButton.frame.width
        let buttonOriginY = bounds.height - buttonHeight - TitleBarLayout.topInset
        let buttonCenterY = buttonOriginY + (buttonHeight / 2.0)
        let buttonsWidth = (buttonWidth * 3.0) + (TitleBarLayout.buttonSpacing * 2.0)
        let leadingReserve = TitleBarLayout.leadingInset + buttonsWidth + TitleBarLayout.titleGapAfterButtons
        let statusHeight = fileStatusStack.fittingSize.height
        let statusOriginY = buttonCenterY - (statusHeight / 2.0)
        return (statusOriginY, leadingReserve, TitleBarLayout.editorTopInset)
    }
}

extension GlassEditorView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if backdropTextView.string != editorTextView.string {
            backdropTextView.string = editorTextView.string
        }
        syncEditorLayout()
        onTextDidChange?()
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

    private var sliderViews: [String: SliderMenuItemView] = [:]
    private var pendingFocusRestore = false
    private var baseIconForDock: NSImage?
    private var dockIconTick = 0
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
        let initialFrame = NSRect(x: 0.0, y: 0.0, width: 425.0, height: 295.0)
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
        return newWindow
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

    private func positionTrafficLights() {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview else {
            return
        }

        let topInset: CGFloat = GlassEditorView.TitleBarLayout.topInset
        let leadingInset: CGFloat = GlassEditorView.TitleBarLayout.leadingInset
        let spacing: CGFloat = GlassEditorView.TitleBarLayout.buttonSpacing
        let y = container.bounds.height - close.frame.height - topInset

        close.setFrameOrigin(NSPoint(x: leadingInset, y: y))
        mini.setFrameOrigin(NSPoint(x: close.frame.maxX + spacing, y: y))
        zoom.setFrameOrigin(NSPoint(x: mini.frame.maxX + spacing, y: y))
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

        for view in sliderViews.values {
            view.horizontalOffset = settings.menuSliderOffset
        }

        sliderViews["darkeningOpacity"]?.doubleValue = settings.darkeningOpacity
        sliderViews["colorStrength"]?.doubleValue = settings.colorStrength
        sliderViews["rainbowHue"]?.doubleValue = settings.rainbowHue * 360.0
        sliderViews["rainbowSpeed"]?.doubleValue = settings.rainbowSpeed
        sliderViews["editorFontSize"]?.doubleValue = settings.editorFontSize
        sliderViews["textColorStrength"]?.doubleValue = settings.textColorStrength
    }

    private func updateRainbowTimer() {
        rainbowTimer?.invalidate()
        rainbowTimer = nil

        if baseIconForDock == nil,
           let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            baseIconForDock = NSImage(contentsOf: url)
        }

        if !settings.rainbowEnabled {
            // Keep icon tinted at the current (static) hue even without animation.
            updateDockIcon(hue: settings.rainbowHue)
            dockIconTick = 0
            return
        }

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

            // Dock icon ~5 fps (every 6th tick)
            self.dockIconTick += 1
            if self.dockIconTick >= 6 {
                self.dockIconTick = 0
                self.updateDockIcon(hue: self.settings.rainbowHue)
            }
        }
        RunLoop.main.add(rainbowTimer!, forMode: .common)
    }

    private func updateDockIcon(hue: CGFloat) {
        guard let base = baseIconForDock else { return }
        let canvasSize = NSSize(width: 512, height: 512)
        let icon = NSImage(size: canvasSize, flipped: false) { rect in
            let side = rect.width * 0.80
            let off  = (rect.width - side) / 2
            let iconRect = NSRect(x: off, y: off, width: side, height: side)

            let r = iconRect.width * 0.225
            NSBezierPath(roundedRect: iconRect, xRadius: r, yRadius: r).setClip()

            base.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

            NSColor(hue: hue, saturation: 0.65, brightness: 1.0, alpha: 0.30)
                .setFill()
            iconRect.fill(using: .color)
            return true
        }
        NSApp.applicationIconImage = icon
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
