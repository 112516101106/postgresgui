//
//  AutocompleteCatalogServiceTests.swift
//  PostgresGUITests
//
//  Unit tests for autocomplete catalog schema resolution.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("AutocompleteCatalogService")
@MainActor
struct AutocompleteCatalogServiceTests {
    @Test
    func resolvedSchemas_defaultsToAllAvailableUserSchemas() {
        let resolvedSchemas = AutocompleteCatalogService.resolvedSchemas(
            for: nil,
            searchPathSchemas: ["public"],
            availableSchemas: ["audit", "auth", "billing", "public"]
        )

        #expect(resolvedSchemas == ["public", "audit", "auth", "billing"])
    }

    @Test
    func resolvedSchemas_keepsExplicitTargetsOnly() {
        let resolvedSchemas = AutocompleteCatalogService.resolvedSchemas(
            for: ["crawler", "quiz"],
            searchPathSchemas: ["public"],
            availableSchemas: ["audit", "auth", "billing", "crawler", "public", "quiz"]
        )

        #expect(resolvedSchemas == ["crawler", "quiz"])
    }
}
