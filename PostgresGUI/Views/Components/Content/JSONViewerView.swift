//
//  JSONViewerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JSONViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingExporter = false
    @State private var showCopiedIcon = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    let selectedRowIDs: Set<UUID>

    private var selectedRows: [TableRow] {
        appState.query.queryResults.filter { selectedRowIDs.contains($0.id) }
    }

    private var csvString: String {
        CSVExporter.toCSV(rows: selectedRows, columns: appState.query.queryColumnNames)
    }
    
    private var jsonString: String {
        // Convert rows to array of dictionaries
        let rowsAsDicts = selectedRows.map { row in
            row.values.mapValues { value -> Any in
                if let stringValue = value {
                    return stringValue
                } else {
                    return NSNull()
                }
            }
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: rowsAsDicts, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "Error encoding JSON: \(error.localizedDescription)"
        }
    }
    
    var body: some View {
        NavigationStack {
            TextEditor(text: Binding(
                get: { jsonString },
                set: { _ in } // Read-only
            ))
            .font(.system(.body, design: .monospaced))
            .navigationTitle("JSON View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Download CSV") {
                            showingExporter = true
                        }

                        Button {
                            handleCopyJSON()
                        } label: {
                            Label {
                                Text("Copy JSON")
                            } icon: {
                                ZStack {
                                    Image(systemName: "doc.on.doc")
                                        .opacity(showCopiedIcon ? 0 : 1)

                                    Image(systemName: "checkmark")
                                        .opacity(showCopiedIcon ? 1 : 0)
                                }
                                .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(minWidth: 600, minHeight: 500)
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvString),
            contentType: .commaSeparatedText,
            defaultFilename: appState.connection.selectedTable?.name ?? "export"
        ) { _ in }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private func handleCopyJSON() {
        guard copyToClipboard() else { return }
        showCopiedIcon = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1.75.nanoseconds)
            guard !Task.isCancelled else { return }
            showCopiedIcon = false
            copyFeedbackTask = nil
        }
    }

    private func copyToClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(jsonString, forType: .string)
    }
}

// MARK: - CSV Document

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}
