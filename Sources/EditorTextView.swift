//
//  EditorTextView.swift
//  The editor's NSTextView subclass and its math-editing host protocol.
//

import AppKit

/// Implemented by GlassEditorView to drive inline LaTeX editing from key events.
protocol MathEditingHost: AnyObject {
    func mathExitRight() -> Bool               // →  at latex end steps out past the closing "$$"
    func mathExitLeft() -> Bool                // ←  at latex start steps out before the opening "$$"
    func mathEnterAttachment(fromLeft: Bool) -> Bool   // →/← into a rendered formula opens it
    func mathClick(at point: NSPoint) -> Bool          // click a rendered formula → open at the click
    func mathDeleteBackwardAtStart() -> Bool   // ⌫ at the opening "$$" unwraps the formula
}

final class EditorTextView: NSTextView {
    weak var mathHost: MathEditingHost?
    /// Esc goes here first (to close the find bar); returns whether it was handled.
    var cancelHandler: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if cancelHandler?() == true { return }
        super.cancelOperation(sender)
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
