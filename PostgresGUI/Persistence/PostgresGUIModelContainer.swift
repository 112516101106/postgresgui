//
//  PostgresGUIModelContainer.swift
//  PostgresGUI
//
//  Centralizes SwiftData schema setup and migration.
//

import Foundation
import SwiftData

enum PostgresGUISchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
        ]
    }
}

enum PostgresGUISchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            ConnectionProfile.self,
            SavedQuery.self,
            QueryFolder.self,
            TabState.self,
            QueryHistory.self,
        ]
    }
}

enum PostgresGUIMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            PostgresGUISchemaV1.self,
            PostgresGUISchemaV2.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PostgresGUISchemaV1.self, toVersion: PostgresGUISchemaV2.self),
        ]
    }
}

enum PostgresGUIModelContainerFactory {
    static var currentSchema: Schema {
        Schema(versionedSchema: PostgresGUISchemaV2.self)
    }

    static func makeModelContainer(
        isStoredInMemoryOnly: Bool = false,
        url: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("default", schema: currentSchema, url: url)
        } else {
            configuration = ModelConfiguration(
                "default",
                schema: currentSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }

        return try ModelContainer(
            for: currentSchema,
            migrationPlan: PostgresGUIMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
