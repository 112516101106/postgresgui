//
//  AutocompleteContext.swift
//  PostgresGUI
//
//  Context models shared by SQL autocomplete parsing and ranking.
//

import Foundation

enum AutocompleteContext: Sendable, Equatable, Hashable, Codable {
    case tablesAndSchemas(schemaQualifier: String?)
    case columnsGlobal
    case columnsSpecific(alias: String)
    case keywords
    case none
}

struct TextSelectionRange: Sendable, Equatable, Hashable, Codable {
    let location: Int
    let length: Int

    nonisolated init(location: Int, length: Int) {
        self.location = max(location, 0)
        self.length = max(length, 0)
    }

    nonisolated static var zero: TextSelectionRange {
        TextSelectionRange(location: 0, length: 0)
    }

    nonisolated var upperBound: Int {
        location + length
    }

    nonisolated var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct SQLRelationReference: Sendable, Equatable, Hashable, Codable {
    let schemaName: String?
    let relationName: String

    nonisolated init(schemaName: String?, relationName: String) {
        self.schemaName = schemaName
        self.relationName = relationName
    }

    nonisolated var qualifiedName: String {
        if let schemaName {
            return "\(schemaName).\(relationName)"
        }

        return relationName
    }
}

struct SQLContextAnalysis: Sendable, Equatable, Codable {
    let context: AutocompleteContext
    let currentWord: String
    let activeStatement: String
    let aliasMap: [String: SQLRelationReference]
    let replacementRange: TextSelectionRange

    nonisolated init(
        context: AutocompleteContext,
        currentWord: String,
        activeStatement: String,
        aliasMap: [String: SQLRelationReference],
        replacementRange: TextSelectionRange = .zero
    ) {
        self.context = context
        self.currentWord = currentWord
        self.activeStatement = activeStatement
        self.aliasMap = aliasMap
        self.replacementRange = replacementRange
    }
}
