//
//  QueryHistoryView.swift
//  PostgresGUI
//
//  Displays the history of executed queries.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct QueryHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QueryHistory.executionDate, order: .reverse) private var history: [QueryHistory]
    
    let onSelectQuery: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Query History")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Export as JSON") { exportHistory(format: .json) }
                    Button("Export as CSV") { exportHistory(format: .csv) }
                    Button("Export as SQL") { exportHistory(format: .sql) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No queries executed yet.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(history) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: entry.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.isSuccess ? .green : .red)
                            
                            Text(entry.executionDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let dbName = entry.databaseName {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(dbName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(QueryState.formatExecutionTime(entry.executionTime))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        
                        Text(entry.queryText)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(3)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                        
                        HStack {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.queryText, forType: .string)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            
                            Button("Use in Editor") {
                                onSelectQuery(entry.queryText)
                                dismiss()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 700, minHeight: 550)
    }
    
    enum ExportFormat {
        case json, csv, sql
    }
    
    private func exportHistory(format: ExportFormat) {
        let panel = NSSavePanel()
        
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "QueryHistory.json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "QueryHistory.csv"
        case .sql:
            panel.allowedContentTypes = [UTType(filenameExtension: "sql") ?? .plainText]
            panel.nameFieldStringValue = "QueryHistory.sql"
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                switch format {
                case .json:
                    let exportData = history.map { [
                        "queryText": $0.queryText,
                        "executionDate": $0.executionDate.timeIntervalSince1970,
                        "executionTime": $0.executionTime,
                        "isSuccess": $0.isSuccess,
                        "databaseName": $0.databaseName ?? ""
                    ] }
                    let data = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                    try data.write(to: url)
                    
                case .csv:
                    var csv = "Date,Database,Success,ExecutionTimeMs,Query\n"
                    for entry in history {
                        let date = entry.executionDate.formatted(date: .abbreviated, time: .shortened)
                        let db = (entry.databaseName ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                        let success = entry.isSuccess ? "Yes" : "No"
                        let time = String(format: "%.1f", entry.executionTime * 1000)
                        let query = entry.queryText.replacingOccurrences(of: "\"", with: "\"\"")
                        csv += "\"\(date)\",\"\(db)\",\"\(success)\",\"\(time)\",\"\(query)\"\n"
                    }
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                    
                case .sql:
                    let sql = history.map { entry in
                        let status = entry.isSuccess ? "Success" : "Failed"
                        return "-- [\(entry.executionDate.formatted())] [\(status)] Database: \(entry.databaseName ?? "N/A")\n\(entry.queryText)"
                    }.joined(separator: "\n\n")
                    
                    try sql.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to export: \(error)")
            }
        }
    }
}
