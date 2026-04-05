//
//  ConnectionSidebarViewModelTests.swift
//  PostgresGUITests
//
//  Unit tests for sidebar refresh and database delete behavior.
//

import Foundation
import SwiftData
import Testing
@testable import PostgresGUI

@MainActor
final class ToolbarRefreshMockDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool = true
    var connectedDatabase: String? = "postgres"
    var deleteDatabaseError: Error?
    private(set) var deleteDatabaseCallCount: Int = 0
    private(set) var deleteDatabaseNames: [String] = []

    func connect(host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode) async throws {
        isConnected = true
        connectedDatabase = database
    }

    func disconnect() async {
        isConnected = false
        connectedDatabase = nil
    }

    func shutdown() async {
        isConnected = false
        connectedDatabase = nil
    }

    func interruptInFlightTableBrowseLoadForSupersession() async {}

    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func createDatabase(name: String) async throws {}
    func deleteDatabase(name: String) async throws {
        deleteDatabaseCallCount += 1
        deleteDatabaseNames.append(name)
        if let deleteDatabaseError {
            throw deleteDatabaseError
        }
    }
    func fetchTables(database: String) async throws -> [TableInfo] { [] }
    func fetchSchemas(database: String) async throws -> [String] { [] }
    func deleteTable(schema: String, table: String) async throws {}
    func truncateTable(schema: String, table: String) async throws {}
    func generateDDL(schema: String, table: String) async throws -> String { "" }
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {}
    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String : RowEditValue]) async throws {}
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
}

@MainActor
final class ToolbarRefreshMockService: TableRefreshServiceProtocol {
    var refreshDelayNanoseconds: UInt64 = 0
    private(set) var refreshCallCount: Int = 0
    private(set) var refreshCompletionCount: Int = 0
    private(set) var refreshCancellationCount: Int = 0

    func loadTables(for database: DatabaseInfo, connection: ConnectionProfile, appState: AppState) async {}

    func refresh(appState: AppState) async {
        refreshCallCount += 1

        if refreshDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
            } catch {
                refreshCancellationCount += 1
                return
            }
        }

        if Task.isCancelled {
            refreshCancellationCount += 1
            return
        }

        refreshCompletionCount += 1
    }
}

final class ToolbarRefreshMockUserDefaults: UserDefaultsProtocol {
    private var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

@MainActor
final class ToolbarRefreshMockKeychainService: KeychainServiceProtocol {
    func savePassword(_ password: String, for connectionId: UUID) throws {}
    func getPassword(for connectionId: UUID) throws -> String? { nil }
    func deletePassword(for connectionId: UUID) throws {}
    func saveSSHPassword(_ password: String, for connectionId: UUID) throws {}
    func getSSHPassword(for connectionId: UUID) throws -> String? { nil }
    func deleteSSHPassword(for connectionId: UUID) throws {}
    func saveSSHPassphrase(_ passphrase: String, for connectionId: UUID) throws {}
    func getSSHPassphrase(for connectionId: UUID) throws -> String? { nil }
    func deleteSSHPassphrase(for connectionId: UUID) throws {}
    func saveSSHPrivateKey(_ key: String, for connectionId: UUID) throws {}
    func getSSHPrivateKey(for connectionId: UUID) throws -> String? { nil }
    func deleteSSHPrivateKey(for connectionId: UUID) throws {}
}

@Suite("ConnectionSidebarViewModel")
struct ConnectionSidebarViewModelTests {
    @MainActor
    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ConnectionProfile.self,
            TabState.self,
            SavedQuery.self,
            QueryFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeViewModel(
        refreshService: ToolbarRefreshMockService
    ) throws -> ConnectionSidebarViewModel {
        let context = try makeViewModelContext(
            refreshService: refreshService,
            databaseService: ToolbarRefreshMockDatabaseService(),
            userDefaults: ToolbarRefreshMockUserDefaults()
        )
        return context.viewModel
    }

    @MainActor
    private func makeViewModelContext(
        refreshService: ToolbarRefreshMockService,
        databaseService: ToolbarRefreshMockDatabaseService,
        userDefaults: ToolbarRefreshMockUserDefaults
    ) throws -> (
        viewModel: ConnectionSidebarViewModel,
        appState: AppState,
        refreshService: ToolbarRefreshMockService,
        databaseService: ToolbarRefreshMockDatabaseService,
        userDefaults: ToolbarRefreshMockUserDefaults
    ) {
        let appState = AppState(
            connection: ConnectionState(databaseService: databaseService),
            query: QueryState()
        )
        let viewModel = ConnectionSidebarViewModel(
            appState: appState,
            tabManager: TabManager(),
            loadingState: LoadingState(),
            modelContext: try makeModelContext(),
            keychainService: ToolbarRefreshMockKeychainService(),
            userDefaults: userDefaults,
            tableRefreshService: refreshService
        )
        return (viewModel, appState, refreshService, databaseService, userDefaults)
    }

    @MainActor
    private func makeDefaultViewModelContext() throws -> (
        viewModel: ConnectionSidebarViewModel,
        appState: AppState,
        refreshService: ToolbarRefreshMockService,
        databaseService: ToolbarRefreshMockDatabaseService,
        userDefaults: ToolbarRefreshMockUserDefaults
    ) {
        try makeViewModelContext(
            refreshService: ToolbarRefreshMockService(),
            databaseService: ToolbarRefreshMockDatabaseService(),
            userDefaults: ToolbarRefreshMockUserDefaults()
        )
    }

