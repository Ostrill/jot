//
//  FindBar.swift
//  In-window find & replace: plain text or regular expressions.
//

import AppKit

/// Plain-text or regular-expression search over the editor's text.
///
/// AppKit's own find bar (NSTextFinder) has no regular-expression mode, which is why the
/// editor has a find bar of its own.
struct TextSearch: Equatable {
    var query: String
    var usesRegex: Bool
    var caseSensitive: Bool

    /// One NSRegularExpression serves both modes — plain text is escaped into a pattern —
    /// so matching, case folding and replacement behave identically either way.
    func expression() throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive { options.insert(.caseInsensitive) }
        let pattern = usesRegex ? query : NSRegularExpression.escapedPattern(for: query)
        return try NSRegularExpression(pattern: pattern, options: options)
    }

    /// Matches of `regex` in `text`, at most `limit` of them. Two kinds are skipped:
    /// - empty matches — a pattern like `^` or `x*` would otherwise "match" between every
    ///   pair of characters, and there is nothing to select or replace;
    /// - any match that covers a rendered formula. A formula sits in the text as a single
    ///   attachment character, so replacing such a match would silently delete it.
    ///
    /// Runs off the main thread; `cancellation` stops it early once a newer search has
    /// made it pointless.
    static func matches(of regex: NSRegularExpression, in text: String, limit: Int,
                        cancellation: SearchCancellation? = nil) -> [NSTextCheckingResult] {
        let ns = text as NSString
        let attachment = String(Character(UnicodeScalar(NSTextAttachment.character)!))
        var results: [NSTextCheckingResult] = []
        // .reportProgress calls back now and then even between matches, so a search with
        // few hits over a long text still notices that it has been cancelled.
        regex.enumerateMatches(in: text, options: .reportProgress,
                               range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            if cancellation?.isCancelled == true { stop.pointee = true; return }
            guard let match, match.range.length > 0,
                  ns.range(of: attachment, options: .literal, range: match.range).location == NSNotFound
            else { return }
            results.append(match)
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }

    /// What one match is replaced with: the literal text for a plain search; for a regular
    /// expression, a template where `$1` is a captured group and `\n` / `\t` are a
    /// newline and a tab.
    func replacement(for match: NSTextCheckingResult, in text: String, template: String,
                     using regex: NSRegularExpression) -> String {
        guard usesRegex else { return template }
        return regex.replacementString(for: match, in: text, offset: 0,
                                       template: Self.expandingEscapes(in: template))
    }

    /// NSRegularExpression templates read `\n` as a plain "n"; editors all treat it as a
    /// line break. Every other escape (`\$`, `\\`) is left for the template to handle.
    static func expandingEscapes(in template: String) -> String {
        var result = ""
        var characters = template.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n": result.append("\n")
            case "t": result.append("\t")
            default: result.append(character); result.append(escaped)
            }
        }
        return result
    }
}

/// Lets a newer search stop an older one that is still running in the background.
final class SearchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Drives one editor's find bar: searches in the background, highlights the matches,
/// moves between them and replaces them.
///
/// Matching runs off the main thread so that no pattern — however slow on however big a
/// document — can freeze the window; each new keystroke cancels the search before it.
final class EditorFindController: NSObject, FindBarDelegate {
    let bar = FindBarView(frame: .zero)

    /// Scrolls a match into view, clear of the bar floating over the text.
    var revealRange: ((NSRange) -> Void)?
    /// The bar was shown or hidden, or changed height.
    var onLayoutChange: (() -> Void)?

    /// Counting and highlighting stop here: past a few thousand matches the count means
    /// little, and every highlight costs a little to draw.
    static let matchLimit = 5_000

