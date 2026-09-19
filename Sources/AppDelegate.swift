//
//  AppDelegate.swift
//  App-wide appearance, menus and the Rainbow animation.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appearanceMenu = NSMenu(title: "Appearance")
    private let formatMenu = NSMenu(title: "Format")
    private let defaults = UserDefaults.standard
    private var settings = PanelSettings(defaults: .standard)
    private var rainbowTimer: Timer?
    private var lastAnimatedTextHue: CGFloat = 0.0

    private var alwaysOnTopItem: NSMenuItem!
    private var rainbowItem: NSMenuItem!
    private var wordWrapItem: NSMenuItem!
    private var wrapGuidesItem: NSMenuItem!
    private var renderFormulasItem: NSMenuItem!

    private var sliderViews: [String: SliderMenuItemView] = [:]

    /// Every open document window's editor, for broadcasting appearance + Rainbow.
    private var allEditorViews: [GlassEditorView] {
        NSApp.windows.compactMap { ($0.windowController as? JotWindowController)?.editorView }
    }

    /// Applies the current app-wide appearance to a freshly opened window.
    func register(_ controller: JotWindowController) {
        controller.editorView.settings = settings
        controller.window?.level = settings.alwaysOnTop ? .floating : .normal
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        normalizeFixedSettings()
        setupMainMenu()
        applySettings()
        NSApp.activate()
        clearCustomFinderIcon()
        // No window is created here: this is a document-based app, so NSDocumentController
        // opens an untitled document (and its window) on launch, and handles opening files.
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

    /// Clicking the Dock icon brings an already-open window back: un-minimise it and order
    /// it front, which also switches Spaces to the one holding it. Without this, AppKit's
    /// default could open a *new* untitled document instead of surfacing the existing one.
    /// Returning false means "handled, don't run the default".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let documentWindows = NSApp.windows.filter { $0.windowController is JotWindowController }
        guard !documentWindows.isEmpty else { return true }   // nothing open → default: new untitled document
        let target = documentWindows.first { $0.isVisible && !$0.isMiniaturized } ?? documentWindows[0]
        if target.isMiniaturized { target.deminiaturize(nil) }
        target.makeKeyAndOrderFront(nil)
        return false
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
        // Standard document actions with no explicit target → they travel the responder
        // chain to NSDocumentController / the key window's NSDocument.
        menu.addItem(NSMenuItem(title: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S"))
        return menu
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

    @objc private func toggleWordWrap(_ sender: Any?) {
        settings.wordWrap.toggle()
        applySettings()
    }

    @objc private func toggleRenderFormulas(_ sender: Any?) {
        settings.renderInlineFormulas.toggle()
        applySettings()                                     // pushes the setting into every editor
        for view in allEditorViews { view.reprocessFormulaRendering() }
    }

    @objc private func toggleWrapGuides(_ sender: Any?) {
        settings.showWrapGuides.toggle()
        applySettings()
    }

    private func applySettings() {
        settings.save(to: defaults)
        lastAnimatedTextHue = settings.rainbowHue
        for view in allEditorViews { view.settings = settings }
        for window in NSApp.windows where window.windowController is JotWindowController {
            window.level = settings.alwaysOnTop ? .floating : .normal
        }
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
            for view in self.allEditorViews {
                view.applyAnimatedColorUpdate(self.settings, refreshEditorTint: shouldRefreshTextTint)
            }
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

}
