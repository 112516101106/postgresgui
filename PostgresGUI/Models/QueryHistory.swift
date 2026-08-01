//
//  QueryHistory.swift
//  PostgresGUI
//
//  Stores a record of executed queries.
//

import Foundation
import SwiftData

@Model
final class QueryHistory: Identifiable {
    var id: UUID
    var queryText: String
    var executionDate: Date
    var executionTime: TimeInterval
    var isSuccess: Bool
    var databaseName: String?
    var connectionId: UUID?

    init(
        id: UUID = UUID(),
        queryText: String,
        executionDate: Date = Date(),
        executionTime: TimeInterval,
        isSuccess: Bool,
        databaseName: String? = nil,
        connectionId: UUID? = nil
    ) {
        self.id = id
        self.queryText = queryText
        self.executionDate = executionDate
        self.executionTime = executionTime
        self.isSuccess = isSuccess
        self.databaseName = databaseName
        self.connectionId = connectionId
    }
}
