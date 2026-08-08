//
//  SyntaxHighlightedEditor.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit

// MARK: - SQL Syntax Highlighter

/// Handles SQL syntax highlighting with regex-based pattern matching
private struct SQLSyntaxHighlighter {

    static let maxHighlightingLength = 50_000

    // Compiled regex patterns (created once)
    let patterns: Patterns

    struct Patterns {
        let keyword: NSRegularExpression
        let string: NSRegularExpression
        let number: NSRegularExpression
        let singleLineComment: NSRegularExpression
        let multiLineComment: NSRegularExpression
        let `operator`: NSRegularExpression
        let function: NSRegularExpression

        init() {
            do {
                keyword = try NSRegularExpression(
                    pattern: "\\b(SELECT|FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|ON|AS|ORDER|BY|GROUP|HAVING|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|DATABASE|SCHEMA|UNION|INTERSECT|EXCEPT|DISTINCT|LIMIT|OFFSET|CASE|WHEN|THEN|ELSE|END|IF|EXISTS|NULL|NOT|AND|OR|IN|LIKE|ILIKE|SIMILAR|TO|BETWEEN|IS|CAST|COALESCE|NULLIF|GREATEST|LEAST|EXTRACT|DATE_PART|NOW|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|TRUE|FALSE|BOOLEAN|INTEGER|BIGINT|SMALLINT|DECIMAL|NUMERIC|REAL|DOUBLE|PRECISION|CHAR|VARCHAR|TEXT|BYTEA|DATE|TIME|TIMESTAMP|INTERVAL|ARRAY|JSON|JSONB|UUID|SERIAL|BIGSERIAL|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|DEFAULT|CONSTRAINT|USING|WITH|WITHOUT|OIDS|TABLESPACE|STORAGE|PARAMETER|SET|RESET|SHOW|GRANT|REVOKE|EXPLAIN|ANALYZE|VACUUM|REINDEX|CLUSTER|TRUNCATE|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|TRANSACTION|ISOLATION|LEVEL|READ|WRITE|ONLY|UNCOMMITTED|COMMITTED|REPEATABLE|SERIALIZABLE|LOCK|FOR|UPDATE|SHARE|NOWAIT|SKIP|LOCKED|RETURNING|RETURNS|LANGUAGE|PLPGSQL|FUNCTION|PROCEDURE|TRIGGER|SEQUENCE|TYPE|DOMAIN|ENUM|AGGREGATE|OPERATOR|OPERATOR\\s+CLASS|OPERATOR\\s+FAMILY|RULE|POLICY|EXTENSION|COLLATION|CONVERSION|TEXT\\s+SEARCH|CONFIGURATION|DICTIONARY|PARSER|TEMPLATE|ROLE|USER|GROUP|PASSWORD|SUPERUSER|CREATEDB|CREATEROLE|INHERIT|LOGIN|REPLICATION|BYPASSRLS|CONNECTION\\s+LIMIT|VALID|UNTIL|IN\\s+SCHEMA|PUBLIC|CURRENT_SCHEMA|SEARCH_PATH)\\b",
                    options: [.caseInsensitive]
                )
                string = try NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'", options: [])
                number = try NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: [])
                singleLineComment = try NSRegularExpression(pattern: "--.*", options: [])
                multiLineComment = try NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/", options: [.dotMatchesLineSeparators])
                `operator` = try NSRegularExpression(pattern: "::|->>|->|@>|<@|\\?\\||\\?&|\\?|<=|>=|<>|!=|[=<>!+\\-*/%&|^~]", options: [])
                function = try NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*\\(", options: [])
            } catch {
                fatalError("Failed to compile regex patterns: \(error)")
            }
        }
    }

    struct Colors {
        let keyword: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let `operator`: NSColor
        let function: NSColor
        let `default`: NSColor

