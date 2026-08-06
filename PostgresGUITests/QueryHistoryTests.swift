//
//  QueryHistoryTests.swift
//  PostgresGUITests
//

import Testing
import SwiftData
import Foundation
@testable import PostgresGUI

@MainActor
struct QueryHistoryTests {

    @Test
    func testQueryHistoryInitializationAndStorage() throws {
        // Setup in-memory SwiftData container for testing
        let container = try PostgresGUIModelContainerFactory.makeModelContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext

        // Define test data
        let testQuery = "SELECT * FROM users"
        let testDatabase = "production_db"
        let testExecutionTime: TimeInterval = 1.5

        // Initialize model
        let historyEntry = QueryHistory(
            queryText: testQuery,
            executionTime: testExecutionTime,
            isSuccess: true,
            databaseName: testDatabase
        )

        // Save to context
        context.insert(historyEntry)
        try context.save()

        // Fetch from context
        let fetchDescriptor = FetchDescriptor<QueryHistory>()
        let savedEntries = try context.fetch(fetchDescriptor)

        // Verify
        #expect(savedEntries.count == 1)
        let savedEntry = try #require(savedEntries.first)

        #expect(savedEntry.queryText == testQuery)
        #expect(savedEntry.executionTime == testExecutionTime)
        #expect(savedEntry.isSuccess == true)
        #expect(savedEntry.databaseName == testDatabase)
    }

    @Test
    func migrationFromV1PreservesExistingSavedQueries() throws {
        let storeURL = temporaryStoreURL()

        do {
            let oldSchema = Schema(versionedSchema: PostgresGUISchemaV1.self)
            let oldConfiguration = ModelConfiguration("default", schema: oldSchema, url: storeURL)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])
            let oldContext = oldContainer.mainContext

            oldContext.insert(ConnectionProfile(
                name: "Local",
                host: "localhost",
                username: "postgres",
                database: "app"
            ))
            oldContext.insert(SavedQuery(
                name: "List users",
                queryText: "SELECT * FROM users"
            ))
            try oldContext.save()
        }

        let migratedContainer = try PostgresGUIModelContainerFactory.makeModelContainer(url: storeURL)
        let migratedContext = migratedContainer.mainContext
        let profiles = try migratedContext.fetch(FetchDescriptor<ConnectionProfile>())
        let savedQueries = try migratedContext.fetch(FetchDescriptor<SavedQuery>())
        let history = try migratedContext.fetch(FetchDescriptor<QueryHistory>())

        #expect(profiles.count == 1)
        #expect(profiles.first?.host == "localhost")
        #expect(savedQueries.count == 1)
        #expect(savedQueries.first?.queryText == "SELECT * FROM users")
        #expect(history.isEmpty)
    }

    @Test
    func queryEditorExecutionPersistsHistoryEntry() async throws {
        let container = try PostgresGUIModelContainerFactory.makeModelContainer(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let connectionId = UUID()
        let queryText = "SELECT 42 AS answer"
        let queryService = QueryHistoryMockQueryService(result: .success(
            rows: [TableRow(values: ["answer": "42"])],
            columnNames: ["answer"],
            executionTime: 0.25
        ))

        let connectionState = ConnectionState(databaseService: DelayedMockDatabaseService())
        connectionState.currentConnection = ConnectionProfile(
            id: connectionId,
            name: "Local",
            host: "localhost",
            username: "postgres",
            database: "analytics"
        )
        connectionState.selectedDatabase = DatabaseInfo(name: "analytics")

        let appState = AppState(connection: connectionState, query: QueryState())
        appState.query.queryText = queryText

        let tabManager = TabManager()
        tabManager.activeTab = TabViewModel(isActive: true)
        tabManager.tabs = [tabManager.activeTab!]

        let viewModel = QueryEditorViewModel(
            appState: appState,
            tabManager: tabManager,
            modelContext: context,
            queryService: queryService
        )

        await viewModel.executeQuery()

        let entries = try context.fetch(FetchDescriptor<QueryHistory>())
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.queryText == queryText)
        #expect(entry.executionTime == 0.25)
        #expect(entry.isSuccess)
        #expect(entry.databaseName == "analytics")
        #expect(entry.connectionId == connectionId)
    }

    @Test
    func exportFormattingUsesReplayableSQLAndISO8601JSON() throws {
        let entry = QueryHistory(
            queryText: "SELECT 1",
            executionDate: Date(timeIntervalSince1970: 0),
            executionTime: 0.0123,
            isSuccess: true,
            databaseName: "app"
        )

        let sql = QueryHistoryExporter.sqlString(for: [entry])
        #expect(sql.contains("SELECT 1;"))

        let json = try String(decoding: QueryHistoryExporter.jsonData(for: [entry]), as: UTF8.self)
        #expect(json.contains("\"executionDate\" : \"1970-01-01T00:00:00Z\""))

        let csv = QueryHistoryExporter.csvString(for: [QueryHistory(
            queryText: "SELECT \"quoted\", value",
            executionTime: 0.1,
            isSuccess: false,
            databaseName: "app"
        )])
        #expect(csv.contains("\"SELECT \"\"quoted\"\", value\""))
    }

    private func temporaryStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store")
    }
}

@MainActor
private final class QueryHistoryMockQueryService: QueryServiceProtocol {
    let result: QueryResult

    init(result: QueryResult) {
        self.result = result
    }

    func executeQuery(_ sql: String, preferredColumnOrder: [String]?) async -> QueryResult {
        result
    }

    func executeTableQuery(
        for table: TableInfo,
        limit: Int,
        offset: Int,
        preferredColumnOrder: [String]?
    ) async -> QueryResult {
        result
    }

    func cancelCurrentQuery() {}
}
