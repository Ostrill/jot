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
    private var isAppearanceMenuOpen = false
    private var lastRainbowTick: Date?

    private var alwaysOnTopItem: NSMenuItem!
    private var rainbowItem: NSMenuItem!
    private var wordWrapItem: NSMenuItem!
    private var wrapGuidesItem: NSMenuItem!
    private var renderFormulasItem: NSMenuItem!

    private var sliderViews: [String: SliderMenuItemView] = [:]

    /// Open document windows, held weakly so closed ones drop out on their own. Cheaper
    /// than rescanning NSApp.windows, which the Rainbow timer used to do 30×/second.
    private let openControllers = NSHashTable<JotWindowController>.weakObjects()

    /// Every open document window's editor, for broadcasting appearance changes.
    private var allEditorViews: [GlassEditorView] {
        openControllers.allObjects.map(\.editorView)
    }

    /// Only the editors the user can actually see. Rainbow repaints nothing for a
    /// window that is minimised, hidden or fully covered by another window.
    private var visibleEditorViews: [GlassEditorView] {
        openControllers.allObjects.compactMap { controller in
            guard let window = controller.window,
                  window.isVisible, !window.isMiniaturized,
                  window.occlusionState.contains(.visible) else { return nil }
            return controller.editorView
        }
    }

    /// Applies the current app-wide appearance to a freshly opened window.
    func register(_ controller: JotWindowController) {
        openControllers.add(controller)
        controller.editorView.settings = settings
        controller.window?.level = settings.alwaysOnTop ? .floating : .normal
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        applySettings()
        NSApp.activate()
        // No window is created here: this is a document-based app, so NSDocumentController
        // opens an untitled document (and its window) on launch, and handles opening files.
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

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editItem)
        editItem.submenu = makeEditMenu()

        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        mainMenu.addItem(formatItem)
        formatItem.submenu = formatMenu

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        mainMenu.addItem(appearanceItem)
        appearanceItem.submenu = appearanceMenu

        appearanceMenu.delegate = self
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

    /// The standard editing commands. They have no target, so they travel the responder
    /// chain to the focused text view (and to the window's undo manager) — which is also
    /// what makes ⌘Z/⌘X/⌘C/⌘V/⌘A work without the editor intercepting raw key codes.
    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
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

        let increaseItem = NSMenuItem(title: "Increase Font Size", action: #selector(increaseFontSize(_:)), keyEquivalent: "+")
        increaseItem.target = self
        formatMenu.addItem(increaseItem)
        let decreaseItem = NSMenuItem(title: "Decrease Font Size", action: #selector(decreaseFontSize(_:)), keyEquivalent: "-")
        decreaseItem.target = self
        formatMenu.addItem(decreaseItem)

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
        view.horizontalOffset = PanelSettings.Fixed.menuSliderOffset
        view.frame = NSRect(x: 0.0, y: 0.0, width: 220.0, height: 44.0)
        item.view = view
        menu.addItem(item)
        sliderViews[key] = view
    }

    @objc private func increaseFontSize(_ sender: Any?) { adjustFontSize(by: 1.0) }

    @objc private func decreaseFontSize(_ sender: Any?) { adjustFontSize(by: -1.0) }

    private func adjustFontSize(by delta: CGFloat) {
        settings.editorFontSize = min(max(settings.editorFontSize + delta, 11.0), 30.0)
        applySettings()
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
        for controller in openControllers.allObjects {
            controller.window?.level = settings.alwaysOnTop ? .floating : .normal
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
            view.horizontalOffset = PanelSettings.Fixed.menuSliderOffset
        }

        sliderViews["darkeningOpacity"]?.doubleValue = settings.darkeningOpacity
        sliderViews["colorStrength"]?.doubleValue = settings.colorStrength
        sliderViews["rainbowHue"]?.doubleValue = settings.rainbowHue * 360.0
        sliderViews["rainbowSpeed"]?.doubleValue = settings.rainbowSpeed
        sliderViews["editorFontSize"]?.doubleValue = settings.editorFontSize
        sliderViews["textColorStrength"]?.doubleValue = settings.textColorStrength
        sliderViews["textShadowStrength"]?.doubleValue = settings.textShadowStrength
    }

    /// Rainbow drives a very slow hue drift — a full cycle takes ~38 s at the default
    /// speed. It used to run at 30 fps, which cost ~5% CPU forever just to keep an idle
    /// window fading, so it now ticks at 12 fps with a generous tolerance (the system can
    /// coalesce those wake-ups). The hue advances by *elapsed time* rather than per tick,
    /// so the animation runs at exactly the same speed as before regardless of the rate.
    private static let rainbowInterval: TimeInterval = 1.0 / 12.0
    private static let rainbowHuePerSecond: CGFloat = 0.5     // × speed; 1/30 s × speed/60 before

    private func updateRainbowTimer() {
        rainbowTimer?.invalidate()
        rainbowTimer = nil
        lastRainbowTick = nil

        if !settings.rainbowEnabled { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.rainbowInterval, repeats: true) { [weak self] _ in
            self?.advanceRainbow()
        }
        timer.tolerance = Self.rainbowInterval * 0.3
        rainbowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceRainbow() {
        let now = Date()
        let elapsed = lastRainbowTick.map { now.timeIntervalSince($0) } ?? Self.rainbowInterval
        lastRainbowTick = now

        // Nothing on screen to animate → don't burn a frame (or advance the hue):
        // the animation simply resumes where it left off when a window comes back.
        let editors = visibleEditorViews
        guard !editors.isEmpty else { return }

        // Clamped: after the app was idle or asleep, `elapsed` can be huge.
        let step = max(settings.rainbowSpeed, 0.0) * Self.rainbowHuePerSecond * CGFloat(min(elapsed, 0.5))
        settings.rainbowHue = (settings.rainbowHue + step).truncatingRemainder(dividingBy: 1.0)

        let hueDelta = circularHueDistance(from: lastAnimatedTextHue, to: settings.rainbowHue)
        let shouldRefreshTextTint = hueDelta >= 0.025
        for view in editors {
            view.applyAnimatedColorUpdate(settings, refreshEditorTint: shouldRefreshTextTint)
        }
        if shouldRefreshTextTint {
            lastAnimatedTextHue = settings.rainbowHue
        }
        // Only worth pushing into the menu slider while the menu is actually open.
        if isAppearanceMenuOpen {
            sliderViews["rainbowHue"]?.doubleValue = settings.rainbowHue * 360.0
        }
        // (Dock-icon hue-tinting removed — the app now ships a static icon.
        //  See memory note jot-dock-icon-tint for the old implementation.)
    }

    private func circularHueDistance(from start: CGFloat, to end: CGFloat) -> CGFloat {
        let delta = abs(end - start)
        return min(delta, 1.0 - delta)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === appearanceMenu else { return }
        isAppearanceMenuOpen = true
        sliderViews["rainbowHue"]?.doubleValue = settings.rainbowHue * 360.0
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === appearanceMenu { isAppearanceMenuOpen = false }
    }
}
