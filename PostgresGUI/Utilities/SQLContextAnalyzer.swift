//
//  SQLContextAnalyzer.swift
//  PostgresGUI
//
//  Lightweight lexical analyzer for SQL autocomplete context detection.
//

import Foundation

enum SQLContextAnalyzer {
    nonisolated static func analyze(_ query: String, upTo caretIndex: String.Index) -> SQLContextAnalysis {
        let statementRange = activeStatementRange(in: query, containing: caretIndex)
        let activeStatement = String(query[statementRange])
        let caretOffset = query.distance(from: statementRange.lowerBound, to: caretIndex)
        let statementCaretIndex = activeStatement.index(activeStatement.startIndex, offsetBy: caretOffset)
        let caretRange = TextSelectionRange(
            location: NSRange(caretIndex..<caretIndex, in: query).location,
            length: 0
        )

        if isCaretInsideIgnoredSpan(in: activeStatement, at: statementCaretIndex) {
            return SQLContextAnalysis(
                context: .none,
                currentWord: "",
                activeStatement: activeStatement,
                aliasMap: [:],
                replacementRange: caretRange
            )
        }

        let currentWordRange = currentWordRange(in: activeStatement, upTo: statementCaretIndex)
        let currentWord = String(activeStatement[currentWordRange])
        let replacementRange = replacementRange(
            in: query,
            statementRange: statementRange,
            currentWordRange: currentWordRange
        )
        let tokens = tokenize(activeStatement)
        let scopeDepth = nestingDepth(in: activeStatement, upTo: statementCaretIndex)
        let aliasMap = resolveAliases(in: tokens, scopeDepth: scopeDepth)
        let context = determineContext(
            in: tokens,
            statement: activeStatement,
            currentWordRange: currentWordRange,
            scopeDepth: scopeDepth
        )

        return SQLContextAnalysis(
            context: context,
            currentWord: currentWord,
            activeStatement: activeStatement,
            aliasMap: aliasMap,
            replacementRange: replacementRange
        )
    }

    nonisolated static func determineContext(in query: String, upTo caretIndex: String.Index) -> AutocompleteContext {
        analyze(query, upTo: caretIndex).context
    }

    private struct Token {
        enum Kind {
            case word(String, quoted: Bool)
            case dot
            case comma
            case openParen
            case closeParen
            case semicolon
        }

        let kind: Kind
        let depth: Int
        let range: Range<String.Index>

        nonisolated var word: String? {
            guard case let .word(value, _) = kind else {
                return nil
            }

            return value
        }

        nonisolated var isQuotedWord: Bool {
            guard case let .word(_, quoted) = kind else {
                return false
            }

            return quoted
        }

        nonisolated func matchesKeyword(_ keyword: String) -> Bool {
            guard let word, !isQuotedWord else {
                return false
            }

            return word.caseInsensitiveCompare(keyword) == .orderedSame
        }

        nonisolated var isDot: Bool {
            guard case .dot = kind else {
                return false
            }

            return true
        }

        nonisolated var isComma: Bool {
            guard case .comma = kind else {
                return false
            }

            return true
        }

        nonisolated var isOpenParen: Bool {
            guard case .openParen = kind else {
                return false
            }

            return true
        }

        nonisolated var isCloseParen: Bool {
            guard case .closeParen = kind else {
                return false
            }

            return true
        }

        nonisolated var isSemicolon: Bool {
            guard case .semicolon = kind else {
                return false
            }

            return true
        }
    }

    private enum PivotContext {
        case tablesAndSchemas
        case columnsGlobal
        case keywords
    }

    private struct ParsedRelationReference {
        let reference: SQLRelationReference?
        let alias: String?
        let nextIndex: Int
    }

