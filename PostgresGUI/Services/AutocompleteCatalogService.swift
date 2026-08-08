//
//  AutocompleteCatalogService.swift
//  PostgresGUI
//
//  Loads a lightweight PostgreSQL catalog snapshot optimized for autocomplete.
//

import Foundation
import Logging

actor AutocompleteCatalogService: AutocompleteCatalogServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.autocomplete.catalog")

    init(connectionManager: ConnectionManagerProtocol) {
        self.connectionManager = connectionManager
    }

    func fetchCatalogSnapshot(targetSchemas: Set<String>? = nil) async throws -> AutocompleteCatalogSnapshot {
        let logger = self.logger

        return try await connectionManager.withConnection { connection in
            let searchPathSchemas = try await Self.fetchSearchPathSchemas(using: connection)
            let availableSchemas = try await Self.fetchAvailableSchemas(using: connection)
            let resolvedSchemas = Self.resolvedSchemas(
                for: targetSchemas,
                searchPathSchemas: searchPathSchemas,
                availableSchemas: availableSchemas
            )

            guard !resolvedSchemas.isEmpty else {
                return AutocompleteCatalogSnapshot(
                    searchPathSchemas: searchPathSchemas,
                    fetchedSchemas: [],
                    relationSummaries: [],
                    columnSummaries: []
                )
            }

            logger.debug("Fetching autocomplete catalog for schemas: \(resolvedSchemas.joined(separator: ", "))")

            let rows = try await connection.executeQuery(Self.catalogQuery(forSchemas: resolvedSchemas))
            var relations: [DBRelationSummary] = []
            var columns: [DBColumnSummary] = []
            var seenRelationOids = Set<Int64>()

            for try await rawRow in rows {
                guard let row = rawRow as? any DatabaseRow else {
                    throw DatabaseError.unknownError("Expected DatabaseRow")
                }

                let relationOid = try await row.decode(Int64.self, column: "relation_oid")
                let schemaName = try await row.decode(String.self, column: "schema_name")
                let relationName = try await row.decode(String.self, column: "relation_name")
                let relationKindCode = try await row.decode(String.self, column: "relation_kind")

                guard let relationKind = RelationKind(catalogCode: relationKindCode) else {
                    continue
                }

                if seenRelationOids.insert(relationOid).inserted {
                    relations.append(
                        DBRelationSummary(
                            oid: relationOid,
                            schema: schemaName,
                            name: relationName,
                            kind: relationKind
                        )
                    )
                }

                guard let columnName = try await Self.decodeOptionalString(from: row, column: "column_name"),
                      let dataType = try await Self.decodeOptionalString(from: row, column: "data_type"),
                      let ordinalPosition = try await Self.decodeOptionalInt(from: row, column: "ordinal_position") else {
                    continue
                }

                columns.append(
                    DBColumnSummary(
                        relationOid: relationOid,
                        relationSchema: schemaName,
                        relationName: relationName,
                        name: columnName,
                        dataType: dataType,
                        ordinalPosition: ordinalPosition
                    )
                )
            }

            return AutocompleteCatalogSnapshot(
                searchPathSchemas: searchPathSchemas,
                fetchedSchemas: resolvedSchemas,
                relationSummaries: relations,
                columnSummaries: columns
            )
        }
    }

    static func resolvedSchemas(
        for targetSchemas: Set<String>?,
        searchPathSchemas: [String],
        availableSchemas: [String]
    ) -> [String] {
        if let targetSchemas, !targetSchemas.isEmpty {
            return targetSchemas.sorted()
        }

        return uniquePreservingOrder(searchPathSchemas + ["public"] + availableSchemas)
    }

    static func catalogQuery(forSchemas schemas: [String]) -> String {
        let schemaList = schemas
            .map(sqlLiteral)
            .joined(separator: ", ")

        return """
        SELECT
            n.nspname AS schema_name,
            c.relname AS relation_name,
            c.relkind::text AS relation_kind,
            c.oid::bigint AS relation_oid,
            a.attname AS column_name,
            pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
            a.attnum AS ordinal_position
        FROM pg_catalog.pg_class c
        INNER JOIN pg_catalog.pg_namespace n
            ON n.oid = c.relnamespace
        LEFT JOIN pg_catalog.pg_attribute a
            ON a.attrelid = c.oid
           AND a.attnum > 0
           AND a.attisdropped = false
        WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
          AND n.nspname IN (\(schemaList))
        ORDER BY n.nspname, c.relname, a.attnum
        """
    }

    private static func fetchSearchPathSchemas(using connection: DatabaseConnectionProtocol) async throws -> [String] {
        let rows = try await connection.executeQuery(
            """
            SELECT unnest(current_schemas(false)) AS schema_name
            """
        )

        var schemas: [String] = []

        for try await rawRow in rows {
            guard let row = rawRow as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }

            let schemaName = try await row.decode(String.self, column: "schema_name")
            schemas.append(schemaName)
        }

        return uniquePreservingOrder(schemas)
    }

    private static func fetchAvailableSchemas(using connection: DatabaseConnectionProtocol) async throws -> [String] {
        let rows = try await connection.executeQuery(
            """
            SELECT nspname AS schema_name
            FROM pg_catalog.pg_namespace
            WHERE nspname NOT IN ('information_schema')
              AND nspname NOT LIKE 'pg_%'
              AND nspname NOT LIKE 'pg_temp_%'
              AND nspname NOT LIKE 'pg_toast%'
            ORDER BY nspname
            """
        )

        var schemas: [String] = []

        for try await rawRow in rows {
            guard let row = rawRow as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }

            let schemaName = try await row.decode(String.self, column: "schema_name")
            schemas.append(schemaName)
        }

        return uniquePreservingOrder(schemas)
    }

    private static func decodeOptionalString(
        from row: any DatabaseRow,
        column: String
    ) async throws -> String? {
        guard let cell = await row.cell(named: column) else {
            return nil
        }

        guard await cell.bytes != nil else {
            return nil
        }

        return try await cell.decode(String.self)
    }

    private static func decodeOptionalInt(
        from row: any DatabaseRow,
        column: String
    ) async throws -> Int? {
        guard let cell = await row.cell(named: column) else {
            return nil
        }

        guard await cell.bytes != nil else {
            return nil
        }

        return try await cell.decode(Int.self)
    }

    private static func sqlLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []

        for value in values where seen.insert(value).inserted {
            uniqueValues.append(value)
        }

        return uniqueValues
    }
}
