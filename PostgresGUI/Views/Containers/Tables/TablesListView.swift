//
//  TablesListView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

// Legacy wrapper - kept for compatibility
struct TablesListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TablesListIsolated(
            tables: appState.connection.filteredTables,
            groupedTables: appState.connection.groupedTables,
            selectedSchema: appState.connection.selectedSchema,
            selectedTable: Binding(
                get: { appState.connection.selectedTable },
                set: { appState.connection.selectedTable = $0 }
            ),
            expandedSchemas: Binding(
                get: { appState.connection.expandedSchemas },
                set: { appState.connection.expandedSchemas = $0 }
            ),
            isLoadingTables: appState.connection.isLoadingTables,
            isShowingRefreshFeedback: appState.connection.isRefreshingSidebarMetadata,
            isExecutingQuery: appState.query.isExecutingQuery,
            selectedDatabase: appState.connection.selectedDatabase,
            refreshQueryAction: { table in
                appState.requestTableQuery(for: table)
            }
        )
    }
}

// Isolated view that only depends on explicit parameters, not AppState environment
struct TablesListIsolated: View {
    let tables: [TableInfo]
    let groupedTables: [SchemaGroup]
    let selectedSchema: String?  // nil means "All Schemas"
    @Binding var selectedTable: TableInfo?
    @Binding var expandedSchemas: Set<String>
    let isLoadingTables: Bool
    let isShowingRefreshFeedback: Bool
    let isExecutingQuery: Bool
    let selectedDatabase: DatabaseInfo?

    let refreshQueryAction: (TableInfo) async -> Void

    /// Number of tables to load per batch for incremental rendering
    private static let batchSize = 100

    /// Current number of tables to display (for incremental loading)
    @State private var displayedCount: Int = TablesListIsolated.batchSize

    /// Whether to show grouped view (multiple schemas present)
    private var shouldShowGrouped: Bool {
        groupedTables.count > 1
    }

    /// Tables to display (limited for performance)
    private var displayedTables: ArraySlice<TableInfo> {
        tables.prefix(displayedCount)
    }

    /// Whether there are more tables to load
    private var hasMoreTables: Bool {
        displayedCount < tables.count
    }

    private var shouldShowLoadingIndicator: Bool {
        isLoadingTables && tables.isEmpty
    }

    private var shouldShowRefreshOverlay: Bool {
        isShowingRefreshFeedback || (isLoadingTables && !tables.isEmpty)
    }

    var body: some View {
        let _ = {
            DebugLog.print(
                "🔍 [TablesListView] Body computed - " +
                "isLoadingTables: \(isLoadingTables), " +
                "refreshFeedback: \(isShowingRefreshFeedback), " +
                "effectiveLoading: \(shouldShowLoadingIndicator), " +
                "tablesCount: \(tables.count), " +
                "selectedTable: \(selectedTable?.name ?? "nil"), " +
                "grouped: \(shouldShowGrouped)"
            )
        }()

        baseContent
        .onChange(of: tables.count) { _, _ in
            // Reset displayed count when tables change (e.g., schema filter changed)
            displayedCount = Self.batchSize
        }
        .onChange(of: selectedSchema) { _, _ in
            // Reset displayed count when schema filter changes
            displayedCount = Self.batchSize
        }
    }

    @ViewBuilder
    private var baseContent: some View {
        if tables.isEmpty {
            if shouldShowLoadingIndicator {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if shouldShowGrouped {
            tablesContentWithRefreshOverlay {
                groupedTablesList
            }
        } else {
            tablesContentWithRefreshOverlay {
                flatTablesList
            }
        }
    }

    // MARK: - Flat List (single schema or filtered)

    private var flatTablesList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(displayedTables, id: \.id) { table in
                TableListRowView(
                    table: table,
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction,
                    showSchemaPrefix: selectedSchema == nil
                )
                .padding(.vertical, 2)
                .padding(.leading, 6)
            }

            // "Load more" button when there are more tables to show
            if hasMoreTables {
                loadMoreButton
            }
        }
    }

    private func tablesContentWithRefreshOverlay<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            ScrollView {
                content()
                    .padding(.top, shouldShowGrouped ? 12 : 8)
                    .padding(.bottom, 8)
            }

            if shouldShowRefreshOverlay {
                refreshOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: shouldShowRefreshOverlay)
    }

    private var refreshOverlay: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .opacity(0.45)

            ProgressView()
                .controlSize(.regular)
        }
        .contentShape(Rectangle())
    }

    private var loadMoreButton: some View {
        Button {
            displayedCount = min(displayedCount + Self.batchSize, tables.count)
        } label: {
            HStack {
                Spacer()
                Text("Load more (\(tables.count - displayedCount) remaining)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouped List (multiple schemas)

    private var groupedTablesList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedTables) { group in
                SchemaGroupView(
                    group: group,
                    isExpanded: Binding(
                        get: { expandedSchemas.contains(group.name) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedSchemas.insert(group.name)
                            } else {
                                expandedSchemas.remove(group.name)
                            }
                        }
                    ),
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction
                )
            }
        }
    }
}

// MARK: - Table Row View (Container)

struct TableListRowView: View {
    @Environment(AppState.self) private var appState

    let table: TableInfo
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void
    var showSchemaPrefix: Bool = true

    @State private var viewModel: TableContextMenuViewModel?
    @State private var isLoadingColumns = false

