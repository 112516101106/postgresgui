//
//  ConnectionService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftData

/// Service for managing database connections
/// Consolidates connection logic that was previously duplicated across ConnectionFormView,
/// ConnectionsListView, and ConnectionsDatabasesSidebar
@MainActor
class ConnectionService: ConnectionServiceProtocol {
    private let appState: AppState
    private let keychainService: KeychainServiceProtocol
    private let userDefaults: UserDefaultsProtocol

    /// Active SSH tunnel manager, kept alive for the duration of the connection
    private var sshTunnelManager: SSHTunnelManager?

    init(appState: AppState, keychainService: KeychainServiceProtocol, userDefaults: UserDefaultsProtocol? = nil) {
        self.appState = appState
        self.keychainService = keychainService
        self.userDefaults = userDefaults ?? UserDefaultsWrapper()
    }

    /// Connect to a database using a connection profile
    func connect(
        to connection: ConnectionProfile,
        password: String? = nil,
        saveAsLast: Bool = true
    ) async -> ConnectionResult {
        do {
            DebugLog.print("🔌 [ConnectionService] Connecting to: \(connection.displayName)")

            // Get password from keychain if not provided
            let actualPassword: String
            if let providedPassword = password {
                actualPassword = providedPassword
            } else {
                actualPassword = try keychainService.getPassword(for: connection.id) ?? ""
            }

            var connectHost = connection.host
            var connectPort = connection.port

            // Establish SSH tunnel if enabled
            if connection.sshEnabled {
                DebugLog.print("🔒 [ConnectionService] Setting up SSH tunnel")

                // Tear down any existing tunnel
                if let existingTunnel = sshTunnelManager {
                    await existingTunnel.teardown()
                }

                let sshPassword = connection.sshAuthMethodEnum == .password
                    ? try keychainService.getSSHPassword(for: connection.id) : nil
                let sshPassphrase = connection.sshAuthMethodEnum == .privateKey
                    ? try keychainService.getSSHPassphrase(for: connection.id) : nil
                let sshPrivateKey = connection.sshAuthMethodEnum == .privateKey
                    ? try keychainService.getSSHPrivateKey(for: connection.id) : nil

                let sshConfig = SSHTunnelConfig(
                    sshHost: connection.sshHost ?? "",
                    sshPort: connection.sshPort ?? 22,
                    sshUsername: connection.sshUsername ?? "",
                    authMethod: connection.sshAuthMethodEnum,
                    password: sshPassword,
                    privateKeyPath: connection.sshPrivateKeyPath,
                    privateKeyContent: sshPrivateKey,
                    passphrase: sshPassphrase,
                    remoteHost: connection.host,
                    remotePort: connection.port
                )

                let manager = SSHTunnelManager()
                let localPort = try await manager.establish(config: sshConfig)
                sshTunnelManager = manager

                connectHost = "127.0.0.1"
                connectPort = localPort

                DebugLog.print("🔒 [ConnectionService] SSH tunnel established on port \(localPort)")
            }

            // Connect to database (through tunnel if SSH enabled)
            try await appState.connection.databaseService.connect(
                host: connectHost,
                port: connectPort,
                username: connection.username,
                password: actualPassword,
                database: connection.database,
                sslMode: connection.sslModeEnum
            )

            // Update app state
            appState.connection.currentConnection = connection

            // Save last connection ID if requested
            if saveAsLast {
                userDefaults.set(
                    connection.id.uuidString,
                    forKey: Constants.UserDefaultsKeys.lastConnectionId
                )
            }

            // Load databases
            await loadDatabases()

            DebugLog.print("✅ [ConnectionService] Connection successful")
            return .success

        } catch {
            // Handle connectionCancelled specially - it's expected during rapid tab switching
            if case ConnectionError.connectionCancelled = error {
                DebugLog.print("📑 [ConnectionService] Connection cancelled (superseded by newer request)")
                // Don't reset connection state - a newer connection is taking over
                return .failure(error)
            }

            DebugLog.print("❌ [ConnectionService] Connection failed: \(error)")

            // Tear down SSH tunnel on failure
            if let tunnel = sshTunnelManager {
                await tunnel.teardown()
                sshTunnelManager = nil
            }

            // Reset connection state on error
            appState.connection.currentConnection = nil

            return .failure(error)
        }
    }

    /// Disconnect from the current database
    func disconnect() async {
        DebugLog.print("🔌 [ConnectionService] Disconnecting")
        await appState.connection.databaseService.disconnect()

        // Tear down SSH tunnel if active
        if let tunnel = sshTunnelManager {
            DebugLog.print("🔒 [ConnectionService] Tearing down SSH tunnel")
            await tunnel.teardown()
            sshTunnelManager = nil
        }

        appState.connection.currentConnection = nil
        appState.connection.databases = []
        appState.connection.databasesVersion += 1
        appState.connection.tables = []
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
    }

    /// Delete a connection profile and its associated keychain password
    func delete(connection: ConnectionProfile, from modelContext: ModelContext) async {
        DebugLog.print("🗑️ [ConnectionService] Deleting connection: \(connection.displayName)")

        // Delete all keychain entries (DB password + SSH credentials)
        // Use try? per call so one failure doesn't prevent the others
        try? keychainService.deletePassword(for: connection.id)
        try? keychainService.deleteSSHPassword(for: connection.id)
        try? keychainService.deleteSSHPassphrase(for: connection.id)
        try? keychainService.deleteSSHPrivateKey(for: connection.id)

        // If deleting the active connection, disconnect first
        if appState.connection.currentConnection?.id == connection.id {
            appState.connection.currentConnection = nil
            appState.connection.selectedDatabase = nil
            appState.connection.tables = []
            appState.connection.selectedTable = nil
            appState.connection.databases = []
            appState.connection.databasesVersion += 1
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
        }

        // Delete from SwiftData
        modelContext.delete(connection)
        try? modelContext.save()

        DebugLog.print("✅ [ConnectionService] Connection deleted")
    }

    // MARK: - Private Helpers

    private func loadDatabases() async {
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
        } catch {
            DebugLog.print("⚠️ [ConnectionService] Failed to load databases: \(error)")
            // Don't throw - connection succeeded, just database list failed
        }
    }
}