    private nonisolated static func determineContext(
        in tokens: [Token],
        statement: String,
        currentWordRange: Range<String.Index>,
        scopeDepth: Int
    ) -> AutocompleteContext {
        let pivotContext = pivotContext(
            in: tokens,
            prefixLimit: currentWordRange.lowerBound,
            scopeDepth: scopeDepth
        )

        if let qualifier = qualifierBeforeCurrentWord(in: tokens, prefixLimit: currentWordRange.lowerBound) {
            switch pivotContext {
            case .tablesAndSchemas:
                return .tablesAndSchemas(schemaQualifier: qualifier)
            case .columnsGlobal, .keywords:
                return .columnsSpecific(alias: qualifier)
            }
        }

        switch pivotContext {
        case .tablesAndSchemas:
            return .tablesAndSchemas(schemaQualifier: nil)
        case .columnsGlobal:
            return .columnsGlobal
        case .keywords:
            let trimmedPrefix = statement[..<currentWordRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPrefix.isEmpty ? .keywords : .keywords
        }
    }

    private nonisolated static func pivotContext(
        in tokens: [Token],
        prefixLimit: String.Index,
        scopeDepth: Int
    ) -> PivotContext {
        let relevantTokens = tokens.filter {
            $0.depth == scopeDepth && $0.range.upperBound <= prefixLimit
        }

        guard !relevantTokens.isEmpty else {
            return .keywords
        }

        var index = relevantTokens.count - 1

        while index >= 0 {
            let token = relevantTokens[index]

            if token.matchesKeyword("BY"), index > 0 {
                let previousToken = relevantTokens[index - 1]
                if previousToken.matchesKeyword("GROUP") || previousToken.matchesKeyword("ORDER") {
                    return .columnsGlobal
                }
            }

            if token.matchesKeyword("FROM")
                || token.matchesKeyword("JOIN")
                || token.matchesKeyword("INTO")
                || token.matchesKeyword("UPDATE") {
                return .tablesAndSchemas
            }

            if token.matchesKeyword("SELECT")
                || token.matchesKeyword("WHERE")
                || token.matchesKeyword("HAVING")
                || token.matchesKeyword("ON")
                || token.matchesKeyword("SET")
                || token.matchesKeyword("RETURNING") {
                return .columnsGlobal
            }

            index -= 1
        }

        return .keywords
    }

    private nonisolated static func qualifierBeforeCurrentWord(
        in tokens: [Token],
        prefixLimit: String.Index
    ) -> String? {
        let relevantTokens = tokens.filter {
            $0.range.upperBound <= prefixLimit
        }

        guard relevantTokens.count >= 2 else {
            return nil
        }

        let dotToken = relevantTokens[relevantTokens.count - 1]
        let qualifierToken = relevantTokens[relevantTokens.count - 2]

        guard dotToken.isDot, let qualifier = qualifierToken.word else {
            return nil
        }

        return qualifier
    }

    private nonisolated static func resolveAliases(
        in tokens: [Token],
        scopeDepth: Int
    ) -> [String: SQLRelationReference] {
        var aliasMap: [String: SQLRelationReference] = [:]

        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            if token.depth != scopeDepth {
                index += 1
                continue
            }

            if token.matchesKeyword("FROM") {
                index = parseFromClause(
                    from: index + 1,
                    tokens: tokens,
                    scopeDepth: scopeDepth,
                    aliasMap: &aliasMap
                )
                continue
            }

            if token.matchesKeyword("JOIN") || token.matchesKeyword("UPDATE") {
                let parsed = parseRelationReference(from: index + 1, tokens: tokens, scopeDepth: scopeDepth)
                store(reference: parsed.reference, alias: parsed.alias, in: &aliasMap)
                index = max(parsed.nextIndex, index + 1)
                continue
            }

            index += 1
        }

        return aliasMap
    }

    private nonisolated static func parseFromClause(
        from startIndex: Int,
        tokens: [Token],
        scopeDepth: Int,
        aliasMap: inout [String: SQLRelationReference]
    ) -> Int {
        var index = startIndex

        while index < tokens.count {
            let token = tokens[index]

            if token.depth != scopeDepth {
                index += 1
                continue
            }

            if isClauseTerminator(token) {
                break
            }

            if token.isComma {
                index += 1
                continue
            }

            if token.matchesKeyword("JOIN") {
                break
            }

            let parsed = parseRelationReference(from: index, tokens: tokens, scopeDepth: scopeDepth)
            store(reference: parsed.reference, alias: parsed.alias, in: &aliasMap)

            if parsed.nextIndex == index {
                index += 1
            } else {
                index = parsed.nextIndex
            }
        }

        return index
    }

