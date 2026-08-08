//
//  DatabaseMetadataProvider.swift
//  PostgresGUI
//
//  Actor-backed in-memory metadata cache for SQL autocomplete.
//

import Foundation

actor DatabaseMetadataProvider {
    private struct RefreshRequestKey: Hashable {
        let schemas: [String]?

        init(targetSchemas: Set<String>?) {
            if let targetSchemas, !targetSchemas.isEmpty {
                self.schemas = targetSchemas.sorted()
            } else {
                self.schemas = nil
            }
        }
    }

    private let catalogService: any AutocompleteCatalogServiceProtocol

    private var searchPathSchemas: [String] = []
    private var loadedSchemas = Set<String>()
    private var relationsBySchema: [String: [DBRelationSummary]] = [:]
    private var relationByQualifiedName: [String: DBRelationSummary] = [:]
    private var columnsByRelationOid: [Int64: [DBColumnSummary]] = [:]
    private var inFlightRefreshes: [RefreshRequestKey: Task<AutocompleteCatalogSnapshot, Error>] = [:]
    private var generation: UInt64 = 0

    init(catalogService: any AutocompleteCatalogServiceProtocol) {
        self.catalogService = catalogService
    }

    @discardableResult
    func refresh(targetSchemas: Set<String>? = nil) async throws -> AutocompleteCatalogSnapshot {
        let requestKey = RefreshRequestKey(targetSchemas: targetSchemas)

        if let inFlightRefresh = inFlightRefreshes[requestKey] {
            return try await inFlightRefresh.value
        }

        let catalogService = self.catalogService
        let refreshTask = Task {
            try await catalogService.fetchCatalogSnapshot(targetSchemas: targetSchemas)
        }
        inFlightRefreshes[requestKey] = refreshTask

        do {
            let snapshot = try await refreshTask.value
            apply(snapshot, targetSchemas: targetSchemas)
            inFlightRefreshes[requestKey] = nil
            return snapshot
        } catch {
            inFlightRefreshes[requestKey] = nil
            throw error
        }
    }

    func clear() {
        for refreshTask in inFlightRefreshes.values {
            refreshTask.cancel()
        }

        searchPathSchemas = []
        loadedSchemas = []
        relationsBySchema = [:]
        relationByQualifiedName = [:]
        columnsByRelationOid = [:]
        inFlightRefreshes = [:]
        generation &+= 1
    }

    func loadedSchemaNames() -> [String] {
        loadedSchemas.sorted()
    }

    func currentSearchPathSchemas() -> [String] {
        searchPathSchemas
    }

    func schemaLookupOrder() -> [String] {
        var orderedSchemas: [String] = []
        var seenSchemas = Set<String>()

        for schema in searchPathSchemas where seenSchemas.insert(schema).inserted {
            orderedSchemas.append(schema)
        }

        for schema in loadedSchemas.sorted() where seenSchemas.insert(schema).inserted {
            orderedSchemas.append(schema)
        }

        return orderedSchemas
    }

    func currentGeneration() -> UInt64 {
        generation
    }

    func hasLoadedSchema(_ schema: String) -> Bool {
        loadedSchemas.contains(schema) || loadedSchemas.contains(schema.lowercased())
    }

    func relations(in schema: String) -> [DBRelationSummary] {
        if let relations = relationsBySchema[schema] {
            return relations
        }

        return relationsBySchema[schema.lowercased()] ?? []
    }

    func relation(named relationName: String, in schema: String) -> DBRelationSummary? {
        if let relation = relationByQualifiedName[qualifiedName(schema: schema, name: relationName)] {
            return relation
        }

        return relationByQualifiedName[
            qualifiedName(schema: schema.lowercased(), name: relationName.lowercased())
        ]
    }

    func relation(for reference: SQLRelationReference) -> DBRelationSummary? {
        if let schemaName = reference.schemaName {
            return relation(named: reference.relationName, in: schemaName)
        }

        for schemaName in schemaLookupOrder() {
            if let relation = relation(named: reference.relationName, in: schemaName) {
                return relation
            }
        }

        return nil
    }

    func columns(forRelationOid relationOid: Int64) -> [DBColumnSummary] {
        columnsByRelationOid[relationOid] ?? []
    }

    func columns(forRelationNamed relationName: String, in schema: String) -> [DBColumnSummary] {
        guard let relation = relation(named: relationName, in: schema) else {
            return []
        }

        return columns(forRelationOid: relation.oid)
    }

    func columns(for reference: SQLRelationReference) -> [DBColumnSummary] {
        guard let relation = relation(for: reference) else {
            return []
        }

        return columns(forRelationOid: relation.oid)
    }

    private func apply(_ snapshot: AutocompleteCatalogSnapshot, targetSchemas: Set<String>?) {
        if targetSchemas == nil {
            clearStorage()
        } else {
            removeSchemas(snapshot.fetchedSchemas)
        }

        searchPathSchemas = snapshot.searchPathSchemas
        loadedSchemas.formUnion(snapshot.fetchedSchemas)

        for relation in snapshot.relationSummaries {
            relationByQualifiedName[qualifiedName(schema: relation.schema, name: relation.name)] = relation
            relationsBySchema[relation.schema, default: []].append(relation)
        }

        for column in snapshot.columnSummaries {
            columnsByRelationOid[column.relationOid, default: []].append(column)
        }

        for schema in snapshot.fetchedSchemas {
            relationsBySchema[schema]?.sort(by: Self.relationSort)
        }

        for relation in snapshot.relationSummaries {
            columnsByRelationOid[relation.oid]?.sort(by: Self.columnSort)
        }

        generation &+= 1
    }

    private func clearStorage() {
        loadedSchemas = []
        relationsBySchema = [:]
        relationByQualifiedName = [:]
        columnsByRelationOid = [:]
    }

    private func removeSchemas(_ schemas: [String]) {
        for schema in schemas {
            loadedSchemas.remove(schema)

            guard let removedRelations = relationsBySchema.removeValue(forKey: schema) else {
                continue
            }

            for relation in removedRelations {
                relationByQualifiedName.removeValue(
                    forKey: qualifiedName(schema: relation.schema, name: relation.name)
                )
                columnsByRelationOid.removeValue(forKey: relation.oid)
            }
        }
    }

    private func qualifiedName(schema: String, name: String) -> String {
        "\(schema).\(name)"
    }

    private static func relationSort(_ lhs: DBRelationSummary, _ rhs: DBRelationSummary) -> Bool {
        if lhs.schema != rhs.schema {
            return lhs.schema < rhs.schema
        }

        return lhs.name < rhs.name
    }

    private static func columnSort(_ lhs: DBColumnSummary, _ rhs: DBColumnSummary) -> Bool {
        if lhs.ordinalPosition != rhs.ordinalPosition {
            return lhs.ordinalPosition < rhs.ordinalPosition
        }

        return lhs.name < rhs.name
    }
}
