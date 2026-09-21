//
//  Document.swift
//  NSDocument architecture: one document + window controller per file.
//

import AppKit

// MARK: - Document architecture (NSDocument)
//
// Each open file (or untitled scratch) is a JotDocument with one JotWindowController
// hosting a GlassEditorView. NSDocumentController then gives us New/Open/Save, the
// save-on-quit / save-on-close review, and multiple windows for free. Appearance
// (glass look, Rainbow) stays app-wide: AppDelegate owns it and broadcasts to every
// open editor.

@objc(JotDocument)
final class JotDocument: NSDocument {
    /// Source of truth for the text before a window exists / after it closes; while a
    /// window is open the editor holds the live copy (pulled back in `data(ofType:)`).
    var text: String = ""

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let controller = JotWindowController()
        addWindowController(controller)
        controller.loadText(text)
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor = (windowControllers.first as? JotWindowController)?.editorView {
            text = editor.text          // capture unsaved edits from the live editor
        }
        return Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = String(decoding: data, as: UTF8.self)
        // On revert the window already exists — push the reloaded text into it.
        (windowControllers.first as? JotWindowController)?.loadText(text)
    }

    /// Runs on every edit (`.changeDone`) and on save (`.changeCleared`), so it's the
    /// one place to keep the custom "✶ filename" status block in sync (the window's own
    /// titlebar is hidden, so the standard edited dot isn't visible).
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        for controller in windowControllers.compactMap({ $0 as? JotWindowController }) {
            controller.editorView.setDocumentPresentation(fileURL: fileURL, isEdited: isDocumentEdited)
        }
    }
}

final class JotWindowController: NSWindowController {
    let editorView = GlassEditorView(frame: .zero)

    /// Top-left of the last opened window, so each new one cascades from it instead of
    /// stacking exactly on top. Reset to `.zero` seeds the first window of the launch.
    private static var nextCascadePoint = NSPoint.zero

    /// The last size and position the user left a window at, so Jot opens where it was
    /// rather than at a fixed default every time.
    private static let frameDefaultsKey = "Jot.windowFrame"

    private static var rememberedFrame: NSRect? {
        guard let stored = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return nil }
        let frame = NSRectFromString(stored)
        guard frame.width > 100.0, frame.height > 100.0 else { return nil }
        // A screen may have gone away since; only reuse a frame that is still reachable.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return nil }
        return frame
    }

    init() {
        let window = PanelWindow(
            contentRect: NSRect(x: 0.0, y: 0.0, width: 637.5, height: 442.5),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // A normal document window: it participates in Spaces / Mission Control (.managed)
        // and can go full screen. The previous [.fullScreenAuxiliary, .moveToActiveSpace]
        // was left over from the app's floating-panel days and made the window *unmanaged*
        // (.managed, .moveToActiveSpace and .canJoinAllSpaces are mutually exclusive), so
        // the Dock icon wouldn't switch Spaces to it and Mission Control treated it as an
        // auxiliary panel.
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.minSize = NSSize(width: 360.0, height: 240.0)
        // A transparent, empty unified toolbar raises the titlebar height so AppKit
        // itself lays the traffic lights out lower and inset — clear of our big rounded
        // corner, hover tracking intact. (A titlebar *accessory* did NOT grow it; and do
        // not use setFrameOrigin — it desyncs the buttons' hover zones.)
        let toolbar = NSToolbar(identifier: "JotToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        super.init(window: window)          // phase 2 — self / editorView now usable

        shouldCascadeWindows = false
        window.contentView = editorView
        // The first window of a launch reopens where the last one was left; every further
        // one cascades from it (Cmd-N no longer stacks them exactly). cascadeTopLeft wraps
        // back near the top when it reaches a screen edge.
        if JotWindowController.nextCascadePoint == .zero {
            if let remembered = JotWindowController.rememberedFrame {
                window.setFrame(remembered, display: false)
            } else {
                window.center()
            }
            JotWindowController.nextCascadePoint = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        } else {
            JotWindowController.nextCascadePoint = window.cascadeTopLeft(from: JotWindowController.nextCascadePoint)
        }

        editorView.onTextDidChange = { [weak self] in
            (self?.document as? NSDocument)?.updateChangeCount(.changeDone)
        }

        // Traffic lights are positioned by AppKit; we only reflow the status block that
        // tracks them. Observe the window directly (NOT as its delegate) so NSDocument
        // keeps ownership of the window's unsaved-changes close review.
        let nc = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            nc.addObserver(self, selector: #selector(reflowTitlebar), name: name, object: window)
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            nc.addObserver(self, selector: #selector(rememberWindowFrame), name: name, object: window)
        }

        // Adopt the app-wide appearance for this fresh window.
        (NSApp.delegate as? AppDelegate)?.register(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Loads text into the editor, seeds the status block, and focuses the editor.
    func loadText(_ text: String) {
        editorView.setText(text)
        if let document = document as? JotDocument {
            editorView.setDocumentPresentation(fileURL: document.fileURL, isEdited: document.isDocumentEdited)
        }
        DispatchQueue.main.async { [weak self] in
            self?.reflowTitlebar()
            self?.editorView.focusEditor()
        }
    }

    @objc private func reflowTitlebar() {
        editorView.needsLayout = true
    }

    @objc private func rememberWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameDefaultsKey)
    }
}
