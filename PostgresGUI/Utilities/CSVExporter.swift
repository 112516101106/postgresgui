//
//  CSVExporter.swift
//  PostgresGUI
//
//  Created by ghazi on 12/29/25.
//

import Foundation

enum CSVExporter {
    /// Converts TableRows to CSV string
    /// - Parameters:
    ///   - rows: Array of TableRow to export
    ///   - columns: Optional column order. If nil, uses sorted keys from first row
    /// - Returns: CSV formatted string
    static func toCSV(rows: [TableRow], columns: [String]? = nil) -> String {
        guard !rows.isEmpty else { return "" }

        // Determine column order
        let columnOrder = columns ?? rows.first?.values.keys.sorted() ?? []
        guard !columnOrder.isEmpty else { return "" }

        var csvLines: [String] = []

        // Header row
        csvLines.append(columnOrder.map { escapeCSVField($0) }.joined(separator: ","))

        // Data rows
        for row in rows {
            let rowValues = columnOrder.map { column -> String in
                if let value = row.values[column] ?? nil {
                    return escapeCSVField(value)
                } else {
                    return ""
                }
            }
            csvLines.append(rowValues.joined(separator: ","))
        }

        return csvLines.joined(separator: "\n")
    }

    /// Converts the selected subset of rows to CSV, preserving the order of `rows`
    /// - Parameters:
    ///   - rows: Rows in display order (already sorted and filtered by the view)
    ///   - selectedIDs: IDs of the rows to include
    ///   - columns: Column order for the output
    /// - Returns: CSV formatted string, or "" when nothing is selected
    static func csvForSelection(
        rows: [TableRow],
        selectedIDs: Set<TableRow.ID>,
        columns: [String]?
    ) -> String {
        toCSV(rows: rows.filter { selectedIDs.contains($0.id) }, columns: columns)
    }

    /// Escapes a field for CSV format according to RFC 4180
    /// - Parameter field: The field value to escape
    /// - Returns: Properly escaped CSV field
    private static func escapeCSVField(_ field: String) -> String {
        // If field contains comma, newline, or double quote, wrap in quotes
        let needsQuoting = field.contains(",") ||
                          field.contains("\n") ||
                          field.contains("\r") ||
                          field.contains("\"")

        if needsQuoting {
            // Double any existing quotes and wrap in quotes
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        return field
    }
}