    @Test
    @MainActor
    func refreshOnDemandFromToolbar_invokesTableRefreshService() async throws {
        let refreshService = ToolbarRefreshMockService()
        let viewModel = try makeViewModel(refreshService: refreshService)

        await viewModel.refreshOnDemandFromToolbar()

        #expect(refreshService.refreshCallCount == 1)
        #expect(refreshService.refreshCompletionCount == 1)
    }

    @Test
    @MainActor
    func refreshOnDemandFromToolbar_cancelsPreviousManualRefreshTask() async throws {
        let refreshService = ToolbarRefreshMockService()
        refreshService.refreshDelayNanoseconds = 250_000_000
        let viewModel = try makeViewModel(refreshService: refreshService)

        let first = Task { await viewModel.refreshOnDemandFromToolbar() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await viewModel.refreshOnDemandFromToolbar() }

        await first.value
        await second.value

        #expect(refreshService.refreshCallCount == 2)
        #expect(refreshService.refreshCancellationCount >= 1)
        #expect(refreshService.refreshCompletionCount == 1)
    }

    @Test
    @MainActor
    func deleteDatabase_selectedDatabase_isAllowedAndClearsDbDependentState() async throws {
        let context = try makeDefaultViewModelContext()
        let selected = DatabaseInfo(name: "hikedb")
        let other = DatabaseInfo(name: "postgres")
        let table = TableInfo(name: "hikes", schema: "public")

        context.appState.connection.databases = [selected, other]
        context.appState.connection.selectedDatabase = selected
        context.appState.connection.tables = [table]
        context.appState.connection.selectedTable = table
        context.appState.connection.schemas = ["public", "audit"]
        context.appState.connection.selectedSchema = "audit"
        context.appState.connection.tableMetadataCache = [
            table.id: (primaryKeys: ["id"], columns: [ColumnInfo(name: "id", dataType: "uuid")])
        ]
        context.userDefaults.set(selected.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)

        await context.viewModel.deleteDatabase(selected)

        #expect(context.databaseService.deleteDatabaseCallCount == 1)
        #expect(context.databaseService.deleteDatabaseNames == ["hikedb"])
        #expect(context.appState.connection.databases.map(\.name) == ["postgres"])
        #expect(context.appState.connection.selectedDatabase == nil)
        #expect(context.appState.connection.tables.isEmpty)
        #expect(context.appState.connection.selectedTable == nil)
        #expect(context.appState.connection.schemas.isEmpty)
        #expect(context.appState.connection.selectedSchema == nil)
        #expect(context.appState.connection.tableMetadataCache.isEmpty)
        #expect(context.userDefaults.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName) == nil)
    }

    @Test
    @MainActor
    func deleteDatabase_selectedDatabase_failure_rollsBackAllState() async throws {
        let databaseService = ToolbarRefreshMockDatabaseService()
        databaseService.deleteDatabaseError = ConnectionError.databaseNotFound("hikedb")
        let context = try makeViewModelContext(
            refreshService: ToolbarRefreshMockService(),
            databaseService: databaseService,
            userDefaults: ToolbarRefreshMockUserDefaults()
        )
        let selected = DatabaseInfo(name: "hikedb")
        let other = DatabaseInfo(name: "postgres")
        let table = TableInfo(name: "hikes", schema: "public")
        let cachedColumns = [ColumnInfo(name: "id", dataType: "uuid")]

        context.appState.connection.databases = [selected, other]
        context.appState.connection.selectedDatabase = selected
        context.appState.connection.tables = [table]
        context.appState.connection.selectedTable = table
        context.appState.connection.schemas = ["public"]
        context.appState.connection.selectedSchema = "public"
        context.appState.connection.tableMetadataCache = [
            table.id: (primaryKeys: ["id"], columns: cachedColumns)
        ]
        context.userDefaults.set(selected.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)

        await context.viewModel.deleteDatabase(selected)

        #expect(context.databaseService.deleteDatabaseCallCount == 1)
        #expect(context.appState.connection.databases.map(\.name) == ["hikedb", "postgres"])
        #expect(context.appState.connection.selectedDatabase?.id == selected.id)
        #expect(context.appState.connection.tables.map(\.id) == [table.id])
        #expect(context.appState.connection.selectedTable?.id == table.id)
        #expect(context.appState.connection.schemas == ["public"])
        #expect(context.appState.connection.selectedSchema == "public")
        #expect(context.appState.connection.tableMetadataCache[table.id]?.primaryKeys == ["id"])
        #expect(context.appState.connection.tableMetadataCache[table.id]?.columns == cachedColumns)
        #expect(context.userDefaults.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName) == "hikedb")
    }

    @Test
    @MainActor
    func deleteDatabase_selectedDatabase_success_triggersRefresh() async throws {
        let refreshService = ToolbarRefreshMockService()
        let context = try makeViewModelContext(
            refreshService: refreshService,
            databaseService: ToolbarRefreshMockDatabaseService(),
            userDefaults: ToolbarRefreshMockUserDefaults()
        )
        let selected = DatabaseInfo(name: "hikedb")
        context.appState.connection.databases = [selected]
        context.appState.connection.selectedDatabase = selected

        await context.viewModel.deleteDatabase(selected)

        #expect(refreshService.refreshCallCount == 1)
    }

    @Test
    @MainActor
    func deleteDatabase_selectedDatabase_clearsLastDatabasePreference() async throws {
        let context = try makeDefaultViewModelContext()
        let selected = DatabaseInfo(name: "hikedb")
        context.appState.connection.databases = [selected]
        context.appState.connection.selectedDatabase = selected
        context.userDefaults.set(selected.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)

        await context.viewModel.deleteDatabase(selected)

        #expect(context.userDefaults.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName) == nil)
    }
}
