//
//  QueryResultsComponent.swift
//  PostgresGUI
//
//  Presentational component for displaying query results.
//  Receives data and callbacks - does not access AppState directly.
//

import SwiftUI

// MARK: - Table Row Comparator

struct TableRowComparator: SortComparator, Hashable {
    let columnName: String
    var order: SortOrder = .forward

    func compare(_ lhs: TableRow, _ rhs: TableRow) -> ComparisonResult {
        let result = compareValues(lhs.values[columnName] ?? nil, rhs.values[columnName] ?? nil)
        return order == .reverse ? result.reversed : result
    }

    private func compareValues(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (v1?, v2?):
            return v1.localizedStandardCompare(v2)
        }
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

// MARK: - Query Results Component

struct QueryResultsComponent: View {
    @AppStorage(Constants.UserDefaultsKeys.queryResultsDateFormat)
    private var dateFormatRawValue = QueryResultsDateFormat.iso8601.rawValue

    // Data
    let results: [TableRow]
    let columnNames: [String]?
    let searchText: String
    let isExecuting: Bool
    let errorMessage: String?
    let hasExecutedQuery: Bool
    let currentPage: Int
    let hasNextPage: Bool
    let tableId: String?
    
    // Bindings
    @Binding var selectedRowIDs: Set<TableRow.ID>
    
    // Callbacks
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    var onDeleteKeyPressed: (() -> Void)?
    var onSpaceKeyPressed: (() -> Void)?
    
    // Local state for sorting
    @State private var sortOrder: [TableRowComparator] = []
    
    private var hasPreviousPage: Bool {
        currentPage > 0
    }
    
    private var showPagination: Bool {
        !results.isEmpty
    }

    private var tableIdentity: String {
        let tablePart = tableId ?? "no-table"
        let columnsPart = columnNames?.joined(separator: "|") ?? "no-columns"
        return "\(tablePart)|\(columnsPart)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExecuting {
                loadingView
            } else {
                resultsContent

                // Pagination row (always show if there are results)
                if showPagination {
                    paginationBar
                }
            }
        }
        .padding(.leading, 4)
        .onChange(of: tableId) { oldValue, newValue in
            // Reset sort order when table changes
            if oldValue != newValue {
                sortOrder = []
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let errorMessage = errorMessage {
            ContentUnavailableView {
                Label {
                    Text("Query Failed")
                        .font(.title3)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            } description: {
                Text(errorMessage)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            // Show empty table with headers if column names are available
            if let columnNames = columnNames, !columnNames.isEmpty {
                // Empty table with overlay empty state message
                emptyTableWithHeaders(columnNames: columnNames)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .center) {
                        EmptyQueryResultsView(hasExecutedQuery: hasExecutedQuery)
                    }
            } else {
                EmptyQueryResultsView(hasExecutedQuery: hasExecutedQuery)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Display results using SwiftUI Table
            resultsTable
        }
    }

    private var loadingView: some View {
        ProgressView("Loading results...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var paginationBar: some View {
        HStack {
            Text("\(results.count) rows shown")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    onPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!hasPreviousPage || isExecuting)

                Text(hasNextPage ? "Page \(currentPage + 1) of ?" : "Page \(currentPage + 1) of \(currentPage + 1)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("Total pages are not computed automatically to keep queries fast.")

                Button {
                    onNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!hasNextPage || isExecuting)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var resultsTable: some View {
        if let columnNames = columnNames {
            Table(sortedResults, selection: $selectedRowIDs, sortOrder: $sortOrder) {
                TableColumnForEach(columnNames, id: \.self) { columnName in
                    TableColumn(columnName, sortUsing: TableRowComparator(columnName: columnName)) { row in
                        Text(formatValue(row.values[columnName] ?? nil))
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    .width(min: Constants.ColumnWidth.tableColumnMin)
                }
            }
            .alwaysShowScrollbars()
            .id(tableIdentity)
            .onDeleteCommand {
                if !selectedRowIDs.isEmpty {
                    onDeleteKeyPressed?()
                }
            }
            .onKeyPress(.space) {
                if !selectedRowIDs.isEmpty {
                    onSpaceKeyPressed?()
                    return .handled
                }
                return .ignored
            }
        }
    }

    @ViewBuilder
    private func emptyTableWithHeaders(columnNames: [String]) -> some View {
        // Create a Table with just headers, no rows
        Table([] as [TableRow], selection: .constant(Set<TableRow.ID>())) {
            TableColumnForEach(columnNames, id: \.self) { columnName in
                TableColumn(columnName) { row in
                    Text(formatValue(row.values[columnName] ?? nil))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: Constants.ColumnWidth.tableColumnMin)
            }
        }
        .id(tableIdentity)
    }

    private var filteredResults: [TableRow] {
        guard !searchText.isEmpty else { return results }
        let lowercasedSearch = searchText.lowercased()
        return results.filter { row in
            row.values.values.contains { value in
                guard let value = value else { return false }
                return value.lowercased().contains(lowercasedSearch)
            }
        }
    }

    private var sortedResults: [TableRow] {
        let filtered = filteredResults
        guard !sortOrder.isEmpty else { return filtered }
        return filtered.sorted(using: sortOrder)
    }

    private func formatValue(_ value: String?) -> String {
        guard let value = value else { return "NULL" }
        guard Self.shouldAttemptDateParsing(value) else {
            return value
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.shouldAttemptDateParsing(trimmedValue) else {
            return value
        }
        guard let date = parseDate(from: trimmedValue) else {
            return value
        }

        switch selectedDateFormat {
        case .relative:
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        default:
            return selectedDateFormat.formatter.string(from: date)
        }
    }

    private var selectedDateFormat: QueryResultsDateFormat {
        QueryResultsDateFormat(rawValue: dateFormatRawValue) ?? .iso8601
    }

    private func parseDate(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        if let date = Self.iso8601ParserWithFractional.date(from: value) {
            return date
        }

        if let date = Self.iso8601Parser.date(from: value) {
            return date
        }

        for formatter in Self.customParsers {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static let iso8601Parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601ParserWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let customParsers: [DateFormatter] = [
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss.SSS"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ssZ"),
        makeParsingFormatter("yyyy-MM-dd HH:mm:ss.SSSZ"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        makeParsingFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        makeParsingFormatter("yyyy-MM-dd")
    ]

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let maxDateParseLength = 64

    static func shouldAttemptDateParsing(_ value: String) -> Bool {
        guard !value.isEmpty, !isLongerThanDateParseLimit(value) else { return false }

        var hasDigit = false
        var hasDateMarker = false

        for scalar in value.unicodeScalars {
            if !hasDigit, CharacterSet.decimalDigits.contains(scalar) {
                hasDigit = true
            }

            if !hasDateMarker {
                switch scalar {
                case "-", "/", ":", "T", "t":
                    hasDateMarker = true
                default:
                    break
                }
            }

            if hasDigit && hasDateMarker {
                return true
            }
        }

        return false
    }

    private static func isLongerThanDateParseLimit(_ value: String) -> Bool {
        var count = 0
        for _ in value.utf8 {
            count += 1
            if count > maxDateParseLength {
                return true
            }
        }
        return false
    }

    private static func makeParsingFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
