//
//  ConnectionSidebarViewModel.swift
//  PostgresGUI
//
//  Handles connection management, database selection, and CRUD operations.
//  Extracted from ConnectionsDatabasesSidebar to separate business logic from presentation.
//
//  Created by ghazi on 12/30/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class ConnectionSidebarViewModel {
    private struct DeleteDatabaseSnapshot {
        let databases: [DatabaseInfo]
        let selectedDatabase: DatabaseInfo?
        let tables: [TableInfo]
        let selectedTable: TableInfo?
        let schemas: [String]
        let selectedSchema: String?
        let tableMetadataCache: [String: (primaryKeys: [String]?, columns: [ColumnInfo]?)]
        let lastDatabaseName: String?
    }

    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let loadingState: LoadingState
    private let modelContext: ModelContext
    private let keychainService: KeychainServiceProtocol
    private let userDefaults: UserDefaultsProtocol
    private let tableRefreshService: TableRefreshServiceProtocol

    // MARK: - State

    var connectionError: String?
    var showConnectionError = false
    var hasRestoredConnection = false

    // Database state
    var databaseToDelete: DatabaseInfo?
    var deleteError: String?

    // Connection state
    var connectionToDelete: ConnectionProfile?
    private var manualRefreshTask: Task<Void, Never>?
    private var manualRefreshRequestId: Int = 0

    /// Static flag to ensure auto-restore only happens once per app session
    private static var hasRestoredConnectionGlobally = false

    // MARK: - Initialization

    init(
        appState: AppState,
        tabManager: TabManager,
        loadingState: LoadingState,
        modelContext: ModelContext,
        keychainService: KeychainServiceProtocol? = nil,
        userDefaults: UserDefaultsProtocol? = nil,
        tableRefreshService: TableRefreshServiceProtocol? = nil
    ) {
        self.appState = appState
        self.tabManager = tabManager
        self.loadingState = loadingState
        self.modelContext = modelContext
        let keychain = keychainService ?? KeychainServiceImpl()
        self.keychainService = keychain
        self.userDefaults = userDefaults ?? UserDefaultsWrapper()
        self.tableRefreshService = tableRefreshService ?? TableRefreshService(keychainService: keychain)
    }

    // MARK: - Initialization & Restoration

    /// Wait for initial load to complete before restoring connection
    func waitForInitialLoad() async {
        while !loadingState.hasCompletedInitialLoad {
            try? await Task.sleep(nanoseconds: 0.05.nanoseconds)
        }

        if appState.connection.currentConnection != nil {
            hasRestoredConnection = true
            Self.hasRestoredConnectionGlobally = true
        }
    }

    /// Restore the last used connection from UserDefaults
    func restoreLastConnection(connections: [ConnectionProfile]) async {
        guard !hasRestoredConnection,
            !Self.hasRestoredConnectionGlobally,
            appState.connection.currentConnection == nil
        else { return }

        hasRestoredConnection = true
        Self.hasRestoredConnectionGlobally = true

        try? await Task.sleep(nanoseconds: 0.1.nanoseconds)

        guard !connections.isEmpty else { return }

        guard
            let lastConnectionIdString = userDefaults.string(
                forKey: Constants.UserDefaultsKeys.lastConnectionId),
            let lastConnectionId = UUID(uuidString: lastConnectionIdString)
        else {
            if connections.count == 1, let onlyConnection = connections.first {
                await connect(to: onlyConnection)
            }
            return
        }

        guard let lastConnection = connections.first(where: { $0.id == lastConnectionId }) else {
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            return
        }

        await connect(to: lastConnection)
    }

    // MARK: - Connection Management

    /// Connect to a connection profile
    func connect(to connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        switch result {
        case .success:
            try? modelContext.save()
            if appState.connection.databases.isEmpty {
                await refreshDatabasesAsync()
            } else {
                await restoreLastDatabase()
            }

        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
        }
    }

    /// Select and connect to a connection from the dropdown
    func selectConnection(_ connection: ConnectionProfile) async {
        // Skip if already connected to this connection
        guard appState.connection.currentConnection?.id != connection.id else { return }

        // Clear current state before switching
        appState.connection.selectedDatabase = nil
        appState.connection.tables = []
        appState.connection.selectedTable = nil
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)

        await connect(to: connection)
    }

    /// Delete a connection
    func deleteConnection(_ connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )
        await connectionService.delete(connection: connection, from: modelContext)
        connectionToDelete = nil
    }

    // MARK: - Database Management

    /// Select a database
    func selectDatabase(_ database: DatabaseInfo, persistSelection: Bool = true) {
        appState.connection.selectedDatabase = database
        appState.connection.tables = []
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil

        if persistSelection {
            userDefaults.set(
                database.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            tabManager.updateActiveTab(connectionId: nil, databaseName: database.name, queryText: nil)
        }

        Task {
            await loadTables(for: database)
        }
    }

    /// Delete a database with optimistic update
    func deleteDatabase(_ database: DatabaseInfo) async {
        let versionBeforeDelete = appState.connection.databasesVersion
        let snapshot = DeleteDatabaseSnapshot(
            databases: appState.connection.databases,
            selectedDatabase: appState.connection.selectedDatabase,
            tables: appState.connection.tables,
            selectedTable: appState.connection.selectedTable,
            schemas: appState.connection.schemas,
            selectedSchema: appState.connection.selectedSchema,
            tableMetadataCache: appState.connection.tableMetadataCache,
            lastDatabaseName: userDefaults.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
        )
        let wasSelected = snapshot.selectedDatabase?.id == database.id

        // Optimistically remove from UI
        appState.connection.databases.removeAll { $0.id == database.id }
        if wasSelected {
            appState.connection.selectedDatabase = nil
            appState.connection.tables = []
            appState.connection.selectedTable = nil
            appState.connection.schemas = []
            appState.connection.selectedSchema = nil
            appState.connection.tableMetadataCache = [:]
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
        }
        databaseToDelete = nil

        do {
            try await appState.connection.databaseService.deleteDatabase(name: database.name)
            appState.connection.databasesVersion += 1
            await tableRefreshService.refresh(appState: appState)
        } catch {
            // Rollback if databases list hasn't changed
            if isSafeToRollback(
                versionAtOperationStart: versionBeforeDelete,
                currentVersion: appState.connection.databasesVersion
            ) {
                appState.connection.databases = snapshot.databases
                appState.connection.selectedDatabase = snapshot.selectedDatabase
                appState.connection.tables = snapshot.tables
                appState.connection.selectedTable = snapshot.selectedTable
                appState.connection.schemas = snapshot.schemas
                appState.connection.selectedSchema = snapshot.selectedSchema
                appState.connection.tableMetadataCache = snapshot.tableMetadataCache
                if let lastDatabaseName = snapshot.lastDatabaseName {
                    userDefaults.set(lastDatabaseName, forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                } else {
                    userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                }
            }
            deleteError = PostgresError.extractDetailedMessage(error)
        }
    }

    // MARK: - Connection State Change Handling

    /// Handle connection change: clear database selection when connection changes
    func handleConnectionChange(oldValue: ConnectionProfile?, newValue: ConnectionProfile?) {
        if oldValue != nil && newValue != oldValue {
            userDefaults.removeObject(
                forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            appState.connection.selectedDatabase = nil
        }
    }

    /// Update tab when connection changes
    func updateTabForConnectionChange(_ newConnection: ConnectionProfile?) {
        tabManager.updateActiveTab(
            connectionId: newConnection?.id, databaseName: nil, queryText: nil)
    }

    /// Update tab when database changes
    func updateTabForDatabaseChange(_ newDatabase: DatabaseInfo?) {
        tabManager.updateActiveTab(
            connectionId: nil, databaseName: newDatabase?.name, queryText: nil)
    }

    // MARK: - Private Helpers

    private func refreshDatabasesAsync() async {
        do {
            appState.connection.databases = try await appState.connection.databaseService
                .fetchDatabases()
            appState.connection.databasesVersion += 1
            await restoreLastDatabase()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }

    private func restoreLastDatabase() async {
        guard appState.connection.selectedDatabase == nil, !appState.connection.databases.isEmpty
        else { return }

        guard
            let lastDatabaseName = userDefaults.string(
                forKey: Constants.UserDefaultsKeys.lastDatabaseName),
            !lastDatabaseName.isEmpty
        else { return }

        guard
            let lastDatabase = appState.connection.databases.first(where: {
                $0.name == lastDatabaseName
            })
        else {
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }

        selectDatabase(lastDatabase, persistSelection: false)
    }

    private func loadTables(for database: DatabaseInfo) async {
        guard let connection = appState.connection.currentConnection else { return }
        await tableRefreshService.loadTables(
            for: database,
            connection: connection,
            appState: appState
        )
    }

    /// Retry loading tables after a timeout
    func retryTableLoading() async {
        guard let database = appState.connection.selectedDatabase else { return }
        await loadTables(for: database)
    }

    /// Triggered by sidebar toolbar refresh button.
    /// Uses latest-wins semantics for rapid repeated clicks.
    func refreshOnDemandFromToolbar() async {
        manualRefreshRequestId += 1
        let requestId = manualRefreshRequestId
        let hadExistingTask = manualRefreshTask != nil

        if hadExistingTask {
            DebugLog.print(
                "🔄 [ConnectionSidebarViewModel] Cancelling previous manual refresh before starting request \(requestId) " +
                refreshStateSummary()
            )
        }
        manualRefreshTask?.cancel()

        DebugLog.print(
            "🔄 [ConnectionSidebarViewModel] Manual refresh requested " +
            "(id: \(requestId), hadExistingTask: \(hadExistingTask)) " +
            refreshStateSummary()
        )
        manualRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            DebugLog.print(
                "🔄 [ConnectionSidebarViewModel] Manual refresh started " +
                "(id: \(requestId)) " +
                self.refreshStateSummary()
            )
            await self.tableRefreshService.refresh(appState: self.appState)
            let duration = Date().timeIntervalSince(startedAt)
            if Task.isCancelled {
                DebugLog.print(
                    "⚠️ [ConnectionSidebarViewModel] Manual refresh task cancelled " +
                    "(id: \(requestId), duration: \(String(format: "%.3f", duration))s) " +
                    self.refreshStateSummary()
                )
            } else {
                DebugLog.print(
                    "✅ [ConnectionSidebarViewModel] Manual refresh task returned from service " +
                    "(id: \(requestId), duration: \(String(format: "%.3f", duration))s) " +
                    self.refreshStateSummary()
                )
            }
        }
        await manualRefreshTask?.value

        if manualRefreshRequestId == requestId {
            manualRefreshTask = nil
            DebugLog.print(
                "🏁 [ConnectionSidebarViewModel] Manual refresh lifecycle finished " +
                "(id: \(requestId)) " +
                refreshStateSummary()
            )
        } else {
            DebugLog.print(
                "↪️ [ConnectionSidebarViewModel] Manual refresh request \(requestId) completed " +
                "after a newer request became active " +
                refreshStateSummary()
            )
        }
    }

    private func refreshStateSummary() -> String {
        let connectionName = appState.connection.currentConnection?.name ?? "nil"
        let selectedDatabase = appState.connection.selectedDatabase?.name ?? "nil"
        let selectedTable = appState.connection.selectedTable?.id ?? "nil"
        let connectedDatabase = appState.connection.databaseService.connectedDatabase ?? "nil"
        return (
            "(connection: \(connectionName), " +
            "selectedDB: \(selectedDatabase), " +
            "selectedTable: \(selectedTable), " +
            "connectedDB: \(connectedDatabase), " +
            "isConnected: \(appState.connection.databaseService.isConnected), " +
            "isLoadingTables: \(appState.connection.isLoadingTables), " +
            "databases: \(appState.connection.databases.count), " +
            "tables: \(appState.connection.tables.count), " +
            "schemas: \(appState.connection.schemas.count))"
        )
    }
}
