//
//  QueryHistoryExporter.swift
//  PostgresGUI
//
//  Formats query history records for export.
//

import Foundation

enum QueryHistoryExporter {
    static func jsonData(for history: [QueryHistory]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(history.map(QueryHistoryExportRecord.init))
    }

    static func csvString(for history: [QueryHistory]) -> String {
        var csv = "Date,Database,Success,ExecutionTimeMs,Query\n"

        for entry in history {
            let fields = [
                entry.executionDate.formatted(date: .abbreviated, time: .shortened),
                entry.databaseName ?? "",
                entry.isSuccess ? "Yes" : "No",
                String(format: "%.1f", entry.executionTime * 1000),
                entry.queryText,
            ]
            csv += fields.map(escapeCSVField).joined(separator: ",") + "\n"
        }

        return csv
    }

    static func sqlString(for history: [QueryHistory]) -> String {
        history.map { entry in
            let status = entry.isSuccess ? "Success" : "Failed"
            let database = entry.databaseName ?? "N/A"
            return "-- [\(entry.executionDate.formatted())] [\(status)] Database: \(database)\n\(sqlStatement(entry.queryText))"
        }
        .joined(separator: "\n\n")
    }

    private static func escapeCSVField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func sqlStatement(_ queryText: String) -> String {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix(";") ? trimmed : "\(trimmed);"
    }
}

private struct QueryHistoryExportRecord: Encodable {
    let queryText: String
    let executionDate: Date
    let executionTime: TimeInterval
    let isSuccess: Bool
    let databaseName: String?
    let connectionId: UUID?

    init(_ history: QueryHistory) {
        queryText = history.queryText
        executionDate = history.executionDate
        executionTime = history.executionTime
        isSuccess = history.isSuccess
        databaseName = history.databaseName
        connectionId = history.connectionId
    }
}
