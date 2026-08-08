//
//  DatabaseServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol defining the interface for database operations
@MainActor
protocol DatabaseServiceProtocol: AnyObject {
    // MARK: - Connection State

    /// Whether currently connected to a database
    var isConnected: Bool { get }

    /// The currently connected database name, if any
    var connectedDatabase: String? { get }

    /// Shared metadata cache backing SQL autocomplete.
    var autocompleteMetadataProvider: DatabaseMetadataProvider? { get }

    // MARK: - Connection Management

    /// Connect to PostgreSQL database
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode
    ) async throws

    /// Disconnect from the current database
    func disconnect() async

    /// Full shutdown including all resources - call on app termination
    func shutdown() async

    /// Interrupt in-flight table-browse work when a newer sidebar request supersedes it.
    /// This should not update logical connection state exposed to the UI.
    func interruptInFlightTableBrowseLoadForSupersession() async

    // MARK: - Database Operations

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo]

    /// Create a new database
    func createDatabase(name: String) async throws

    /// Delete a database
    func deleteDatabase(name: String) async throws

    // MARK: - Table Operations

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo]

    /// Fetch list of schemas in the connected database
    func fetchSchemas(database: String) async throws -> [String]

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws

    /// Truncate a table (delete all rows)
    func truncateTable(schema: String, table: String) async throws

    /// Generate DDL (CREATE TABLE statement) for a table
    func generateDDL(schema: String, table: String) async throws -> String

    /// Fetch all table data (no pagination, for export)
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String])

    // MARK: - Query Execution

    /// Execute arbitrary SQL query and return results along with column names
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String])

    /// Execute SQL intended for query results display
    /// Wraps select queries for safe display formatting
    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String])

    // MARK: - Row Operations

    /// Delete rows from a table using primary key values
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws

    /// Update a row in a table using primary key values
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws

    // MARK: - Metadata Operations

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String]

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo]
}

// MARK: - DatabaseService Conformance

extension DatabaseService: DatabaseServiceProtocol {
    // DatabaseService already implements all required methods
    // No additional implementation needed
}

extension DatabaseServiceProtocol {
    var autocompleteMetadataProvider: DatabaseMetadataProvider? {
        nil
    }
}
