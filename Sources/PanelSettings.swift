//
//  PanelSettings.swift
//  App-wide appearance state, persisted to UserDefaults.
//

import AppKit

/// The app-wide appearance, shared by every open window and persisted under
/// `Jot.settings`. Only the values the user can actually change live here; everything
/// that was calibrated once and pinned at launch is a constant in `Fixed` below.
///
/// **Never change `CFBundleIdentifier`** — it swaps the preferences file and wipes
/// these settings.
struct PanelSettings {
    /// Appearance values that used to be adjustable, calibrated once and then pinned at
    /// every launch. Keeping them as constants means there is no second, contradictory
    /// copy in UserDefaults to reason about.
    enum Fixed {
        static let glassStyle: NSGlassEffectView.Style = .clear
        static let cornerRadius: CGFloat = 30.0
        static let borderOpacity: CGFloat = 0.05
        static let menuSliderOffset: CGFloat = 25.0
        /// Shown next to the filename while the document has unsaved changes.
        static let documentIndicatorSymbol = "\u{2736}"          // ✶
        static let wrapGuideXOffset: CGFloat = -10.37291937635512
        static let wrapGuideThickness: CGFloat = 3.197090105162524
        static let wrapGuideTopTrim: CGFloat = 8.003953657818043
        static let wrapGuideBottomTrim: CGFloat = 2.254072375033705
        static let wrapGuideOpacity: CGFloat = 0.3048133243984811
        static let wrapGuideRounded = true
    }

    // The defaults below are the maintainer's calibrated setup, baked in so a fresh
    // install opens looking like the reference configuration. They are also the
    // fallbacks when a key is missing from the stored settings — see `init(defaults:)`.
    var darkeningOpacity: CGFloat = 0.5952995867768595
    var colorStrength: CGFloat = 0.1984762396694215
    var rainbowHue: CGFloat = 0.4089982857132796
    var rainbowEnabled = true
    var rainbowSpeed: CGFloat = 0.05283514616487946
    var alwaysOnTop = false
    var editorFontSize: CGFloat = 19.61813446969697
    var textColorStrength: CGFloat = 0.5045408105713924
    /// Dark halo behind the text, so it stays legible over any backdrop (0 = off).
    var textShadowStrength: CGFloat = 0.1968333431523143
    var wordWrap = true
    var showWrapGuides = true
    /// Render `$$…$$` as images; off → plain source text.
    var renderInlineFormulas = true

    // MARK: Derived colors

    var accentColor: NSColor {
        NSColor(
            calibratedHue: clamped(rainbowHue),
            saturation: 0.78,
            brightness: 1.0,
            alpha: clamped(colorStrength)
        )
    }

    var dimColor: NSColor {
        NSColor(calibratedWhite: 0.0, alpha: max(0.0, min(0.90, darkeningOpacity)))
    }

    var editorTextColor: NSColor {
        NSColor(calibratedWhite: 1.0, alpha: textAlpha)
    }

    var editorCompositeTextColor: NSColor {
        accentReferenceColor.blended(withFraction: textAlpha, of: .white) ?? .white
    }

    var backdropTextColor: NSColor {
        accentReferenceColor.withAlphaComponent(0.94)
    }

    var selectionColor: NSColor {
        NSColor(calibratedWhite: 1.0, alpha: 0.16 + (clamped(textColorStrength) * 0.08))
    }

    var caretColor: NSColor {
        NSColor.white.blended(withFraction: 0.10, of: accentReferenceColor) ?? .white
    }

    /// A soft, centred dark halo drawn behind the glyphs so the text stays legible
    /// over any backdrop (light or dark) showing through the glass — the subtitle
    /// trick. A single flat colour can't be readable everywhere; this is why. Fully
    /// transparent (no shadow) when the strength is 0.
    var editorTextShadow: NSShadow {
        let strength = clamped(textShadowStrength)
        let shadow = NSShadow()
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = strength <= 0.001 ? 0.0 : 2.0 + (14.0 * strength)
        shadow.shadowColor = strength <= 0.001 ? nil : NSColor.black.withAlphaComponent(0.6 + (0.4 * strength))
        return shadow
    }

    var documentIndicatorColor: NSColor {
        NSColor.white.blended(withFraction: 0.55, of: accentReferenceColor) ?? accentReferenceColor
    }

    var statusTextColor: NSColor { editorCompositeTextColor }

    var wrapGuideColor: NSColor {
        editorCompositeTextColor.withAlphaComponent(clamped(Fixed.wrapGuideOpacity))
    }

    private var textAlpha: CGFloat {
        0.56 + (clamped(textColorStrength) * 0.28)
    }

    private var accentReferenceColor: NSColor {
        guard colorStrength > 0.001 else { return NSColor(calibratedWhite: 1.0, alpha: 1.0) }
        return NSColor(calibratedHue: clamped(rainbowHue), saturation: 0.55, brightness: 1.0, alpha: 1.0)
    }

    private func clamped(_ value: CGFloat) -> CGFloat { max(0.0, min(1.0, value)) }

    // MARK: Persistence

    private static let defaultsKey = "Jot.settings"
    private static let legacyDefaultsKey = "GlassPanel.settings"

    init() {}

    /// Loads the stored settings, falling back per key to the calibrated defaults above
    /// — so those literals exist in exactly one place.
    init(defaults: UserDefaults) {
        self.init()
        guard let stored = defaults.dictionary(forKey: Self.defaultsKey)
                ?? defaults.dictionary(forKey: Self.legacyDefaultsKey) else { return }

        func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
            (stored[key] as? Double).map { CGFloat($0) } ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            stored[key] as? Bool ?? fallback
        }

        darkeningOpacity = number("darkeningOpacity", darkeningOpacity)
        colorStrength = number("colorStrength", colorStrength)
        rainbowHue = number("rainbowHue", rainbowHue)
        rainbowEnabled = flag("rainbowEnabled", rainbowEnabled)
        rainbowSpeed = number("rainbowSpeed", rainbowSpeed)
        alwaysOnTop = flag("alwaysOnTop", alwaysOnTop)
        editorFontSize = number("editorFontSize", editorFontSize)
        textColorStrength = number("textColorStrength", textColorStrength)
        textShadowStrength = number("textShadowStrength", textShadowStrength)
        wordWrap = flag("wordWrap", wordWrap)
        showWrapGuides = flag("showWrapGuides", showWrapGuides)
        renderInlineFormulas = flag("renderInlineFormulas", renderInlineFormulas)
    }

    func save(to defaults: UserDefaults) {
        defaults.set([
            "darkeningOpacity": darkeningOpacity,
            "colorStrength": colorStrength,
            "rainbowHue": rainbowHue,
            "rainbowEnabled": rainbowEnabled,
            "rainbowSpeed": rainbowSpeed,
            "alwaysOnTop": alwaysOnTop,
            "editorFontSize": editorFontSize,
            "textColorStrength": textColorStrength,
            "textShadowStrength": textShadowStrength,
            "wordWrap": wordWrap,
            "showWrapGuides": showWrapGuides,
            "renderInlineFormulas": renderInlineFormulas
        ], forKey: Self.defaultsKey)
    }
}