    private static let matchColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 0.24)
    private static let currentMatchColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 0.6)
    /// A search re-runs this long after the text was edited under an open bar.
    private static let editRefreshDelay: TimeInterval = 0.08

    private unowned let textView: NSTextView
    /// Concurrent on purpose: a pathological pattern can outlive its cancellation, and a
    /// serial queue would hold every later search up behind it.
    private let queue = DispatchQueue(label: "Jot.find", qos: .userInitiated, attributes: .concurrent)
    private var matches: [NSTextCheckingResult] = []
    private var isTruncated = false
    private var current: Int?
    /// Whether `matches` still describe the text and the query as they are now.
    private var resultsAreCurrent = false
    private var runningSearch: SearchCancellation?
    /// Actions that arrived while a search was still running (Return pressed right after
    /// typing); they run as soon as its results are in.
    private var pendingActions: [() -> Void] = []
    private var pendingEditRefresh: DispatchWorkItem?

    var isVisible: Bool { !bar.isHidden }

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        bar.isHidden = true
        bar.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(storageDidEdit(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        runningSearch?.cancel()
    }

    func perform(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface: show(replacing: false)
        case .showReplaceInterface: show(replacing: true)
        case .nextMatch: go(.next)
        case .previousMatch: go(.previous)
        case .setSearchString: useSelectionForFind()
        case .hideFindInterface: hide()
        default: break
        }
    }

    func hide() {
        guard isVisible else { return }
        cancelSearch()
        pendingActions = []
        matches = []
        current = nil
        resultsAreCurrent = false
        clearHighlights()
        bar.isHidden = true
        onLayoutChange?()
        // The match the bar stopped on stays selected; typing carries on from there.
        textView.window?.makeFirstResponder(textView)
    }

    private func show(replacing: Bool) {
        let wasVisible = isVisible
        bar.showsReplace = replacing
        bar.isHidden = false
        onLayoutChange?()
        if !wasVisible {
            // Like every Mac app, start from what was last searched for anywhere.
            if bar.searchField.stringValue.isEmpty, let shared = Self.sharedFindString() {
                bar.setQuery(literal: shared)
            }
            runSearch(selectingMatch: false)
        }
        bar.focusSearchField()
    }

    private func go(_ direction: FindBarView.Direction) {
        if bar.searchField.stringValue.isEmpty, let shared = Self.sharedFindString() {
            bar.setQuery(literal: shared)
            resultsAreCurrent = false
        }
        guard !bar.searchField.stringValue.isEmpty else {
            show(replacing: false)
            return
        }
        whenResultsAreCurrent { [weak self] in self?.step(direction) }
    }

    private func useSelectionForFind() {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { NSSound.beep(); return }
        let text = (textView.string as NSString).substring(with: selection)
        bar.setQuery(literal: text)
        Self.shareFindString(text)
        resultsAreCurrent = false
        if isVisible { runSearch(selectingMatch: false) }
    }

    // MARK: Searching

    private func whenResultsAreCurrent(_ action: @escaping () -> Void) {
        if resultsAreCurrent {
            action()
            return
        }
        pendingActions.append(action)
        if runningSearch == nil { runSearch(selectingMatch: false) }
    }

    private func cancelSearch() {
        runningSearch?.cancel()
        runningSearch = nil
        pendingEditRefresh?.cancel()
        pendingEditRefresh = nil
    }

    /// Starts a fresh search for the bar's query. `selectingMatch` selects and reveals the
    /// first match from the caret on — the incremental search while the query is typed.
    private func runSearch(selectingMatch: Bool, note: String? = nil) {
        cancelSearch()
        resultsAreCurrent = false
        let search = bar.search
        guard !search.query.isEmpty else {
            apply([], selectingMatch: false, note: note)
            return
        }
        // Compiling is cheap, so it stays here: a broken pattern is reported at once.
        let regex: NSRegularExpression
        do {
            regex = try search.expression()
        } catch {
            pendingActions = []
            matches = []
            current = nil
            clearHighlights()
            bar.setStatus("Invalid", isError: true)
            return
        }
        let text = textView.string
        let token = SearchCancellation()
        runningSearch = token
        queue.async { [weak self] in
            let found = TextSearch.matches(of: regex, in: text, limit: Self.matchLimit + 1, cancellation: token)
            DispatchQueue.main.async {
                guard let self, self.runningSearch === token, !token.isCancelled else { return }
                self.runningSearch = nil
                self.apply(found, selectingMatch: selectingMatch, note: note)
            }
        }
    }

    private func apply(_ found: [NSTextCheckingResult], selectingMatch: Bool, note: String?) {
        isTruncated = found.count > Self.matchLimit
        matches = isTruncated ? Array(found.prefix(Self.matchLimit)) : found
        let anchor = textView.selectedRange().location
        current = matches.isEmpty ? nil : (matches.firstIndex { $0.range.location >= anchor } ?? 0)
        resultsAreCurrent = true
        highlightMatches()
        updateStatus(note: note)
        if selectingMatch, let current { select(current) }

        let actions = pendingActions
        pendingActions = []
        actions.forEach { $0() }
    }

    /// Anything that edits the text — typing, undo, a replacement, a formula being
    /// rendered — makes the matches stale. With the bar open they are found again once
    /// the edits pause; with it closed, only when they are next needed.
    @objc private func storageDidEdit(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters) else { return }
        resultsAreCurrent = false
        runningSearch?.cancel()
        runningSearch = nil
        guard isVisible || !pendingActions.isEmpty else { return }
        pendingEditRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runSearch(selectingMatch: false) }
        pendingEditRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.editRefreshDelay, execute: work)
    }

    // MARK: Moving between matches

    private func step(_ direction: FindBarView.Direction) {
        guard !matches.isEmpty else { NSSound.beep(); return }
        let selection = textView.selectedRange()
        let index: Int
        if let current, NSEqualRanges(matches[current].range, selection) {
            index = direction == .next
                ? (current + 1) % matches.count
                : (current + matches.count - 1) % matches.count
        } else if direction == .next {
            // The caret was moved since: carry on from wherever it is now.
            index = matches.firstIndex { $0.range.location >= NSMaxRange(selection) } ?? 0
        } else {
            index = matches.lastIndex { NSMaxRange($0.range) <= selection.location } ?? matches.count - 1
        }
        let previous = current
        current = index
        if isVisible, let layoutManager = textView.layoutManager {
            if let previous {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.matchColor,
                                                    forCharacterRange: matches[previous].range)
            }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.currentMatchColor,
                                                forCharacterRange: matches[index].range)
        }
        updateStatus()
        select(index)
    }

    private func select(_ index: Int) {
        let range = matches[index].range
        textView.setSelectedRange(range)
        revealRange?(range)
    }

    // MARK: Replacing

    private func replaceCurrent() {
        guard let index = current, let storage = textView.textStorage else { NSSound.beep(); return }
        let search = bar.search
        guard let regex = try? search.expression() else { return }
        let match = matches[index]
        let replacement = search.replacement(for: match, in: textView.string,
                                             template: bar.replaceField.stringValue, using: regex)
        guard textView.shouldChangeText(in: match.range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: match.range, with: replacement)
        textView.didChangeText()
        textView.undoManager?.setActionName("Replace")
        // Carry on from just past the replacement, so a replacement that itself matches
        // is not found again.
        let end = match.range.location + (replacement as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        runSearch(selectingMatch: true)
    }

    /// Finds every match afresh — not just the highlighted ones, which stop at
    /// matchLimit — and replaces them in one edit, so a single Undo takes it all back.
    private func replaceAll() {
        let search = bar.search
        guard !search.query.isEmpty, let regex = try? search.expression() else { NSSound.beep(); return }
        cancelSearch()
        let template = bar.replaceField.stringValue
        let text = textView.string
        let token = SearchCancellation()
        runningSearch = token
        queue.async { [weak self] in
            let found = TextSearch.matches(of: regex, in: text, limit: .max, cancellation: token)
            let replacements = found.map { search.replacement(for: $0, in: text, template: template, using: regex) }
            DispatchQueue.main.async {
                guard let self, self.runningSearch === token, !token.isCancelled else { return }
                self.runningSearch = nil
                self.commitReplaceAll(found.map(\.range), with: replacements)
            }
        }
    }

    private func commitReplaceAll(_ ranges: [NSRange], with replacements: [String]) {
        guard !ranges.isEmpty, let storage = textView.textStorage else {
            NSSound.beep()
            runSearch(selectingMatch: false)
            return
        }
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                                        replacementStrings: replacements) else { return }
        storage.beginEditing()
        // Back to front, so each range is still where it was found.
        for (range, replacement) in zip(ranges, replacements).reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName("Replace All")
        runSearch(selectingMatch: false, note: "Replaced \(ranges.count)")
    }

    // MARK: Highlights & status

    /// Temporary attributes live in the editor's layout manager only: they don't touch
    /// the text (or the file), and don't invalidate its layout.
    private func highlightMatches() {
        clearHighlights()
        guard isVisible, let layoutManager = textView.layoutManager else { return }
        for match in matches {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.matchColor, forCharacterRange: match.range)
        }
        if let current {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.currentMatchColor,
                                                forCharacterRange: matches[current].range)
        }
    }

    private func clearHighlights() {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor,
                                               forCharacterRange: NSRange(location: 0, length: storage.length))
    }

    private func updateStatus(note: String? = nil) {
        if let note {
            bar.setStatus(note)
        } else if bar.searchField.stringValue.isEmpty {
            bar.setStatus("")
        } else if matches.isEmpty {
            bar.setStatus("No results")
        } else {
            let total = "\(matches.count)\(isTruncated ? "+" : "")"
            guard let current else { bar.setStatus(total); return }
            bar.setStatus(matches.count < 1_000 ? "\(current + 1) of \(total)" : "\(current + 1)/\(total)")
        }
    }

    // MARK: The shared find string
    //
    // macOS keeps the last searched-for text on a system-wide pasteboard, so ⌘E in one
    // app and ⌘G in another find the same thing.

    private static func sharedFindString() -> String? {
        let string = NSPasteboard(name: .find).string(forType: .string)
        return string?.isEmpty == false ? string : nil
    }

    private static func shareFindString(_ string: String) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: FindBarDelegate

    func findBarSearchDidChange(_ bar: FindBarView) {
        runSearch(selectingMatch: true)
    }

    func findBar(_ bar: FindBarView, move direction: FindBarView.Direction) {
        go(direction)
    }

    func findBar(_ bar: FindBarView, replaceAll: Bool) {
        if replaceAll {
            self.replaceAll()
        } else {
            whenResultsAreCurrent { [weak self] in self?.replaceCurrent() }
        }
    }

    func findBarDidClose(_ bar: FindBarView) {
        hide()
    }
}