    private nonisolated static func parseRelationReference(
        from startIndex: Int,
        tokens: [Token],
        scopeDepth: Int
    ) -> ParsedRelationReference {
        var index = startIndex

        while index < tokens.count {
            let token = tokens[index]

            if token.depth != scopeDepth {
                index += 1
                continue
            }

            if token.matchesKeyword("ONLY") || token.matchesKeyword("LATERAL") {
                index += 1
                continue
            }

            break
        }

        guard index < tokens.count else {
            return ParsedRelationReference(reference: nil, alias: nil, nextIndex: index)
        }

        let token = tokens[index]

        if token.isOpenParen {
            return ParsedRelationReference(reference: nil, alias: nil, nextIndex: index + 1)
        }

        guard let firstIdentifier = token.word else {
            return ParsedRelationReference(reference: nil, alias: nil, nextIndex: index + 1)
        }

        var schemaName: String?
        var relationName = firstIdentifier
        var nextIndex = index + 1

        if nextIndex + 1 < tokens.count,
           tokens[nextIndex].depth == scopeDepth,
           tokens[nextIndex].isDot,
           tokens[nextIndex + 1].depth == scopeDepth,
           let secondIdentifier = tokens[nextIndex + 1].word {
            schemaName = firstIdentifier
            relationName = secondIdentifier
            nextIndex += 2
        }

        if nextIndex < tokens.count,
           tokens[nextIndex].depth == scopeDepth,
           tokens[nextIndex].matchesKeyword("AS") {
            nextIndex += 1
        }

        var alias: String?
        if nextIndex < tokens.count,
           tokens[nextIndex].depth == scopeDepth,
           let aliasCandidate = tokens[nextIndex].word,
           !isReservedAliasBoundary(tokens[nextIndex]) {
            alias = aliasCandidate
            nextIndex += 1
        }

        let reference = SQLRelationReference(schemaName: schemaName, relationName: relationName)

        return ParsedRelationReference(reference: reference, alias: alias, nextIndex: nextIndex)
    }

    private nonisolated static func store(
        reference: SQLRelationReference?,
        alias: String?,
        in aliasMap: inout [String: SQLRelationReference]
    ) {
        guard let reference else {
            return
        }

        aliasMap[reference.relationName.lowercased()] = reference

        if let alias {
            aliasMap[alias.lowercased()] = reference
        }
    }

    private nonisolated static func isClauseTerminator(_ token: Token) -> Bool {
        token.matchesKeyword("WHERE")
            || token.matchesKeyword("GROUP")
            || token.matchesKeyword("ORDER")
            || token.matchesKeyword("HAVING")
            || token.matchesKeyword("LIMIT")
            || token.matchesKeyword("OFFSET")
            || token.matchesKeyword("UNION")
            || token.matchesKeyword("INTERSECT")
            || token.matchesKeyword("EXCEPT")
            || token.matchesKeyword("RETURNING")
            || token.matchesKeyword("SET")
            || token.matchesKeyword("VALUES")
            || token.matchesKeyword("ON")
            || token.matchesKeyword("USING")
            || token.isSemicolon
    }

    private nonisolated static func isReservedAliasBoundary(_ token: Token) -> Bool {
        isClauseTerminator(token)
            || token.matchesKeyword("JOIN")
            || token.matchesKeyword("INNER")
            || token.matchesKeyword("LEFT")
            || token.matchesKeyword("RIGHT")
            || token.matchesKeyword("FULL")
            || token.matchesKeyword("CROSS")
            || token.matchesKeyword("OUTER")
            || token.matchesKeyword("NATURAL")
            || token.isComma
            || token.isCloseParen
            || token.isDot
    }

    private nonisolated static func currentWordRange(
        in statement: String,
        upTo caretIndex: String.Index
    ) -> Range<String.Index> {
        var start = caretIndex

        while start > statement.startIndex {
            let previousIndex = statement.index(before: start)
            guard isIdentifierBody(statement[previousIndex]) else {
                break
            }
            start = previousIndex
        }

        return start..<caretIndex
    }

    private nonisolated static func replacementRange(
        in query: String,
        statementRange: Range<String.Index>,
        currentWordRange: Range<String.Index>
    ) -> TextSelectionRange {
        let statementNSRange = NSRange(statementRange, in: query)
        let activeStatement = String(query[statementRange])
        let currentWordNSRange = NSRange(currentWordRange, in: activeStatement)

        return TextSelectionRange(
            location: statementNSRange.location + currentWordNSRange.location,
            length: currentWordNSRange.length
        )
    }

