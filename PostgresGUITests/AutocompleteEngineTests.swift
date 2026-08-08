//
//  AutocompleteEngineTests.swift
//  PostgresGUITests
//
//  Unit tests for SQL autocomplete ranking and filtering.
//

import Foundation
import Testing
@testable import PostgresGUI

private actor MockAutocompleteEngineCatalogService: AutocompleteCatalogServiceProtocol {
    private var queuedSnapshots: [AutocompleteCatalogSnapshot] = []
    private var requestedSchemasHistory: [Set<String>?] = []
    private var fetchCallCount = 0

    func fetchCatalogSnapshot(targetSchemas: Set<String>?) async throws -> AutocompleteCatalogSnapshot {
        fetchCallCount += 1
        requestedSchemasHistory.append(targetSchemas)

        guard !queuedSnapshots.isEmpty else {
            Issue.record("No queued snapshot configured for MockAutocompleteEngineCatalogService")
            return AutocompleteCatalogSnapshot(
                searchPathSchemas: [],
                fetchedSchemas: [],
                relationSummaries: [],
                columnSummaries: []
            )
        }

        return queuedSnapshots.removeFirst()
    }

    func enqueue(_ snapshot: AutocompleteCatalogSnapshot) {
        queuedSnapshots.append(snapshot)
    }

    func fetchRequests() -> [Set<String>?] {
        requestedSchemasHistory
    }

    func numberOfFetchCalls() -> Int {
        fetchCallCount
    }
}

@Suite("AutocompleteEngine")
@MainActor
struct AutocompleteEngineTests {
    private func makeRelation(
        oid: Int64,
        schema: String,
        name: String,
        kind: RelationKind = .table
    ) -> DBRelationSummary {
        DBRelationSummary(oid: oid, schema: schema, name: name, kind: kind)
    }

    private func makeColumn(
        relationOid: Int64,
        schema: String,
        relationName: String,
        name: String,
        dataType: String,
        ordinalPosition: Int
    ) -> DBColumnSummary {
        DBColumnSummary(
            relationOid: relationOid,
            relationSchema: schema,
            relationName: relationName,
            name: name,
            dataType: dataType,
            ordinalPosition: ordinalPosition
        )
    }

    @Test
    func ranksPrefixMatchesAheadOfSubstringMatchesForSpecificColumns() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id_user", dataType: "uuid", ordinalPosition: 1),
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "session_id", dataType: "uuid", ordinalPosition: 2),
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "created_at", dataType: "timestamp", ordinalPosition: 3)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .columnsSpecific(alias: "u"),
                currentWord: "ID",
                activeStatement: "SELECT u.ID FROM users u",
                aliasMap: ["u": SQLRelationReference(schemaName: "public", relationName: "users")]
            ),
            provider: provider
        )

        #expect(suggestions.map(\.title) == ["id_user", "session_id"])
        #expect(suggestions.first?.subtitle == "uuid")
        #expect(suggestions.first?.iconType == .column)
    }

    @Test
    func deduplicatesGlobalColumnsAcrossAliasAndRelationNameMappings() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users"),
                    makeRelation(oid: 2, schema: "public", name: "orders")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1),
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "email", dataType: "text", ordinalPosition: 2),
                    makeColumn(relationOid: 2, schema: "public", relationName: "orders", name: "id", dataType: "uuid", ordinalPosition: 1),
                    makeColumn(relationOid: 2, schema: "public", relationName: "orders", name: "user_id", dataType: "uuid", ordinalPosition: 2)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .columnsGlobal,
                currentWord: "",
                activeStatement: "SELECT  FROM users u JOIN orders o ON o.user_id = u.id",
                aliasMap: [
                    "o": SQLRelationReference(schemaName: "public", relationName: "orders"),
                    "orders": SQLRelationReference(schemaName: "public", relationName: "orders"),
                    "u": SQLRelationReference(schemaName: "public", relationName: "users"),
                    "users": SQLRelationReference(schemaName: "public", relationName: "users")
                ]
            ),
            provider: provider
        )

        #expect(suggestions.count == 4)
        #expect(suggestions.filter { $0.title == "id" }.count == 2)
        #expect(suggestions.contains { $0.subtitle == "uuid • public.users" })
        #expect(suggestions.contains { $0.subtitle == "uuid • public.orders" })
    }

    @Test
    func lazilyRefreshesExplicitSchemaBeforeReturningTableSuggestions() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: []
            )
        )
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["audit"],
                relationSummaries: [
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: []
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .tablesAndSchemas(schemaQualifier: "audit"),
                currentWord: "ev",
                activeStatement: "SELECT * FROM audit.ev",
                aliasMap: [:]
            ),
            provider: provider
        )

        let fetchRequests = await service.fetchRequests()
        let fetchCallCount = await service.numberOfFetchCalls()

        #expect(suggestions.map(\.title) == ["events"])
        #expect(suggestions.first?.replacementText == "events")
        #expect(fetchCallCount == 2)
        #expect(fetchRequests.last! == ["audit"])
    }

    @Test
    func qualifiesNonPublicRelationsInUnqualifiedTableContext() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public", "audit"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users"),
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: []
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .tablesAndSchemas(schemaQualifier: nil),
                currentWord: "eve",
                activeStatement: "SELECT * FROM eve",
                aliasMap: [:]
            ),
            provider: provider
        )

        #expect(suggestions.map(\.title) == ["events"])
        #expect(suggestions.first?.replacementText == "audit.events")
        #expect(suggestions.first?.subtitle == "table • audit")
    }

    @Test
    func suggestsSchemasWithDotReplacementText() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public", "audit"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: []
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .tablesAndSchemas(schemaQualifier: nil),
                currentWord: "aud",
                activeStatement: "SELECT * FROM aud",
                aliasMap: [:]
            ),
            provider: provider
        )

        #expect(suggestions.map(\.title) == ["audit"])
        #expect(suggestions.first?.replacementText == "audit.")
        #expect(suggestions.first?.iconType == .schema)
    }

    @Test
    func suggestsKeywordsWhenNoMetadataContextApplies() async {
        let service = MockAutocompleteEngineCatalogService()
        let provider = DatabaseMetadataProvider(catalogService: service)

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .keywords,
                currentWord: "sel",
                activeStatement: "sel",
                aliasMap: [:]
            ),
            provider: provider
        )

        #expect(suggestions.map(\.title) == ["select"])
        #expect(suggestions.first?.replacementText == "select")
        #expect(suggestions.first?.iconType == .keyword)
    }

    @Test
    func suggestsClauseKeywordsAfterCompletedFromRelation() async throws {
        let service = MockAutocompleteEngineCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public", "audit"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "alembic_version"),
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: []
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let suggestions = await AutocompleteEngine.suggestions(
            for: SQLContextAnalysis(
                context: .tablesAndSchemas(schemaQualifier: nil),
                currentWord: "",
                activeStatement: "SELECT * FROM users ",
                aliasMap: [
                    "users": SQLRelationReference(schemaName: "public", relationName: "users")
                ]
            ),
            provider: provider
        )

        #expect(suggestions.prefix(3).map(\.title) == ["JOIN", "LEFT JOIN", "RIGHT JOIN"])
        #expect(suggestions.contains { $0.title == "WHERE" })
    }
}
