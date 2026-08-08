//
//  AutocompleteCatalogServiceProtocol.swift
//  PostgresGUI
//
//  Protocol abstraction for SQL autocomplete catalog loading.
//

import Foundation

protocol AutocompleteCatalogServiceProtocol: Actor {
    func fetchCatalogSnapshot(targetSchemas: Set<String>?) async throws -> AutocompleteCatalogSnapshot
}
