//
//  SchemaGroupView.swift
//  PostgresGUI
//
//  Collapsible disclosure group for tables in a schema.
//  Uses conditional rendering instead of DisclosureGroup
//  to avoid eager view construction of collapsed content.
//  Implements incremental loading for large table counts.
//

import SwiftUI

struct SchemaGroupView: View {
    let group: SchemaGroup
    @Binding var isExpanded: Bool
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void

    /// Number of tables to load per batch for incremental rendering
    private static let batchSize = 100

    /// Current number of tables to display (for incremental loading)
    @State private var displayedCount: Int = SchemaGroupView.batchSize
    @State private var isHovered = false

    /// Tables to display (limited for performance)
    private var displayedTables: ArraySlice<TableInfo> {
        group.tables.prefix(displayedCount)
    }

    /// Whether there are more tables to load
    private var hasMoreTables: Bool {
        displayedCount < group.tables.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            schemaHeader

            // Only render tables when expanded - prevents eager view construction
            if isExpanded {
                ForEach(displayedTables, id: \.id) { table in
                    TableListRowView(
                        table: table,
                        isExecutingQuery: isExecutingQuery,
                        refreshQueryAction: refreshQueryAction,
                        showSchemaPrefix: false
                    )
                    .padding(.vertical, 2)
                    .padding(.leading, 6)
                }

                // "Load more" button when there are more tables to show
                if hasMoreTables {
                    Button {
                        displayedCount = min(displayedCount + Self.batchSize, group.tables.count)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Load more (\(group.tables.count - displayedCount) remaining)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if !newValue {
                // Reset pagination when collapsed
                displayedCount = Self.batchSize
            }
        }
    }

    private var schemaHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(group.name)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(group.tableCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(group.name), \(group.tableCount) tables")
    }
}
