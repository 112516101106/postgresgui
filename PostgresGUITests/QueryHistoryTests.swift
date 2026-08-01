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
        let schema = Schema([QueryHistory.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
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
}