    private nonisolated static func activeStatementRange(
        in query: String,
        containing caretIndex: String.Index
    ) -> Range<String.Index> {
        var statementStart = query.startIndex
        var statementEnd = query.endIndex
        var index = query.startIndex

        while index < query.endIndex {
            if let advancedIndex = advanceIfLineComment(in: query, from: index)
                ?? advanceIfBlockComment(in: query, from: index)
                ?? advanceIfSingleQuotedString(in: query, from: index)
                ?? advanceIfDollarQuotedString(in: query, from: index) {
                index = advancedIndex
                continue
            }

            if query[index] == ";" {
                let nextIndex = query.index(after: index)
                if nextIndex <= caretIndex {
                    statementStart = nextIndex
                } else {
                    statementEnd = index
                    break
                }
            }

            index = query.index(after: index)
        }

        return statementStart..<statementEnd
    }

    private nonisolated static func isCaretInsideIgnoredSpan(
        in statement: String,
        at caretIndex: String.Index
    ) -> Bool {
        var index = statement.startIndex

        while index < statement.endIndex {
            if let ignoredRange = ignoredRangeIfPresent(in: statement, from: index) {
                if ignoredRange.contains(caretIndex)
                    || (ignoredRange.upperBound == caretIndex && ignoredRange.lowerBound < caretIndex) {
                    return true
                }
                index = ignoredRange.upperBound
                continue
            }

            index = statement.index(after: index)
        }

        return false
    }

    private nonisolated static func nestingDepth(
        in statement: String,
        upTo caretIndex: String.Index
    ) -> Int {
        var depth = 0
        var index = statement.startIndex

        while index < caretIndex {
            if let advancedIndex = advanceIfLineComment(in: statement, from: index)
                ?? advanceIfBlockComment(in: statement, from: index)
                ?? advanceIfSingleQuotedString(in: statement, from: index)
                ?? advanceIfDollarQuotedString(in: statement, from: index) {
                index = advancedIndex
                continue
            }

            let character = statement[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(depth - 1, 0)
            }

            index = statement.index(after: index)
        }

        return depth
    }

    private nonisolated static func tokenize(_ statement: String) -> [Token] {
        var tokens: [Token] = []
        var depth = 0
        var index = statement.startIndex

        while index < statement.endIndex {
            if let advancedIndex = advanceIfLineComment(in: statement, from: index)
                ?? advanceIfBlockComment(in: statement, from: index)
                ?? advanceIfSingleQuotedString(in: statement, from: index)
                ?? advanceIfDollarQuotedString(in: statement, from: index) {
                index = advancedIndex
                continue
            }

            let character = statement[index]

            if character.isWhitespace {
                index = statement.index(after: index)
                continue
            }

            if character == "\"" {
                let startIndex = index
                let quotedIdentifier = readQuotedIdentifier(in: statement, from: index)
                tokens.append(
                    Token(
                        kind: .word(quotedIdentifier.value, quoted: true),
                        depth: depth,
                        range: startIndex..<quotedIdentifier.nextIndex
                    )
                )
                index = quotedIdentifier.nextIndex
                continue
            }

            if isIdentifierStart(character) {
                let startIndex = index
                let identifier = readUnquotedIdentifier(in: statement, from: index)
                tokens.append(
                    Token(
                        kind: .word(identifier.value, quoted: false),
                        depth: depth,
                        range: startIndex..<identifier.nextIndex
                    )
                )
                index = identifier.nextIndex
                continue
            }

            if character == "." {
                let nextIndex = statement.index(after: index)
                tokens.append(Token(kind: .dot, depth: depth, range: index..<nextIndex))
                index = nextIndex
                continue
            }

            if character == "," {
                let nextIndex = statement.index(after: index)
                tokens.append(Token(kind: .comma, depth: depth, range: index..<nextIndex))
                index = nextIndex
                continue
            }

            if character == "(" {
                let nextIndex = statement.index(after: index)
                tokens.append(Token(kind: .openParen, depth: depth, range: index..<nextIndex))
                depth += 1
                index = nextIndex
                continue
            }

            if character == ")" {
                depth = max(depth - 1, 0)
                let nextIndex = statement.index(after: index)
                tokens.append(Token(kind: .closeParen, depth: depth, range: index..<nextIndex))
                index = nextIndex
                continue
            }

            if character == ";" {
                let nextIndex = statement.index(after: index)
                tokens.append(Token(kind: .semicolon, depth: depth, range: index..<nextIndex))
                index = nextIndex
                continue
            }

            index = statement.index(after: index)
        }

        return tokens
    }

