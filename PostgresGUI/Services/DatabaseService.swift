//
//  DatabaseService.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import Logging

@MainActor
class DatabaseService {
    // MARK: - Core Dependencies

    // Connection manager (actor-isolated) - protocol for testability
    private let connectionManager: ConnectionManagerProtocol
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.service")

    // Specialized services (lazy to avoid circular dependencies)
    private lazy var tableService = TableService(connectionManager: connectionManager, queryExecutor: queryExecutor)
    private lazy var metadataService = MetadataService(connectionManager: connectionManager, queryExecutor: queryExecutor)
    private lazy var databaseManagementService = DatabaseManagementService(
        connectionManager: connectionManager,
        queryExecutor: queryExecutor
    )
    private lazy var liveAutocompleteMetadataProvider = DatabaseMetadataProvider(
        catalogService: AutocompleteCatalogService(connectionManager: connectionManager)
    )

    // MARK: - Connection State

    // Connection state (tracked synchronously for UI access)
    // NOTE: This is the single source of truth for connection state
    // AppState.isConnected is a computed property that reads from this
    private var currentDatabase: String?
    private var _isConnected: Bool = false

    var isConnected: Bool {
        _isConnected
    }

    var connectedDatabase: String? {
        currentDatabase
    }

    var autocompleteMetadataProvider: DatabaseMetadataProvider? {
        liveAutocompleteMetadataProvider
    }

