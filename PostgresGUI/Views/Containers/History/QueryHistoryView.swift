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

    private var sheetMinHeight: CGFloat {
        history.count <= 1 ? 340 : 520
    }

    private var sheetIdealHeight: CGFloat {
        history.count <= 1 ? 380 : 600
    }

    private var historyCountText: String {
        "\(history.count) \(history.count == 1 ? "query" : "queries")"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Query History")
                        .font(.headline)

                    if !history.isEmpty {
                        Text(historyCountText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button("Export as JSON") { exportHistory(format: .json) }
                    Button("Export as CSV") { exportHistory(format: .csv) }
                    Button("Export as SQL") { exportHistory(format: .sql) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(history.isEmpty)
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if history.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("No Query History")
                        .font(.headline)
                    Text("Executed queries will appear here.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(history) { entry in
                            QueryHistoryRow(entry: entry) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.queryText, forType: .string)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(
            minWidth: 700,
            idealWidth: 760,
            maxWidth: 900,
            minHeight: sheetMinHeight,
            idealHeight: sheetIdealHeight,
            maxHeight: 650
        )
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
                    let data = try QueryHistoryExporter.jsonData(for: history)
                    try data.write(to: url)
                    
                case .csv:
                    let csv = QueryHistoryExporter.csvString(for: history)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                    
                case .sql:
                    let sql = QueryHistoryExporter.sqlString(for: history)
                    try sql.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to export: \(error)")
            }
        }
    }
}

private struct QueryHistoryRow: View {
    let entry: QueryHistory
    let onCopy: () -> Void
    @State private var didCopy = false

    private var statusIconName: String {
        entry.isSuccess ? "checkmark" : "xmark"
    }

    private var statusDescription: String {
        entry.isSuccess ? "Query succeeded" : "Query failed"
    }

    private var databaseDescription: String? {
        entry.databaseName?.isEmpty == false ? entry.databaseName : nil
    }

    private var executionTimeDescription: String {
        QueryState.formatExecutionTime(entry.executionTime)
    }

    private var relativeExecutionDateDescription: String {
        QueryResultsDateFormat.relative.string(from: entry.executionDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: statusIconName)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(statusDescription)

                    Text(executionTimeDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Execution time \(executionTimeDescription)")

                    Text(relativeExecutionDateDescription)
                        .foregroundColor(.secondary)
                        .help(entry.executionDate.formatted(date: .abbreviated, time: .shortened))

                    if let databaseDescription {
                        Text(databaseDescription)
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)

                Spacer(minLength: 12)

                Button {
                    onCopy()
                    didCopy = true

                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        await MainActor.run {
                            didCopy = false
                        }
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
                .help(didCopy ? "Copied" : "Copy query")
                .accessibilityLabel(didCopy ? "Copied query" : "Copy query")
            }

            Text(entry.queryText)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
    }
}
