//
//  KeychainServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftUI

/// Protocol for secure password storage
@MainActor
protocol KeychainServiceProtocol {
    /// Save password to secure storage
    func savePassword(_ password: String, for connectionId: UUID) throws

    /// Retrieve password from secure storage
    func getPassword(for connectionId: UUID) throws -> String?

    /// Delete password from secure storage
    func deletePassword(for connectionId: UUID) throws

    // MARK: - SSH Credentials

    /// Save SSH password to secure storage
    func saveSSHPassword(_ password: String, for connectionId: UUID) throws

    /// Retrieve SSH password from secure storage
    func getSSHPassword(for connectionId: UUID) throws -> String?

    /// Delete SSH password from secure storage
    func deleteSSHPassword(for connectionId: UUID) throws

    /// Save SSH private key passphrase to secure storage
    func saveSSHPassphrase(_ passphrase: String, for connectionId: UUID) throws

    /// Retrieve SSH private key passphrase from secure storage
    func getSSHPassphrase(for connectionId: UUID) throws -> String?

    /// Delete SSH private key passphrase from secure storage
    func deleteSSHPassphrase(for connectionId: UUID) throws
}

/// Implementation that delegates to existing KeychainService enum
@MainActor
class KeychainServiceImpl: KeychainServiceProtocol {
    func savePassword(_ password: String, for connectionId: UUID) throws {
        try KeychainService.savePassword(password, for: connectionId)
    }

    func getPassword(for connectionId: UUID) throws -> String? {
        try KeychainService.getPassword(for: connectionId)
    }

    func deletePassword(for connectionId: UUID) throws {
        try KeychainService.deletePassword(for: connectionId)
    }

    // MARK: - SSH Credentials

    func saveSSHPassword(_ password: String, for connectionId: UUID) throws {
        try KeychainService.saveSSHPassword(password, for: connectionId)
    }

    func getSSHPassword(for connectionId: UUID) throws -> String? {
        try KeychainService.getSSHPassword(for: connectionId)
    }

    func deleteSSHPassword(for connectionId: UUID) throws {
        try KeychainService.deleteSSHPassword(for: connectionId)
    }

    func saveSSHPassphrase(_ passphrase: String, for connectionId: UUID) throws {
        try KeychainService.saveSSHPassphrase(passphrase, for: connectionId)
    }

    func getSSHPassphrase(for connectionId: UUID) throws -> String? {
        try KeychainService.getSSHPassphrase(for: connectionId)
    }

    func deleteSSHPassphrase(for connectionId: UUID) throws {
        try KeychainService.deleteSSHPassphrase(for: connectionId)
    }
}

// MARK: - SwiftUI Environment

/// Environment key for KeychainServiceProtocol
private struct KeychainServiceKey: EnvironmentKey {
    @MainActor static let defaultValue: KeychainServiceProtocol = KeychainServiceImpl()
}

extension EnvironmentValues {
    var keychainService: KeychainServiceProtocol {
        get { self[KeychainServiceKey.self] }
        set { self[KeychainServiceKey.self] = newValue }
    }
}