    init(
        connectionManager: ConnectionManagerProtocol = PostgresConnectionManager(),
        queryExecutor: QueryExecutorProtocol? = nil
    ) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor ?? PostgresQueryExecutor()
        logger.info("DatabaseService initialized")
    }

    // MARK: - Connection Management

    /// Connect to PostgreSQL database
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws {
        // Validate inputs
        guard !host.isEmpty else {
            throw ConnectionError.invalidHost(host)
        }

        guard port > 0 && port <= 65535 else {
            throw ConnectionError.invalidPort
        }

        logger.info("Connecting to \(host):\(port), database: \(database)")
        await liveAutocompleteMetadataProvider.clear()

        // Get abstract TLS mode from SSLMode
        let tlsMode = sslMode.databaseTLSMode

        // Clear state before reconnecting to prevent stale reads by concurrent tasks
        // This ensures _isConnected is false while connection is in progress
        _isConnected = false
        currentDatabase = nil

        do {
            try await connectionManager.connect(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tlsMode: tlsMode
            )

            currentDatabase = database
            _isConnected = true
            warmAutocompleteMetadata()
            logger.info("Successfully connected")
        } catch {
            logger.error("Connection failed: \(error)")
            _isConnected = false
            await liveAutocompleteMetadataProvider.clear()
            throw error
        }
    }

    /// Disconnect from database
    func disconnect() async {
        logger.info("Disconnecting")
        await connectionManager.disconnect()
        await liveAutocompleteMetadataProvider.clear()
        currentDatabase = nil
        _isConnected = false
    }

    /// Full shutdown including all resources - call on app termination
    func shutdown() async {
        logger.info("Shutting down DatabaseService")
        await connectionManager.shutdown()
        await liveAutocompleteMetadataProvider.clear()
        currentDatabase = nil
        _isConnected = false
    }

    /// Interrupt in-flight table-browse work for supersession.
    /// Keeps logical connection state intact while connection manager transparently reconnects.
    func interruptInFlightTableBrowseLoadForSupersession() async {
        await connectionManager.interruptInFlightOperationForSupersession()
    }

    /// Test connection without saving (static method - doesn't require instance)
    nonisolated static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws -> Bool {
        let tlsMode = sslMode.databaseTLSMode

        return try await PostgresConnectionManager.testConnection(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tlsMode: tlsMode
        )
    }

    private func warmAutocompleteMetadata() {
        let provider = liveAutocompleteMetadataProvider
        let logger = self.logger

        Task {
            do {
                try await provider.refresh()
            } catch {
                logger.warning("Autocomplete metadata warm-up failed: \(error)")
            }
        }
    }

    // MARK: - Database Operations (Delegated to DatabaseManagementService)

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchDatabases()
    }

    /// Create a new database
    func createDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await databaseManagementService.createDatabase(name: name)
    }

    /// Delete a database
    func deleteDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        if currentDatabase == name {
            let maintenanceCandidates = ["postgres", "template1"].filter { $0 != name }
            var reconnectErrors: [String] = []
            var switchedDatabase: String?
            var lastReconnectError: Error?

            for candidate in maintenanceCandidates {
                do {
                    logger.info("Switching away from target database '\(name)' to maintenance database '\(candidate)' before drop")
                    try await connectionManager.reconnectUsingStoredCredentials(database: candidate)
                    switchedDatabase = candidate
                    break
                } catch {
                    lastReconnectError = error
                    reconnectErrors.append("\(candidate): \(error.localizedDescription)")
                    logger.warning("Failed maintenance reconnect candidate '\(candidate)': \(error)")
                }
            }

            guard let switchedDatabase else {
                _isConnected = false
                currentDatabase = nil
                logger.error("Unable to switch away from '\(name)' before drop. Errors: \(reconnectErrors.joined(separator: " | "))")
                throw lastReconnectError ?? ConnectionError.notConnected
            }

            currentDatabase = switchedDatabase
            _isConnected = true
        }

        try await databaseManagementService.deleteDatabase(name: name)
    }

    // MARK: - Table Operations (Delegated to TableService)

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.fetchTables(database: database)
    }

    /// Fetch list of schemas in the connected database
    func fetchSchemas(database: String) async throws -> [String] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.fetchSchemas(database: database)
    }

    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.fetchTableData(
            schema: schema,
            table: table,
            offset: offset,
            limit: limit
        )
    }

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await tableService.deleteTable(schema: schema, table: table)
    }

    /// Truncate a table (delete all rows)
    func truncateTable(schema: String, table: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await tableService.truncateTable(schema: schema, table: table)
    }

    /// Generate DDL (CREATE TABLE statement) for a table
    func generateDDL(schema: String, table: String) async throws -> String {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.generateDDL(schema: schema, table: table)
    }

    /// Fetch all table data (no pagination, for export)
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.fetchAllTableData(schema: schema, table: table)
    }

    // MARK: - Query Execution

    /// Execute arbitrary SQL query and return results along with column names
    /// Supports multi-statement scripts by splitting and executing sequentially
    /// Wraps in transaction for atomicity (unless user already has transaction commands)
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        try await executeQueryInternal(sql, wrapPolicy: .none)
    }

    /// Execute SQL intended for query results display
    /// Wraps select queries for safe display formatting
    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        try await executeQueryInternal(sql, wrapPolicy: .wrapSelectResults)
    }

    private func executeQueryInternal(
        _ sql: String,
        wrapPolicy: QueryWrapPolicy
    ) async throws -> ([TableRow], [String]) {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.info("Executing query")
        logger.debug("SQL: \(sql.prefix(200))")

        let queryExecutor = self.queryExecutor

        // Split SQL into individual statements to work around PostgresNIO limitation
        // (doesn't support multiple commands in a single prepared statement)
        let statements = SQLStatementSplitter.split(sql)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !statements.isEmpty else {
            return ([], [])
        }

        // Single statement - no transaction wrapper needed
        if statements.count == 1 {
            let wrappedQuery = QueryWrapper.wrapIfNeeded(sql: statements[0], policy: wrapPolicy)
            return try await connectionManager.withConnection { conn in
                let (rows, columnNames) = try await queryExecutor.executeQuery(
                    connection: conn,
                    sql: wrappedQuery.sql
                )
                return (rows, Self.normalizedColumnNames(columnNames, wrappedQuery: wrappedQuery))
            }
        }

        // Multiple statements - wrap in transaction if user hasn't already
        // Execute all within single connection block for atomicity
        let needsTransaction = !Self.containsTransactionCommands(sql)

        return try await connectionManager.withConnection { conn in
            var lastRows: [TableRow] = []
            var lastColumnNames: [String] = []

            do {
                if needsTransaction {
                    _ = try await queryExecutor.executeQuery(connection: conn, sql: "BEGIN")
                }

                for statement in statements {
                    let wrappedQuery = QueryWrapper.wrapIfNeeded(sql: statement, policy: wrapPolicy)
                    let (rows, columnNames) = try await queryExecutor.executeQuery(
                        connection: conn,
                        sql: wrappedQuery.sql
                    )
                    let normalizedColumns = Self.normalizedColumnNames(columnNames, wrappedQuery: wrappedQuery)

                    if wrappedQuery.isWrapped || !rows.isEmpty {
                        lastRows = rows
                        lastColumnNames = normalizedColumns
                    }
                }

                if needsTransaction {
                    _ = try await queryExecutor.executeQuery(connection: conn, sql: "COMMIT")
                }
            } catch {
                if needsTransaction {
                    _ = try? await queryExecutor.executeQuery(connection: conn, sql: "ROLLBACK")
                }
                throw error
            }

            return (lastRows, lastColumnNames)
        }
    }

    private static func normalizedColumnNames(
        _ columnNames: [String],
        wrappedQuery: WrappedQuery
    ) -> [String] {
        guard let expected = wrappedQuery.expectedColumnNames else {
            return columnNames
        }
        return expected
    }

    /// Check if SQL contains transaction control commands
    /// Note: We intentionally exclude "END" as it conflicts with PL/pgSQL block syntax.
    /// Users who use "END" for transactions (rare) will just get nested transactions, which is safe.
    private static func containsTransactionCommands(_ sql: String) -> Bool {
        let upperSQL = sql.uppercased()
        let transactionKeywords = ["BEGIN", "START TRANSACTION", "COMMIT", "ROLLBACK", "SAVEPOINT"]
        return transactionKeywords.contains { keyword in
            // Match keyword as whole word (not part of identifier)
            let pattern = "\\b\(keyword)\\b"
            return upperSQL.range(of: pattern, options: .regularExpression) != nil
        }
    }

    // MARK: - Metadata Operations (Delegated to MetadataService)

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchPrimaryKeyColumns(schema: schema, table: table)
    }

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchColumnInfo(schema: schema, table: table)
    }

    // MARK: - Row Operations

    /// Delete rows from a table using primary key values
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        logger.info("Deleting \(rows.count) rows from \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await self.queryExecutor.deleteRows(
                connection: conn,
                schema: schema,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                rows: rows
            )
        }
    }

    /// Update a row in a table using primary key values
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        logger.info("Updating row in \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await self.queryExecutor.updateRow(
                connection: conn,
                schema: schema,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                originalRow: originalRow,
                updatedValues: updatedValues
            )
        }
    }
}
