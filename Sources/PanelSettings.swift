//
//  PanelSettings.swift
//  App-wide appearance state, persisted to UserDefaults.
//

import AppKit

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
