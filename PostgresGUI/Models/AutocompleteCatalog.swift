//
//  AutocompleteCatalog.swift
//  PostgresGUI
//
//  Lightweight metadata models for SQL autocomplete.
//

import Foundation

enum RelationKind: String, Sendable, Codable, CaseIterable {
    case table
    case view
    case materializedView
    case foreignTable

    nonisolated init?(catalogCode: String) {
        switch catalogCode {
        case "r", "p":
            self = .table
        case "v":
            self = .view
        case "m":
            self = .materializedView
        case "f":
            self = .foreignTable
        default:
            return nil
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .table:
            return "table"
        case .view:
            return "view"
        case .materializedView:
            return "materialized view"
        case .foreignTable:
            return "foreign table"
        }
    }
}

struct DBRelationSummary: Identifiable, Sendable, Hashable, Codable {
    let oid: Int64
    let schema: String
    let name: String
    let kind: RelationKind

    nonisolated init(oid: Int64, schema: String, name: String, kind: RelationKind) {
        self.oid = oid
        self.schema = schema
        self.name = name
        self.kind = kind
    }

    nonisolated var id: String {
        qualifiedName
    }

    nonisolated var qualifiedName: String {
        "\(schema).\(name)"
    }
}

struct DBColumnSummary: Identifiable, Sendable, Hashable, Codable {
    let relationOid: Int64
    let relationSchema: String
    let relationName: String
    let name: String
    let dataType: String
    let ordinalPosition: Int

    nonisolated init(
        relationOid: Int64,
        relationSchema: String,
        relationName: String,
        name: String,
        dataType: String,
        ordinalPosition: Int
    ) {
        self.relationOid = relationOid
        self.relationSchema = relationSchema
        self.relationName = relationName
        self.name = name
        self.dataType = dataType
        self.ordinalPosition = ordinalPosition
    }

    nonisolated var id: String {
        "\(relationOid):\(name)"
    }
}

struct AutocompleteCatalogSnapshot: Sendable, Codable {
    let searchPathSchemas: [String]
    let fetchedSchemas: [String]
    let relationSummaries: [DBRelationSummary]
    let columnSummaries: [DBColumnSummary]

    nonisolated init(
        searchPathSchemas: [String],
        fetchedSchemas: [String],
        relationSummaries: [DBRelationSummary],
        columnSummaries: [DBColumnSummary]
    ) {
        self.searchPathSchemas = Self.uniquePreservingOrder(searchPathSchemas)
        self.fetchedSchemas = Self.uniquePreservingOrder(fetchedSchemas)
        self.relationSummaries = relationSummaries
        self.columnSummaries = columnSummaries
    }

    nonisolated var isEmpty: Bool {
        relationSummaries.isEmpty && columnSummaries.isEmpty
    }

    nonisolated private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []

        for value in values where seen.insert(value).inserted {
            uniqueValues.append(value)
        }

        return uniqueValues
    }
}
