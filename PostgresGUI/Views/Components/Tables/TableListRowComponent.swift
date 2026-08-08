//
//  TableListRowComponent.swift
//  PostgresGUI
//
//  Presentational component for a table row in the tables list.
//  Receives data and callbacks - does not access AppState directly.
//

import SwiftUI

struct TableListRowComponent: View {
    // Data
    let table: TableInfo
    let isExpanded: Bool
    let isExecutingQuery: Bool
    let columnInfo: [ColumnInfo]?
    let isLoadingColumns: Bool
    var showSchemaPrefix: Bool = true
    
    // Callbacks
    let onToggleExpanded: () -> Void
    let onShowAllRows: () -> Void
    let refreshQueryAction: () -> Void
    let onGenerateDDL: () -> Void
    let onShowExport: () -> Void
    let onTruncate: () -> Void
    let onDrop: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var isNameHovered = false

    /// Display name based on whether schema prefix should be shown
    private var displayText: String {
        showSchemaPrefix ? table.displayName : table.name
    }

    private let rowControlHeight: CGFloat = 24
    private let rowCornerRadius: CGFloat = 6

    private var rowBackground: Color {
        isHovered ? Color.secondary.opacity(0.12) : Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main table row
            tableHeader

            // Column list (shown when expanded)
            if isExpanded {
                columnsList
            }
        }
        .contextMenu {
            tableMenuContent
        }
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Expand/collapse chevron
            Button {
                onToggleExpanded()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20, height: rowControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Table name click shows query results
            Button {
                onShowAllRows()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isNameHovered ? "play.circle.fill" : (table.tableType == .foreign ? "tablecells.fill" : "tablecells"))
                        .foregroundStyle(isNameHovered ? .green : .secondary)
                        .frame(width: 14, alignment: .center)
                    if showSchemaPrefix && table.schema != "public" {
                        HStack(spacing: 2) {
                            Text(table.schema)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(".")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(table.name)
                                .lineLimit(1)
                        }
                    } else {
                        Text(displayText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: rowControlHeight)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .help(displayText)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isNameHovered = hovering
            }
            .overlay(alignment: .trailing) {
                Menu {
                    tableMenuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isButtonHovered ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(isButtonHovered ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        .opacity((isHovered || isButtonHovered) ? 1.0 : 0.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .background(rowBackground, in: RoundedRectangle(cornerRadius: rowCornerRadius))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Columns List

    private var columnsList: some View {
        Group {
            if isLoadingColumns {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.leading, 44)
            } else if let columns = columnInfo, !columns.isEmpty {
                ForEach(columns) { column in
                    TableColumnRowView(column: column)
                }
            } else {
                Text("No columns found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 44)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var tableMenuContent: some View {
        // Refresh
        Button {
            refreshQueryAction()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(isExecutingQuery)

        Divider()

        // Generate DDL
        Button {
            onGenerateDDL()
        } label: {
            Label("Generate DDL", systemImage: "doc.text")
        }
        .disabled(isExecutingQuery)

        // Export
        Button {
            onShowExport()
        } label: {
            Label("Export...", systemImage: "square.and.arrow.up")
        }
        .disabled(isExecutingQuery)

        Divider()

        // Truncate (destructive)
        Button(role: .destructive) {
            onTruncate()
        } label: {
            Label("Truncate...", systemImage: "trash.slash")
        }
        .disabled(isExecutingQuery)

        // Drop (destructive)
        Button(role: .destructive) {
            onDrop()
        } label: {
            Label("Drop...", systemImage: "trash")
        }
        .disabled(isExecutingQuery)
    }
}

#Preview {
    let sampleTable = TableInfo(name: "quotes", schema: "public")
    let sampleColumns: [ColumnInfo] = [
        ColumnInfo(name: "id", dataType: "uuid", isPrimaryKey: true),
        ColumnInfo(name: "source_id", dataType: "uuid"),
        ColumnInfo(name: "doc_id", dataType: "varchar"),
        ColumnInfo(name: "created_by", dataType: "varchar"),
        ColumnInfo(name: "content", dataType: "text"),
        ColumnInfo(name: "details", dataType: "jsonb"),
        ColumnInfo(name: "page_number", dataType: "int"),
        ColumnInfo(name: "created_at", dataType: "timestamp"),
        ColumnInfo(name: "updated_at", dataType: "timestamp")
    ]

    return VStack(spacing: 12) {
        TableListRowComponent(
            table: sampleTable,
            isExpanded: false,
            isExecutingQuery: false,
            columnInfo: sampleColumns,
            isLoadingColumns: false,
            showSchemaPrefix: true,
            onToggleExpanded: {},
            onShowAllRows: {},
            refreshQueryAction: {},
            onGenerateDDL: {},
            onShowExport: {},
            onTruncate: {},
            onDrop: {}
        )

        TableListRowComponent(
            table: sampleTable,
            isExpanded: true,
            isExecutingQuery: false,
            columnInfo: sampleColumns,
            isLoadingColumns: false,
            showSchemaPrefix: true,
            onToggleExpanded: {},
            onShowAllRows: {},
            refreshQueryAction: {},
            onGenerateDDL: {},
            onShowExport: {},
            onTruncate: {},
            onDrop: {}
        )
    }
    .padding()
    .frame(width: 320)
}