protocol FindBarDelegate: AnyObject {
    func findBarSearchDidChange(_ bar: FindBarView)
    func findBar(_ bar: FindBarView, move direction: FindBarView.Direction)
    func findBar(_ bar: FindBarView, replaceAll: Bool)
    func findBarDidClose(_ bar: FindBarView)
}

/// The find & replace bar: a small glass panel at the top-right of the editor.
final class FindBarView: NSView, NSTextFieldDelegate {
    enum Direction { case next, previous }

    static let width: CGFloat = 404.0
    private static let rowHeight: CGFloat = 28.0
    private static let padding: CGFloat = 8.0
    private static let rowGap: CGFloat = 6.0

    weak var delegate: FindBarDelegate?

    private let glass = NSGlassEffectView(frame: .zero)
    private let content = FlippedContentView(frame: .zero)
    private let searchWell = FindFieldWell(placeholder: "Find")
    private let replaceWell = FindFieldWell(placeholder: "Replace")
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var regexToggle = makeToggle(".*", tooltip: "Regular expression")
    private lazy var caseToggle = makeToggle("Aa", tooltip: "Match case")
    private lazy var previousButton = makeIconButton("chevron.up", tooltip: "Previous match (⇧⌘G)", action: #selector(goPrevious))
    private lazy var nextButton = makeIconButton("chevron.down", tooltip: "Next match (⌘G)", action: #selector(goNext))
    private lazy var closeButton = makeIconButton("xmark", tooltip: "Close (Esc)", action: #selector(close))
    private lazy var replaceButton = makeTextButton("Replace", action: #selector(replaceOne))
    private lazy var replaceAllButton = makeTextButton("All", action: #selector(replaceEverything))

    var searchField: NSTextField { searchWell.field }
    var statusText: String { statusLabel.stringValue }

    var usesRegex: Bool {
        get { regexToggle.state == .on }
        set { regexToggle.state = newValue ? .on : .off; styleToggle(regexToggle) }
    }

    var isCaseSensitive: Bool {
        get { caseToggle.state == .on }
        set { caseToggle.state = newValue ? .on : .off; styleToggle(caseToggle) }
    }
    var replaceField: NSTextField { replaceWell.field }

    var search: TextSearch {
        TextSearch(query: searchField.stringValue,
                   usesRegex: regexToggle.state == .on,
                   caseSensitive: caseToggle.state == .on)
    }

    var showsReplace = false {
        didSet {
            replaceWell.isHidden = !showsReplace
            replaceButton.isHidden = !showsReplace
            replaceAllButton.isHidden = !showsReplace
            needsLayout = true
        }
    }

    var preferredSize: NSSize {
        let rows: CGFloat = showsReplace ? 2.0 : 1.0
        let height = Self.padding * 2.0 + Self.rowHeight * rows + (showsReplace ? Self.rowGap : 0.0)
        return NSSize(width: Self.width, height: height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Frosted rather than clear: the bar floats over text, which must not show
        // through sharply enough to fight with the query.
        glass.style = .regular
        glass.tintColor = NSColor(calibratedWhite: 0.0, alpha: 0.3)
        glass.cornerRadius = 14.0
        addSubview(glass)
        // Content sits above the glass as a sibling, not inside its contentView — see
        // GlassEditorView.setupView for why (snapshots drop the glass's contents).
        addSubview(content)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        statusLabel.textColor = NSColor(calibratedWhite: 1.0, alpha: 0.55)
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byClipping

        for field in [searchField, replaceField] { field.delegate = self }
        searchField.nextKeyView = replaceField
        replaceField.nextKeyView = searchField
        for view in [searchWell, statusLabel, regexToggle, caseToggle, previousButton, nextButton,
                     closeButton, replaceWell, replaceButton, replaceAllButton] as [NSView] {
            content.addSubview(view)
        }
        showsReplace = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The window is movable by its background, and the bar's own background (the glass,
    // the content view) would otherwise count as part of it: a click that just missed a
    // button would start dragging the whole window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === content || hit === glass || hit?.isDescendant(of: glass) == true { return self }
        return hit
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds

        let p = Self.padding, h = Self.rowHeight
        var x = bounds.width - p
        // Lays controls out right to left, each vertically centred in its row.
        func place(_ view: NSView, width: CGFloat, height: CGFloat = 24.0, row y: CGFloat, gap: CGFloat = 2.0) {
            x -= width
            view.frame = NSRect(x: x, y: y + (h - height) / 2.0, width: width, height: height)
            x -= gap
        }
        place(closeButton, width: 24.0, row: p)
        place(nextButton, width: 24.0, row: p)
        place(previousButton, width: 24.0, row: p, gap: 6.0)
        place(caseToggle, width: 28.0, row: p)
        place(regexToggle, width: 28.0, row: p, gap: 6.0)
        place(statusLabel, width: 70.0, height: 16.0, row: p, gap: 6.0)
        searchWell.frame = NSRect(x: p, y: p, width: x - p, height: h)

        guard showsReplace else { return }
        let y = p + h + Self.rowGap
        x = bounds.width - p
        place(replaceAllButton, width: 40.0, row: y)
        place(replaceButton, width: 66.0, row: y, gap: 6.0)
        replaceWell.frame = NSRect(x: p, y: y, width: x - p, height: h)
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError
            ? NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.5, alpha: 0.95)
            : NSColor(calibratedWhite: 1.0, alpha: 0.55)
        searchWell.isInvalid = isError
    }

    /// Puts a string into the search field — escaped if the regex toggle is on, so the
    /// text is found literally either way.
    func setQuery(literal text: String) {
        searchField.stringValue = regexToggle.state == .on ? NSRegularExpression.escapedPattern(for: text) : text
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    // MARK: Text field delegate

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === searchField else { return }
        delegate?.findBarSearchDidChange(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if control === replaceField {
                delegate?.findBar(self, replaceAll: false)
            } else {
                delegate?.findBar(self, move: backwards ? .previous : .next)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.findBarDidClose(self)
            return true
        default:
            return false
        }
    }

    // MARK: Actions

    @objc private func toggleChanged(_ sender: NSButton) {
        styleToggle(sender)
        delegate?.findBarSearchDidChange(self)
    }
    @objc private func goNext() { delegate?.findBar(self, move: .next) }
    @objc private func goPrevious() { delegate?.findBar(self, move: .previous) }
    @objc private func close() { delegate?.findBarDidClose(self) }
    @objc private func replaceOne() { delegate?.findBar(self, replaceAll: false) }
    @objc private func replaceEverything() { delegate?.findBar(self, replaceAll: true) }

    // MARK: Controls

    private func makeToggle(_ title: String, tooltip: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(toggleChanged(_:)))
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6.0
        styleToggle(button)
        return button
    }

    private func styleToggle(_ button: NSButton) {
        let on = button.state == .on
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: on ? .bold : .medium),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: on ? 0.95 : 0.45)
        ])
        button.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: on ? 0.16 : 0.0).cgColor
    }

    private func makeIconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 11.0, weight: .semibold))
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = NSColor(calibratedWhite: 1.0, alpha: 0.75)
        button.toolTip = tooltip
        return button
    }

    private func makeTextButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7.0
        button.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12.0, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.85)
        ])
        return button
    }
}

/// A borderless text field sitting in a softly lit rounded well, vertically centred —
/// a plain NSTextField would pin its text to the top of a taller frame.
final class FindFieldWell: NSView {
    let field = NSTextField(frame: .zero)

    var isInvalid = false {
        didSet { layer?.borderWidth = isInvalid ? 1.0 : 0.0 }
    }

    init(placeholder: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8.0
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.09).cgColor
        layer?.borderColor = NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.45, alpha: 0.8).cgColor

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 13.0, weight: .regular)
        field.textColor = NSColor(calibratedWhite: 1.0, alpha: 0.92)
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.38)
        ])
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    // A click anywhere in the well, not only on the line of text, goes to the field.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === self ? field : hit
    }

    override func layout() {
        super.layout()
        let height = field.intrinsicContentSize.height
        field.frame = NSRect(x: 8.0, y: (bounds.height - height) / 2.0, width: bounds.width - 16.0, height: height)
    }
}
