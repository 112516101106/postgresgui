//
//  DatabaseMetadataProviderTests.swift
//  PostgresGUITests
//
//  Unit tests for SQL autocomplete metadata caching.
//

import Foundation
import Testing
@testable import PostgresGUI

private actor MockAutocompleteCatalogService: AutocompleteCatalogServiceProtocol {
    var queuedSnapshots: [AutocompleteCatalogSnapshot] = []
    var fetchDelayNanoseconds: UInt64 = 0

    private var requestedSchemasHistory: [Set<String>?] = []
    private var fetchCallCount = 0

    func fetchCatalogSnapshot(targetSchemas: Set<String>?) async throws -> AutocompleteCatalogSnapshot {
        fetchCallCount += 1
        requestedSchemasHistory.append(targetSchemas)

        if fetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }

        guard !queuedSnapshots.isEmpty else {
            Issue.record("No queued snapshot configured for MockAutocompleteCatalogService")
            return AutocompleteCatalogSnapshot(
                searchPathSchemas: [],
                fetchedSchemas: [],
                relationSummaries: [],
                columnSummaries: []
            )
        }

        return queuedSnapshots.removeFirst()
    }

    func fetchRequests() -> [Set<String>?] {
        requestedSchemasHistory
    }

    func numberOfFetchCalls() -> Int {
        fetchCallCount
    }

    func enqueue(_ snapshot: AutocompleteCatalogSnapshot) {
        queuedSnapshots.append(snapshot)
    }

    func setFetchDelay(nanoseconds: UInt64) {
        fetchDelayNanoseconds = nanoseconds
    }
}

@Suite("DatabaseMetadataProvider")
@MainActor
struct DatabaseMetadataProviderTests {
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
    func refresh_withoutExplicitSchemas_cachesDefaultSnapshot() async throws {
        let service = MockAutocompleteCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public", "audit"],
                fetchedSchemas: ["public", "audit"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users"),
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1),
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "email", dataType: "text", ordinalPosition: 2),
                    makeColumn(relationOid: 2, schema: "audit", relationName: "events", name: "id", dataType: "bigint", ordinalPosition: 1)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()

        let searchPathSchemas = await provider.currentSearchPathSchemas()
        let loadedSchemaNames = await provider.loadedSchemaNames()
        let publicRelations = await provider.relations(in: "public")
        let publicColumns = await provider.columns(forRelationNamed: "users", in: "public")
        let fetchRequests = await service.fetchRequests()
        let publicRelationNames = publicRelations.map { $0.name }
        let publicColumnNames = publicColumns.map { $0.name }

        #expect(searchPathSchemas == ["public", "audit"])
        #expect(loadedSchemaNames == ["audit", "public"])
        #expect(publicRelationNames == ["users"])
        #expect(publicColumnNames == ["id", "email"])
        #expect(fetchRequests.count == 1)
        #expect(fetchRequests.first! == nil)
    }

    @Test
    func refresh_specificSchema_mergesWithoutDroppingExistingSchemas() async throws {
        let service = MockAutocompleteCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1)
                ]
            )
        )
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["audit"],
                relationSummaries: [
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 2, schema: "audit", relationName: "events", name: "event_id", dataType: "bigint", ordinalPosition: 1)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()
        try await provider.refresh(targetSchemas: ["audit"])

        let loadedSchemaNames = await provider.loadedSchemaNames()
        let publicRelations = await provider.relations(in: "public")
        let auditRelations = await provider.relations(in: "audit")
        let auditColumns = await provider.columns(forRelationNamed: "events", in: "audit")

        let fetchRequests = await service.fetchRequests()
        let publicRelationNames = publicRelations.map { $0.name }
        let auditRelationNames = auditRelations.map { $0.name }
        let auditColumnNames = auditColumns.map { $0.name }
        #expect(loadedSchemaNames == ["audit", "public"])
        #expect(publicRelationNames == ["users"])
        #expect(auditRelationNames == ["events"])
        #expect(auditColumnNames == ["event_id"])
        #expect(fetchRequests.count == 2)
        #expect(fetchRequests[1] == ["audit"])
    }

    @Test
    func refresh_specificSchema_replacesOnlyThatSchema() async throws {
        let service = MockAutocompleteCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public", "audit"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users"),
                    makeRelation(oid: 2, schema: "audit", name: "events")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1),
                    makeColumn(relationOid: 2, schema: "audit", relationName: "events", name: "event_id", dataType: "bigint", ordinalPosition: 1)
                ]
            )
        )
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["audit"],
                relationSummaries: [
                    makeRelation(oid: 3, schema: "audit", name: "event_log")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 3, schema: "audit", relationName: "event_log", name: "id", dataType: "bigint", ordinalPosition: 1)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh(targetSchemas: ["public", "audit"])
        try await provider.refresh(targetSchemas: ["audit"])

        let publicRelations = await provider.relations(in: "public")
        let auditRelations = await provider.relations(in: "audit")
        let removedRelation = await provider.relation(named: "events", in: "audit")
        let publicRelationNames = publicRelations.map { $0.name }
        let auditRelationNames = auditRelations.map { $0.name }

        #expect(publicRelationNames == ["users"])
        #expect(auditRelationNames == ["event_log"])
        #expect(removedRelation == nil)
    }

    @Test
    func clear_resetsCachedMetadata() async throws {
        let service = MockAutocompleteCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1)
                ]
            )
        )

        let provider = DatabaseMetadataProvider(catalogService: service)
        try await provider.refresh()
        let generationBeforeClear = await provider.currentGeneration()

        await provider.clear()

        let loadedSchemaNames = await provider.loadedSchemaNames()
        let searchPathSchemas = await provider.currentSearchPathSchemas()
        let publicRelations = await provider.relations(in: "public")
        let publicColumns = await provider.columns(forRelationNamed: "users", in: "public")
        let generationAfterClear = await provider.currentGeneration()

        #expect(loadedSchemaNames.isEmpty)
        #expect(searchPathSchemas.isEmpty)
        #expect(publicRelations.isEmpty)
        #expect(publicColumns.isEmpty)
        #expect(generationAfterClear == generationBeforeClear + 1)
    }

    @Test
    func refresh_deduplicatesConcurrentRequestsForSameSchemaSet() async throws {
        let service = MockAutocompleteCatalogService()
        await service.enqueue(
            AutocompleteCatalogSnapshot(
                searchPathSchemas: ["public"],
                fetchedSchemas: ["public"],
                relationSummaries: [
                    makeRelation(oid: 1, schema: "public", name: "users")
                ],
                columnSummaries: [
                    makeColumn(relationOid: 1, schema: "public", relationName: "users", name: "id", dataType: "uuid", ordinalPosition: 1)
                ]
            )
        )
        await service.setFetchDelay(nanoseconds: 50_000_000)

        let provider = DatabaseMetadataProvider(catalogService: service)

        async let firstRefresh = provider.refresh(targetSchemas: ["public"])
        async let secondRefresh = provider.refresh(targetSchemas: ["public"])

        let firstSnapshot = try await firstRefresh
        let secondSnapshot = try await secondRefresh
        let fetchCallCount = await service.numberOfFetchCalls()
        let publicRelations = await provider.relations(in: "public")
        let publicRelationNames = publicRelations.map { $0.name }

        #expect(firstSnapshot.fetchedSchemas == ["public"])
        #expect(secondSnapshot.fetchedSchemas == ["public"])
        #expect(fetchCallCount == 1)
        #expect(publicRelationNames == ["users"])
    }
}
