//
//  SQLContextAnalyzerTests.swift
//  PostgresGUITests
//
//  Unit tests for SQL autocomplete context analysis.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("SQLContextAnalyzer")
@MainActor
struct SQLContextAnalyzerTests {
    @Test
    func determinesTablesContextAfterFrom() {
        let sql = "SELECT * FROM us"

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.endIndex)

        #expect(analysis.context == .tablesAndSchemas(schemaQualifier: nil))
        #expect(analysis.currentWord == "us")
        #expect(analysis.replacementRange.nsRange == NSRange(location: 14, length: 2))
    }

    @Test
    func determinesSchemaQualifiedTableContextAfterDot() {
        let sql = "SELECT * FROM audit."

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.endIndex)

        #expect(analysis.context == .tablesAndSchemas(schemaQualifier: "audit"))
        #expect(analysis.currentWord.isEmpty)
        #expect(analysis.replacementRange.nsRange == NSRange(location: 20, length: 0))
    }

    @Test
    func determinesColumnContextForAliasDotNotation() {
        let sql = "SELECT u. FROM public.users u"

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.index(sql.startIndex, offsetBy: 9))

        #expect(analysis.context == .columnsSpecific(alias: "u"))
        #expect(analysis.aliasMap["u"] == SQLRelationReference(schemaName: "public", relationName: "users"))
        #expect(analysis.aliasMap["users"] == SQLRelationReference(schemaName: "public", relationName: "users"))
    }

    @Test
    func determinesGlobalColumnContextInOrderBy() {
        let sql = "SELECT * FROM public.users ORDER BY cre"

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.endIndex)

        #expect(analysis.context == .columnsGlobal)
        #expect(analysis.currentWord == "cre")
    }

    @Test
    func isolatesActiveStatementInMultiStatementQuery() {
        let sql = "SELECT 1;SELECT u. FROM users u"
        let dotIndex = sql.firstIndex(of: ".")!

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.index(after: dotIndex))

        #expect(analysis.activeStatement == "SELECT u. FROM users u")
        #expect(analysis.context == .columnsSpecific(alias: "u"))
        #expect(analysis.aliasMap["u"] == SQLRelationReference(schemaName: nil, relationName: "users"))
    }

    @Test
    func resolvesQuotedAliasAndSchemaQualifiedRelation() {
        let sql = "SELECT \"evt\". FROM audit.events AS \"evt\""
        let caretIndex = sql.index(sql.startIndex, offsetBy: 13)

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: caretIndex)

        #expect(analysis.context == .columnsSpecific(alias: "evt"))
        #expect(analysis.aliasMap["evt"] == SQLRelationReference(schemaName: "audit", relationName: "events"))
    }

    @Test
    func doesNotLeakNestedAliasesOutsideCurrentScope() {
        let sql = "SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id) AND o."

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.endIndex)

        #expect(analysis.context == .columnsSpecific(alias: "o"))
        #expect(analysis.aliasMap["o"] == nil)
        #expect(analysis.aliasMap["u"] == SQLRelationReference(schemaName: nil, relationName: "users"))
    }

    @Test
    func resolvesAliasesInsideNestedScope() {
        let sql = "SELECT * FROM users u WHERE EXISTS (SELECT o. FROM orders o WHERE o.user_id = u.id)"
        let caretIndex = sql.index(sql.startIndex, offsetBy: 45)

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: caretIndex)

        #expect(analysis.context == .columnsSpecific(alias: "o"))
        #expect(analysis.aliasMap["o"] == SQLRelationReference(schemaName: nil, relationName: "orders"))
        #expect(analysis.aliasMap["u"] == nil)
    }

    @Test
    func returnsNoneInsideLineComment() {
        let sql = "SELECT * FROM users -- ord"

        let analysis = SQLContextAnalyzer.analyze(sql, upTo: sql.endIndex)

        #expect(analysis.context == .none)
        #expect(analysis.currentWord.isEmpty)
        #expect(analysis.aliasMap.isEmpty)
        #expect(analysis.replacementRange.nsRange == NSRange(location: 26, length: 0))
    }
}
