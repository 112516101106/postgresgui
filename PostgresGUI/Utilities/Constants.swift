//
//  Constants.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

/// Design system constants following Liquid Glass patterns
enum Constants {
    // Font sizes
    enum FontSize {
        /// Small text used for tabs, picker labels, status text (11pt)
        static let small: CGFloat = 11
        /// Icon size for small UI elements
        static let smallIcon: CGFloat = 10
    }

    // Spacing
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    // Column widths
    enum ColumnWidth {
        static let sidebarMin: CGFloat = 200
        static let sidebarIdeal: CGFloat = 250
        static let sidebarMax: CGFloat = 300
        
        static let tablesMin: CGFloat = 250
        static let tablesIdeal: CGFloat = 300
        static let tablesMax: CGFloat = 400
        
        static let tableColumnMin: CGFloat = 120
    }
    
    // Pagination
    enum Pagination {
        static let defaultRowsPerPage: Int = 100
        static let minRowsPerPage: Int = 10
        static let maxRowsPerPage: Int = 1000
    }

    // Table browse payload compaction
    static let tableBrowseMaxCellCharacters: Int = 2048
    static let tableBrowseTruncationSuffix: String = "... [truncated]"
    static let tableBrowseMaxCachedPages: Int = 3
    
    // PostgreSQL defaults
    enum PostgreSQL {
        static let defaultPort: Int = 5432
        static let defaultDatabase: String = "postgres"
        static let defaultUsername: String = "postgres"
    }
    
    // UserDefaults keys
    enum UserDefaultsKeys {
        static let lastConnectionId = "lastConnectionId"
        static let lastDatabaseName = "lastDatabaseName"
        static let queryResultsDateFormat = "queryResultsDateFormat"
    }

    // Timeouts
    enum Timeout {
        /// Default timeout for database operations (queries, table loading)
        /// Set to 5 minutes to allow long-running queries while still providing safety
        static let databaseOperation: TimeInterval = 300.0
    }
}

enum QueryResultsDateFormat: String, CaseIterable, Identifiable {
    case iso8601
    case iso8601DateOnly
    case us
    case european
    case relative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iso8601:
            return "ISO 8601"
        case .iso8601DateOnly:
            return "ISO 8601 (date only)"
        case .us:
            return "US"
        case .european:
            return "European"
        case .relative:
            return "Relative"
        }
    }

    var example: String {
        switch self {
        case .relative:
            return Self.relativeFormatter.localizedString(
                for: Date().addingTimeInterval(-7200),
                relativeTo: Date()
            )
        default:
            return formatter.string(from: Self.sampleDate)
        }
    }

    var formatter: DateFormatter {
        switch self {
        case .iso8601:
            return Self.iso8601DateTimeFormatter
        case .iso8601DateOnly:
            return Self.iso8601DateFormatter
        case .us:
            return Self.usFormatter
        case .european:
            return Self.europeanFormatter
        case .relative:
            return Self.iso8601DateTimeFormatter
        }
    }

    func string(from date: Date, relativeTo referenceDate: Date = Date()) -> String {
        switch self {
        case .relative:
            return Self.relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
        default:
            return formatter.string(from: date)
        }
    }

    private static let sampleDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 14
        components.hour = 10
        components.minute = 30
        components.second = 45
        return Calendar.current.date(from: components) ?? Date()
    }()

    private static let iso8601DateTimeFormatter = makeFormatter("yyyy-MM-dd HH:mm:ss")
    private static let iso8601DateFormatter = makeFormatter("yyyy-MM-dd")
    private static let usFormatter = makeFormatter("MM/dd/yyyy h:mm a")
    private static let europeanFormatter = makeFormatter("dd/MM/yyyy HH:mm")
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