    private nonisolated static func ignoredRangeIfPresent(
        in text: String,
        from index: String.Index
    ) -> Range<String.Index>? {
        if let nextIndex = advanceIfLineComment(in: text, from: index) {
            return index..<nextIndex
        }

        if let nextIndex = advanceIfBlockComment(in: text, from: index) {
            return index..<nextIndex
        }

        if let nextIndex = advanceIfSingleQuotedString(in: text, from: index) {
            return index..<nextIndex
        }

        if let nextIndex = advanceIfDollarQuotedString(in: text, from: index) {
            return index..<nextIndex
        }

        return nil
    }

    private nonisolated static func advanceIfLineComment(
        in text: String,
        from index: String.Index
    ) -> String.Index? {
        guard text[index] == "-" else {
            return nil
        }

        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex, text[nextIndex] == "-" else {
            return nil
        }

        var cursor = text.index(after: nextIndex)
        while cursor < text.endIndex, text[cursor] != "\n" {
            cursor = text.index(after: cursor)
        }

        return cursor
    }

    private nonisolated static func advanceIfBlockComment(
        in text: String,
        from index: String.Index
    ) -> String.Index? {
        guard text[index] == "/" else {
            return nil
        }

        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex, text[nextIndex] == "*" else {
            return nil
        }

        var cursor = text.index(after: nextIndex)
        while cursor < text.endIndex {
            if text[cursor] == "*" {
                let afterStar = text.index(after: cursor)
                if afterStar < text.endIndex, text[afterStar] == "/" {
                    return text.index(after: afterStar)
                }
            }
            cursor = text.index(after: cursor)
        }

        return text.endIndex
    }

    private nonisolated static func advanceIfSingleQuotedString(
        in text: String,
        from index: String.Index
    ) -> String.Index? {
        guard text[index] == "'" else {
            return nil
        }

        var cursor = text.index(after: index)
        while cursor < text.endIndex {
            if text[cursor] == "'" {
                let nextIndex = text.index(after: cursor)
                if nextIndex < text.endIndex, text[nextIndex] == "'" {
                    cursor = text.index(after: nextIndex)
                    continue
                }

                return nextIndex
            }

            cursor = text.index(after: cursor)
        }

        return text.endIndex
    }

    private nonisolated static func advanceIfDollarQuotedString(
        in text: String,
        from index: String.Index
    ) -> String.Index? {
        guard text[index] == "$" else {
            return nil
        }

        var tagEnd = text.index(after: index)
        while tagEnd < text.endIndex, isDollarTagCharacter(text[tagEnd]) {
            tagEnd = text.index(after: tagEnd)
        }

        guard tagEnd < text.endIndex, text[tagEnd] == "$" else {
            return nil
        }

        let tag = String(text[index...tagEnd])
        var cursor = text.index(after: tagEnd)

        while cursor < text.endIndex {
            guard text[cursor] == "$" else {
                cursor = text.index(after: cursor)
                continue
            }

            var candidateEnd = text.index(after: cursor)
            while candidateEnd < text.endIndex, isDollarTagCharacter(text[candidateEnd]) {
                candidateEnd = text.index(after: candidateEnd)
            }

            if candidateEnd < text.endIndex, text[candidateEnd] == "$" {
                let candidateTag = String(text[cursor...candidateEnd])
                if candidateTag == tag {
                    return text.index(after: candidateEnd)
                }
            }

            cursor = text.index(after: cursor)
        }

        return text.endIndex
    }

    private nonisolated static func readQuotedIdentifier(
        in text: String,
        from index: String.Index
    ) -> (value: String, nextIndex: String.Index) {
        var cursor = text.index(after: index)
        var identifier = ""

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\"" {
                let nextIndex = text.index(after: cursor)
                if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    identifier.append("\"")
                    cursor = text.index(after: nextIndex)
                    continue
                }

                return (identifier, nextIndex)
            }

            identifier.append(character)
            cursor = text.index(after: cursor)
        }

        return (identifier, text.endIndex)
    }

    private nonisolated static func readUnquotedIdentifier(
        in text: String,
        from index: String.Index
    ) -> (value: String, nextIndex: String.Index) {
        var cursor = index
        while cursor < text.endIndex, isIdentifierBody(text[cursor]) {
            cursor = text.index(after: cursor)
        }

        return (String(text[index..<cursor]), cursor)
    }

    private nonisolated static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private nonisolated static func isIdentifierBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private nonisolated static func isDollarTagCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