    /// Whether this table's columns are expanded
    private var isExpanded: Bool {
        appState.connection.expandedTables.contains(table.id)
    }

    /// Column info from cache or table
    private var columnInfo: [ColumnInfo]? {
        appState.connection.getColumnInfo(for: table)
    }

    var body: some View {
        TableListRowComponent(
            table: table,
            isExpanded: isExpanded,
            isExecutingQuery: isExecutingQuery,
            columnInfo: columnInfo,
            isLoadingColumns: isLoadingColumns,
            showSchemaPrefix: showSchemaPrefix,
            onToggleExpanded: {
                toggleExpanded()
            },
            onShowAllRows: {
                appState.requestTableQuery(for: table)
            },
            refreshQueryAction: {
                Task {
                    await refreshQueryAction(table)
                }
            },
            onGenerateDDL: {
                Task { @MainActor in
                    let vm = ensureViewModel()
                    await vm.generateDDL()
                }
            },
            onShowExport: {
                ensureViewModel().showExportSheet = true
            },
            onTruncate: {
                ensureViewModel().showTruncateConfirmation = true
            },
            onDrop: {
                ensureViewModel().showDropConfirmation = true
            }
        )
        .modifier(TableContextMenuModalsWrapper(viewModel: $viewModel))
    }

    // MARK: - Actions

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isExpanded {
                appState.connection.expandedTables.remove(table.id)
            } else {
                appState.connection.expandedTables.insert(table.id)
                // Fetch column info if not already cached
                if columnInfo == nil {
                    fetchColumnInfo()
                }
            }
        }
    }

    private func fetchColumnInfo() {
        isLoadingColumns = true
        Task { @MainActor in
            // Fetch column info and primary keys directly without requiring table to be "selected"
            // This bypasses TableMetadataService which has selection guards
            do {
                // Fetch both column info and primary keys in parallel
                async let columnsTask = appState.connection.databaseService.fetchColumnInfo(
                    schema: table.schema,
                    table: table.name
                )
                async let primaryKeysTask = appState.connection.databaseService.fetchPrimaryKeyColumns(
                    schema: table.schema,
                    table: table.name
                )

                var columns = try await columnsTask
                let primaryKeys = try await primaryKeysTask

                // Mark primary key columns
                let pkSet = Set(primaryKeys)
                for i in columns.indices {
                    if pkSet.contains(columns[i].name) {
                        columns[i].isPrimaryKey = true
                    }
                }

                // Cache the result
                appState.connection.tableMetadataCache[table.id] = (
                    primaryKeys: primaryKeys,
                    columns: columns
                )
            } catch {
                DebugLog.print("⚠️ [TableListRowView] Failed to fetch column info for \(table.name): \(error)")
            }
            isLoadingColumns = false
        }
    }

    /// Ensures the viewModel exists, creating it lazily if needed.
    /// Called when menu actions require the ViewModel.
    @MainActor
    private func ensureViewModel() -> TableContextMenuViewModel {
        if let existing = viewModel {
            return existing
        }
        let vm = TableContextMenuViewModel(table: table, appState: appState)
        viewModel = vm
        return vm
    }
}

// MARK: - Table Column Row View (Sidebar)

/// Compact column display for the table sidebar expansion
struct TableColumnRowView: View {
    let column: ColumnInfo

    /// Simplified data type for display
    private var simplifiedType: String {
        let type = column.dataType.lowercased()

        // Map common PostgreSQL types to simplified names
        if type.hasPrefix("character varying") || type.hasPrefix("varchar") {
            return "varchar"
        } else if type.hasPrefix("character") || type == "char" || type == "bpchar" {
            return "char"
        } else if type == "integer" || type == "int4" {
            return "int"
        } else if type == "bigint" || type == "int8" {
            return "bigint"
        } else if type == "smallint" || type == "int2" {
            return "smallint"
        } else if type == "boolean" || type == "bool" {
            return "bool"
        } else if type.hasPrefix("timestamp") {
            return "timestamp"
        } else if type == "date" {
            return "date"
        } else if type == "time" || type.hasPrefix("time ") {
            return "time"
        } else if type.hasPrefix("numeric") || type.hasPrefix("decimal") {
            return "numeric"
        } else if type == "double precision" || type == "float8" {
            return "double"
        } else if type == "real" || type == "float4" {
            return "float"
        } else if type == "text" {
            return "text"
        } else if type == "uuid" {
            return "uuid"
        } else if type == "json" || type == "jsonb" {
            return type
        } else if type == "bytea" {
            return "bytea"
        } else if type.hasSuffix("[]") {
            // Array types
            let baseType = String(type.dropLast(2))
            return "\(baseType)[]"
        } else {
            // Return as-is for other types
            return column.dataType
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Key icon for PK/FK, dot for others
            if column.isPrimaryKey {
                Image(systemName: "key.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else if column.isForeignKey {
                Image(systemName: "key")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            }

            // Column name (50%)
            Text(column.name)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Data type (50%, right-aligned)
            Text(simplifiedType)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 32)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
    }
}

// MARK: - Modals Wrapper

/// Wrapper to safely handle optional viewModel binding
private struct TableContextMenuModalsWrapper: ViewModifier {
    @Binding var viewModel: TableContextMenuViewModel?

    func body(content: Content) -> some View {
        if let vm = viewModel {
            content.tableContextMenuModals(viewModel: vm) {
                // No additional action needed after drop - the ViewModel handles refresh
            }
        } else {
            content
        }
    }
}