        init(isDark: Bool) {
            if isDark {
                keyword = .systemBlue
                string = .systemGreen
                number = .systemOrange
                comment = .systemGray
                `operator` = .systemPink
                function = .systemCyan
            } else {
                keyword = NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
                string = NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)
                number = NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
                comment = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
                `operator` = NSColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1.0)
                function = NSColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 1.0)
            }
            `default` = .textColor
        }
    }

    init() {
        self.patterns = Patterns()
    }

    /// Apply syntax highlighting to text storage (incremental, for user typing)
    func highlightIncremental(_ textStorage: NSTextStorage, isDark: Bool) {
        let text = textStorage.string
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return }

        let colors = Colors(isDark: isDark)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            textStorage.addAttribute(.foregroundColor, value: color, range: range)
        }
        textStorage.endEditing()
    }

    /// Apply syntax highlighting and return attributed string (for external text updates)
    func highlight(_ text: String, isDark: Bool) -> NSAttributedString? {
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return nil }

        let colors = Colors(isDark: isDark)
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        attributed.addAttribute(.font, value: font, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    /// Core pattern matching logic - shared between both highlighting methods
    private func applyPatterns(to text: String, colors: Colors, apply: (NSRange, NSColor) -> Void) {
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        var protected = IndexSet()

        func isProtected(_ range: NSRange) -> Bool {
            range.length > 0 && protected.contains(integersIn: range.location..<(range.location + range.length))
        }

        func protect(_ range: NSRange) {
            if range.length > 0 {
                protected.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        // Order matters: comments > strings > numbers/keywords/functions/operators
        let orderedPatterns: [(NSRegularExpression, NSColor, Bool)] = [
            (patterns.multiLineComment, colors.comment, true),
            (patterns.singleLineComment, colors.comment, true),
            (patterns.string, colors.string, true),
            (patterns.number, colors.number, false),
            (patterns.keyword, colors.keyword, false),
            (patterns.function, colors.function, false),
            (patterns.operator, colors.operator, false),
        ]

        for (pattern, color, shouldProtect) in orderedPatterns {
            pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                var range = match.range

                // For functions, exclude the opening paren
                if pattern === patterns.function {
                    range = NSRange(location: range.location, length: range.length - 1)
                }

                if !isProtected(range) {
                    apply(range, color)
                    if shouldProtect { protect(range) }
                }
            }
        }
    }
}

// MARK: - Syntax Highlighted Editor

struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    let metadataProvider: DatabaseMetadataProvider?
    @Environment(\.colorScheme) var colorScheme

    init(
        text: Binding<String>,
        metadataProvider: DatabaseMetadataProvider? = nil
    ) {
        self._text = text
        self.metadataProvider = metadataProvider
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = AutocompleteTextView()

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Disable automatic text substitutions for code editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Set up scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        // Line numbers
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = lineNumberRuler

        // Set delegate and store references
        textView.delegate = context.coordinator
        textView.autocompleteDelegate = context.coordinator
        context.coordinator.attach(textView: textView, lineNumberRuler: lineNumberRuler)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? AutocompleteTextView else { return }

        context.coordinator.parent = self

        let isDark = colorScheme == .dark
        let colorSchemeChanged = context.coordinator.lastIsDark != isDark
        context.coordinator.lastIsDark = isDark

        if textView.string != text && !context.coordinator.isUpdatingFromUserInput {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
            context.coordinator.lineNumberRuler?.needsDisplay = true
            context.coordinator.scheduleAutocompleteRefresh(after: 0)
        } else if colorSchemeChanged {
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate, AutocompleteTextViewDelegate {
        fileprivate var parent: SyntaxHighlightedEditor
        private let highlighter = SQLSyntaxHighlighter()
        private let suggestionState = AutocompleteSuggestionListState()
        private lazy var suggestionHostingController = NSHostingController(
            rootView: AutocompleteSuggestionListView(state: suggestionState) { [weak self] suggestion in
                self?.insertSuggestion(suggestion)
            }
        )
        private lazy var autocompletePopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = suggestionHostingController
            return popover
        }()
        private var highlightingWorkItem: DispatchWorkItem?
        private var autocompleteWorkItem: DispatchWorkItem?
        private var autocompleteTask: Task<Void, Never>?
        private var autocompleteRequestID = 0
        private var latestAnalysis: SQLContextAnalysis?
        private var isApplyingSuggestion = false

        weak var textView: AutocompleteTextView?
        weak var lineNumberRuler: LineNumberRulerView?
        var isUpdatingFromUserInput = false
        var lastIsDark = false
        var isAutocompleteVisible: Bool {
            autocompletePopover.isShown
        }

        init(parent: SyntaxHighlightedEditor) {
            self.parent = parent
            self.lastIsDark = parent.colorScheme == .dark
        }

        deinit {
            highlightingWorkItem?.cancel()
            autocompleteWorkItem?.cancel()
            autocompleteTask?.cancel()
        }

        func attach(textView: AutocompleteTextView, lineNumberRuler: LineNumberRulerView) {
            self.textView = textView
            self.lineNumberRuler = lineNumberRuler
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }

            isUpdatingFromUserInput = true
            parent.text = textView.string
            lineNumberRuler?.needsDisplay = true

            // Debounce highlighting
            highlightingWorkItem?.cancel()
            let isDark = lastIsDark
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView, let storage = textView.textStorage else { return }
                self.highlighter.highlightIncremental(storage, isDark: isDark)
                self.isUpdatingFromUserInput = false
            }
            highlightingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)

            guard !isApplyingSuggestion else {
                return
            }

            scheduleAutocompleteRefresh(after: 0.15)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            lineNumberRuler?.needsDisplay = true

            guard !isApplyingSuggestion else {
                return
            }

            scheduleAutocompleteRefresh(after: 0)
        }

        func textDidEndEditing(_ notification: Notification) {
            closeAutocomplete()
        }

        func applyHighlighting(to textView: NSTextView, isDark: Bool) {
            guard let attributed = highlighter.highlight(textView.string, isDark: isDark),
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let wasFirstResponder = textView.window?.firstResponder === textView

            textStorage.beginEditing()
            textStorage.setAttributedString(attributed)
            textStorage.endEditing()

            // Restore selection
            let maxLocation = textView.string.utf16.count
            let validLocation = min(selectedRange.location, maxLocation)
            let validLength = min(selectedRange.length, maxLocation - validLocation)

            DispatchQueue.main.async {
                textView.setSelectedRange(NSRange(location: validLocation, length: validLength))
                if wasFirstResponder {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }

        func scheduleAutocompleteRefresh(after delay: TimeInterval) {
            autocompleteWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.refreshAutocomplete()
            }
            autocompleteWorkItem = workItem

            if delay <= 0 {
                DispatchQueue.main.async(execute: workItem)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }

        func autocompleteTextView(
            _ textView: AutocompleteTextView,
            moveSelection direction: AutocompleteSelectionDirection
        ) -> Bool {
            guard isAutocompleteVisible else {
                return false
            }

            switch direction {
            case .up:
                suggestionState.moveSelection(by: -1)
            case .down:
                suggestionState.moveSelection(by: 1)
            }

            return true
        }

        func autocompleteTextViewInsertSelectedSuggestion(_ textView: AutocompleteTextView) -> Bool {
            guard let suggestion = suggestionState.selectedSuggestion else {
                return false
            }

            insertSuggestion(suggestion)
            return true
        }

        func autocompleteTextViewDismissSuggestions(_ textView: AutocompleteTextView) -> Bool {
            guard isAutocompleteVisible else {
                return false
            }

            closeAutocomplete()
            return true
        }

        private func refreshAutocomplete() {
            autocompleteTask?.cancel()

            guard let textView,
                  let metadataProvider = parent.metadataProvider,
                  textView.window?.firstResponder === textView else {
                closeAutocomplete()
                return
            }

            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else {
                closeAutocomplete()
                return
            }

            let text = textView.string
            let textLength = (text as NSString).length
            guard selectedRange.location <= textLength else {
                closeAutocomplete()
                return
            }

            let caretIndex = String.Index(utf16Offset: selectedRange.location, in: text)
            let analysis = SQLContextAnalyzer.analyze(text, upTo: caretIndex)
            guard analysis.context != .none else {
                closeAutocomplete()
                return
            }

            autocompleteRequestID += 1
            let requestID = autocompleteRequestID

            autocompleteTask = Task { [weak self] in
                let suggestions = await AutocompleteEngine.suggestions(
                    for: analysis,
                    provider: metadataProvider
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard let self, requestID == self.autocompleteRequestID else {
                        return
                    }

                    self.presentSuggestions(suggestions, analysis: analysis)
                }
            }
        }

        private func presentSuggestions(
            _ suggestions: [SuggestionItem],
            analysis: SQLContextAnalysis
        ) {
            guard let textView,
                  !suggestions.isEmpty,
                  let caretRect = textView.calculateCaretRect(),
                  textView.window != nil else {
                closeAutocomplete()
                return
            }

            latestAnalysis = analysis
            suggestionState.apply(suggestions)
            autocompletePopover.contentSize = NSSize(
                width: 360,
                height: popoverHeight(for: suggestions.count)
            )

            if autocompletePopover.isShown {
                autocompletePopover.performClose(nil)
            }

            autocompletePopover.show(relativeTo: caretRect, of: textView, preferredEdge: .maxY)
            textView.window?.makeFirstResponder(textView)
        }

        private func popoverHeight(for suggestionCount: Int) -> CGFloat {
            let visibleRowCount = min(max(suggestionCount, 1), 8)
            return CGFloat(visibleRowCount) * 32 + 12
        }

        private func closeAutocomplete() {
            autocompleteTask?.cancel()
            autocompleteTask = nil
            autocompleteRequestID += 1
            latestAnalysis = nil
            suggestionState.apply([])

            if autocompletePopover.isShown {
                autocompletePopover.performClose(nil)
            }
        }

        private func insertSuggestion(_ suggestion: SuggestionItem) {
            guard let textView,
                  let analysis = latestAnalysis else {
                return
            }

            let replacementRange = clampedRange(
                analysis.replacementRange.nsRange,
                in: textView.string
            )

            guard textView.shouldChangeText(
                in: replacementRange,
                replacementString: suggestion.replacementText
            ) else {
                return
            }

            isApplyingSuggestion = true
            closeAutocomplete()

            textView.textStorage?.replaceCharacters(
                in: replacementRange,
                with: suggestion.replacementText
            )

            let insertedLength = (suggestion.replacementText as NSString).length
            let caretLocation = replacementRange.location + insertedLength
            textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
            textView.didChangeText()
            lineNumberRuler?.needsDisplay = true
            textView.window?.makeFirstResponder(textView)

            DispatchQueue.main.async { [weak self] in
                self?.isApplyingSuggestion = false
            }
        }

        private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
            let textLength = (text as NSString).length
            let location = min(max(range.location, 0), textLength)
            let length = min(max(range.length, 0), textLength - location)
            return NSRange(location: location, length: length)
        }
    }
}
