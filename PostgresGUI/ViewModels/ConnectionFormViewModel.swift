//
//  ConnectionFormViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftUI
import SwiftData
import AppKit

/// Input mode for connection form
enum ConnectionInputMode {
    case individual
    case connectionString
}

/// ViewModel for ConnectionFormView - handles all business logic and state
@Observable
@MainActor
class ConnectionFormViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let keychainService: KeychainServiceProtocol
    let connectionToEdit: ConnectionProfile?

    // MARK: - Form State - Individual Fields

    var individualName: String = ""
    var host: String = "localhost"
    var port: String = "5432"
    var username: String = "postgres"
    var password: String = ""
    var database: String = "postgres"
    var showPassword: Bool = false
    var showIndividualNameField: Bool = false

    // MARK: - Form State - Connection String

    var connectionString: String = ""
    var connectionStringName: String = ""
    var showConnectionStringNameField: Bool = false
    var copyButtonLabel: String = "Copy"

    // MARK: - SSL Mode State

    var sslModeSelection: SSLMode = .default
    private var isSSLModeUserSelected: Bool = false

    // MARK: - Input Mode

    var inputMode: ConnectionInputMode = .individual

    // MARK: - Connection Test State

    var isConnecting: Bool = false
    var connectionTestStatus: ConnectionTestStatus = .idle

    // MARK: - Password Management

    var hasStoredPassword: Bool = false
    var actualStoredPassword: String = ""
    var passwordModified: Bool = false

    // MARK: - SSH Tunnel State

    var sshEnabled: Bool = false
    var sshHost: String = ""
    var sshPort: String = "22"
    var sshUsername: String = ""
    var sshAuthMethod: SSHAuthMethod = .password
    var sshPassword: String = ""
    var showSSHPassword: Bool = false
    var sshPrivateKeyPath: String = ""
    var sshPrivateKeyContent: String = ""
    var sshPassphrase: String = ""
    var showSSHPassphrase: Bool = false

    // SSH password management (mirrors DB password pattern)
    var hasStoredSSHPassword: Bool = false
    var actualStoredSSHPassword: String = ""
    var sshPasswordModified: Bool = false
    var hasStoredSSHPassphrase: Bool = false
    var actualStoredSSHPassphrase: String = ""
    var sshPassphraseModified: Bool = false

    // MARK: - Alert State

    var showKeychainAlert: Bool = false
    var keychainAlertMessage: String = ""

    // Connection saved alert state
    var showConnectionSavedAlert: Bool = false
    var savedConnectionProfile: ConnectionProfile?
    private var savedConnectionPassword: String = ""

    // MARK: - Computed Properties

    var isEditing: Bool {
        connectionToEdit != nil
    }

    var currentName: String? {
        if inputMode == .individual {
            return showIndividualNameField && !individualName.isEmpty ? individualName : nil
        } else {
            return showConnectionStringNameField && !connectionStringName.isEmpty ? connectionStringName : nil
        }
    }

    var navigationTitle: String {
        isEditing ? "Edit Connection" : "Create New Connection"
    }

    var toggleLabel: String {
        isEditing ? "View Connection String" : "Use Connection String"
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        keychainService: KeychainServiceProtocol? = nil,
        connectionToEdit: ConnectionProfile? = nil
    ) {
        self.appState = appState
        self.keychainService = keychainService ?? KeychainServiceImpl()
        self.connectionToEdit = connectionToEdit
    }

    /// Load connection data when editing
    func loadConnectionIfNeeded() {
        guard let connection = connectionToEdit else { return }

        // Populate both name fields with the same value initially
        individualName = connection.name ?? ""
        connectionStringName = connection.name ?? ""
        host = connection.host
        port = String(connection.port)
        username = connection.username
        database = connection.database

        // Password handling - don't access keychain on form load
        hasStoredPassword = true
        actualStoredPassword = ""
        passwordModified = false
        password = String(repeating: "•", count: 8)

        // Show name fields when editing only if name is not nil
        showIndividualNameField = connection.name != nil
        showConnectionStringNameField = connection.name != nil

        // SSH tunnel fields
        sshEnabled = connection.sshEnabled
        sshHost = connection.sshHost ?? ""
        sshPort = connection.sshPort.map { String($0) } ?? "22"
        sshUsername = connection.sshUsername ?? ""
        sshAuthMethod = connection.sshAuthMethodEnum
        sshPrivateKeyPath = connection.sshPrivateKeyPath ?? ""

        // SSH password/passphrase — lazy load from Keychain (same pattern as DB password)
        if sshEnabled {
            if sshAuthMethod == .password {
                hasStoredSSHPassword = true
                actualStoredSSHPassword = ""
                sshPasswordModified = false
                sshPassword = String(repeating: "\u{2022}", count: 8)
            } else {
                hasStoredSSHPassphrase = true
                actualStoredSSHPassphrase = ""
                sshPassphraseModified = false
                sshPassphrase = String(repeating: "\u{2022}", count: 8)
            }
        }

        // If in connection string mode, populate the connection string
        if inputMode == .connectionString {
            connectionString = generateConnectionString()
        }

    }

    // MARK: - Input Mode Handling

    func handleInputModeChange(to newMode: ConnectionInputMode) {
        connectionTestStatus = .idle

        // If switching to connection string mode in edit mode, populate the connection string
        if newMode == .connectionString, isEditing {
            connectionString = generateConnectionString()
        }

        inputMode = newMode

        if newMode == .individual {
            updateSSLModeForHostIfNeeded(host)
        }
    }

    // MARK: - Password Handling

    /// Load password from keychain when user clicks "Show Password"
    func loadPasswordFromKeychain() -> Bool {
        guard let connection = connectionToEdit else { return true }

        do {
            if let keychainPassword = try keychainService.getPassword(for: connection.id) {
                actualStoredPassword = keychainPassword
                return true
            } else {
                actualStoredPassword = ""
                return true
            }
        } catch {
            connectionTestStatus = .error(
                message: "Unable to retrieve password from keychain. You may need to grant access in System Settings > Privacy & Security."
            )
            return false
        }
    }

    /// Get the actual password value for connection
    func getActualPassword() -> String {
        if let connection = connectionToEdit {
            if hasStoredPassword && !passwordModified {
                return (try? keychainService.getPassword(for: connection.id)) ?? ""
            }
        }
        return password
    }

    /// Handle password field change
    func handlePasswordChange(_ newValue: String) {
        password = newValue
        if hasStoredPassword && !passwordModified {
            passwordModified = true
        }
    }

    // MARK: - Connection String Handling

    func generateConnectionString() -> String {
        guard let connection = connectionToEdit else { return "" }

        let passwordPlaceholder = hasStoredPassword ? "YOUR_PASSWORD" : nil

        return ConnectionStringParser.build(
            username: connection.username,
            password: passwordPlaceholder,
            host: connection.host,
            port: connection.port,
            database: connection.database,
            sslMode: connection.sslModeEnum
        )
    }

    func copyConnectionStringToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connectionString, forType: .string)

        copyButtonLabel = "Copied!"
        Task {
            try? await Task.sleep(nanoseconds: 1.5.nanoseconds)
            copyButtonLabel = "Copy"
        }
    }

    // MARK: - Connection Testing

    func testConnection() async {
        isConnecting = true

        let testStartTime = Date()
        connectionTestStatus = .testing

        DebugLog.print("🧪 [ConnectionFormViewModel] ========== Starting Connection Test ==========")
        DebugLog.print("   Mode: \(inputMode == .connectionString ? "Connection String" : "Individual Fields")")

        var tunnelManager: SSHTunnelManager?
        do {
            let details = try parseConnectionDetails()

            DebugLog.print("   Final connection parameters:")
            DebugLog.print("     Host: \(details.host)")
            DebugLog.print("     Port: \(details.port)")
            DebugLog.print("     Username: \(details.username)")
            DebugLog.print("     Database: \(details.database)")
            DebugLog.print("     SSL Mode: \(details.sslMode.rawValue)")
            DebugLog.print("     SSH Tunnel: \(details.sshConfig != nil ? "enabled" : "disabled")")

            var testHost = details.host
            var testPort = details.port

            // If SSH tunnel is configured, establish it first
            if let sshConfig = details.sshConfig {
                connectionTestStatus = .testingSSH
                DebugLog.print("   🔒 Establishing SSH tunnel to \(sshConfig.sshHost):\(sshConfig.sshPort)")

                let manager = SSHTunnelManager()
                tunnelManager = manager
                do {
                    let localPort = try await manager.establish(config: sshConfig)
                    testHost = "127.0.0.1"
                    testPort = localPort
                    DebugLog.print("   🔒 SSH tunnel established on port \(localPort)")
                    connectionTestStatus = .testing
                } catch {
                    await manager.teardown()
                    let message = "SSH tunnel failed: \(error.localizedDescription)"
                    await handleTestError(message, startTime: testStartTime)
                    isConnecting = false
                    return
                }
            }

            let success = try await DatabaseService.testConnection(
                host: testHost,
                port: testPort,
                username: details.username,
                password: details.password,
                database: details.database,
                sslMode: details.sslMode
            )

            // Tear down test tunnel
            if let manager = tunnelManager {
                await manager.teardown()
            }

            // Ensure testing state is visible for at least 150ms
            let elapsed = Date().timeIntervalSince(testStartTime)
            if elapsed < 0.15 {
                try? await Task.sleep(nanoseconds: (0.15 - elapsed).nanoseconds)
            }

            if success {
                DebugLog.print("   ✅ Connection test successful!")
                connectionTestStatus = .success
            } else {
                DebugLog.print("   ❌ Connection test failed (returned false)")
                let prefix = details.sshConfig != nil ? "SSH tunnel established, but database connection failed: " : ""
                connectionTestStatus = .error(message: "\(prefix)Could not connect to \(details.host):\(details.port)")
            }
        } catch let error as ConnectionFormError {
            if let manager = tunnelManager { await manager.teardown() }
            await handleTestError(error.message, startTime: testStartTime)
        } catch {
            if let manager = tunnelManager { await manager.teardown() }
            let message = PostgresError.extractDetailedMessage(error)
            await handleTestError(message, startTime: testStartTime)
        }

        isConnecting = false
    }

    private func handleTestError(_ message: String, startTime: Date) async {
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 0.15 {
            try? await Task.sleep(nanoseconds: (0.15 - elapsed).nanoseconds)
        }
        connectionTestStatus = .error(message: message)
        DebugLog.print("   ❌ \(message)")
    }

    // MARK: - Save Connection

    func saveConnection(modelContext: ModelContext) async -> Bool {
        isConnecting = true

        do {
            let details = try parseConnectionDetails()

            let profile: ConnectionProfile

            if let existingConnection = connectionToEdit {
                // Update existing connection
                profile = existingConnection

                // Check if connection-critical parameters changed (requires reconnect)
                let connectionParamsChanged = profile.host != details.host ||
                    profile.port != details.port ||
                    profile.username != details.username ||
                    profile.database != details.database ||
                    profile.sslMode != details.sslMode.rawValue ||
                    passwordModified ||
                    profile.sshEnabled != sshEnabled

                profile.name = currentName
                profile.host = details.host
                profile.port = details.port
                profile.username = details.username
                profile.database = details.database
                profile.sslMode = details.sslMode.rawValue

                // Update SSH tunnel fields
                profile.sshEnabled = sshEnabled
                profile.sshHost = sshEnabled ? sshHost : nil
                profile.sshPort = sshEnabled ? (Int(sshPort) ?? 22) : nil
                profile.sshUsername = sshEnabled ? sshUsername : nil
                profile.sshAuthMethod = sshEnabled ? sshAuthMethod.rawValue : nil
                profile.sshPrivateKeyPath = (sshEnabled && sshAuthMethod == .privateKey) ? sshPrivateKeyPath : nil

                // Update password if modified
                if passwordModified {
                    if !password.isEmpty {
                        try keychainService.savePassword(password, for: profile.id)
                    } else {
                        try? keychainService.deletePassword(for: profile.id)
                    }
                }

                // Update SSH credentials
                try saveSSHCredentials(for: profile.id)

                // Save changes to SwiftData
                try modelContext.save()

                // Only disconnect if connection-critical parameters changed
                // (name-only changes don't require reconnection)
                if connectionParamsChanged && appState.connection.currentConnection?.id == profile.id {
                    await appState.connection.databaseService.disconnect()
                    appState.connection.currentConnection = nil
                    appState.connection.selectedDatabase = nil
                    appState.connection.selectedTable = nil
                    appState.connection.tables = []
                    appState.connection.databases = []
                    appState.connection.databasesVersion += 1
                }
            } else {
                // Create new connection
                profile = ConnectionProfile(
                    name: currentName,
                    host: details.host,
                    port: details.port,
                    username: details.username,
                    database: details.database,
                    sslMode: details.sslMode,
                    password: nil,
                    sshEnabled: sshEnabled,
                    sshHost: sshEnabled ? sshHost : nil,
                    sshPort: sshEnabled ? (Int(sshPort) ?? 22) : nil,
                    sshUsername: sshEnabled ? sshUsername : nil,
                    sshAuthMethod: sshEnabled ? sshAuthMethod : nil,
                    sshPrivateKeyPath: (sshEnabled && sshAuthMethod == .privateKey) ? sshPrivateKeyPath : nil
                )

                // Save password to keychain
                if !details.password.isEmpty {
                    try keychainService.savePassword(details.password, for: profile.id)
                }

                // Save SSH credentials
                try saveSSHCredentials(for: profile.id)

                modelContext.insert(profile)
                try modelContext.save()

                // Auto-connect if first connection, otherwise show alert
                let descriptor = FetchDescriptor<ConnectionProfile>()
                let allConnections = try modelContext.fetch(descriptor)

                if allConnections.count == 1 {
                    await autoConnect(to: profile, password: details.password)
                } else {
                    // Show connection saved alert with Connect/Dismiss options
                    savedConnectionProfile = profile
                    savedConnectionPassword = details.password
                    showConnectionSavedAlert = true
                    return false  // Don't dismiss yet - wait for alert response
                }
            }

            DebugLog.print("✅ [ConnectionFormViewModel] Connection profile saved successfully")
            isConnecting = false
            return true

        } catch let error as ConnectionFormError {
            keychainAlertMessage = error.message
            showKeychainAlert = true
            isConnecting = false
            return false
        } catch {
            DebugLog.print("❌ [ConnectionFormViewModel] Save error: \(error)")
            keychainAlertMessage = error.localizedDescription
            showKeychainAlert = true
            isConnecting = false
            return false
        }
    }

    private func autoConnect(to connection: ConnectionProfile, password: String) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(
            to: connection,
            password: password,
            saveAsLast: true
        )

        switch result {
        case .success:
            DebugLog.print("✅ [ConnectionFormViewModel] Auto-connect successful")
        case .failure(let error):
            DebugLog.print("❌ [ConnectionFormViewModel] Auto-connect failed: \(error)")
        }
    }

    /// Called when user chooses to connect from the "Connection Saved" alert
    func connectToSavedConnection() async {
        guard let profile = savedConnectionProfile else { return }
        await autoConnect(to: profile, password: savedConnectionPassword)
        clearSavedConnectionState()
    }

    /// Called when user chooses "Not Now" from the "Connection Saved" alert
    func dismissSavedConnectionAlert() {
        clearSavedConnectionState()
    }

    private func clearSavedConnectionState() {
        savedConnectionProfile = nil
        savedConnectionPassword = ""
        showConnectionSavedAlert = false
    }

    // MARK: - Private Helpers

    private struct ConnectionDetails {
        let host: String
        let port: Int
        let username: String
        let password: String
        let database: String
        let sslMode: SSLMode
        let sshConfig: SSHTunnelConfig?
    }

    private func parseConnectionDetails() throws -> ConnectionDetails {
        if inputMode == .connectionString {
            return try parseConnectionString()
        } else {
            return try parseIndividualFields()
        }
    }

    private func parseConnectionString() throws -> ConnectionDetails {
        let parsed = try ConnectionStringParser.parse(connectionString)

        var parsedPassword = parsed.password ?? ""

        // Replace YOUR_PASSWORD placeholder with keychain password
        if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
            if let keychainPassword = try? keychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                parsedPassword = keychainPassword
            }
        }

        return ConnectionDetails(
            host: parsed.host,
            port: parsed.port,
            username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
            password: parsedPassword,
            database: parsed.database ?? Constants.PostgreSQL.defaultDatabase,
            sslMode: parsed.sslMode,
            sshConfig: buildSSHConfig(
                dbHost: parsed.host,
                dbPort: parsed.port
            )
        )
    }

    private func parseIndividualFields() throws -> ConnectionDetails {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDatabase = database.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let portInt = Int(trimmedPort), portInt > 0 && portInt <= 65535 else {
            throw ConnectionFormError(message: "Invalid port number")
        }

        let passwordToUse: String
        if let connection = connectionToEdit {
            if let keychainPassword = try? keychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                passwordToUse = passwordModified ? password : keychainPassword
            } else {
                passwordToUse = password
            }
        } else {
            passwordToUse = password
        }

        let finalHost = trimmedHost.isEmpty ? "localhost" : trimmedHost

        return ConnectionDetails(
            host: finalHost,
            port: portInt,
            username: trimmedUsername.isEmpty ? "postgres" : trimmedUsername,
            password: passwordToUse,
            database: trimmedDatabase.isEmpty ? "postgres" : trimmedDatabase,
            sslMode: sslModeSelection,
            sshConfig: buildSSHConfig(dbHost: finalHost, dbPort: portInt)
        )
    }

    // MARK: - SSH Tunnel Helpers

    /// Build SSH tunnel config from current form state, or nil if SSH is disabled
    private func buildSSHConfig(dbHost: String, dbPort: Int) -> SSHTunnelConfig? {
        guard sshEnabled else { return nil }

        let sshPasswordToUse: String?
        let sshPassphraseToUse: String?

        if sshAuthMethod == .password {
            if let connection = connectionToEdit, hasStoredSSHPassword, !sshPasswordModified {
                sshPasswordToUse = (try? keychainService.getSSHPassword(for: connection.id)) ?? ""
            } else {
                sshPasswordToUse = sshPassword
            }
            sshPassphraseToUse = nil
        } else {
            sshPasswordToUse = nil
            if let connection = connectionToEdit, hasStoredSSHPassphrase, !sshPassphraseModified {
                sshPassphraseToUse = (try? keychainService.getSSHPassphrase(for: connection.id)) ?? ""
            } else {
                sshPassphraseToUse = sshPassphrase.isEmpty ? nil : sshPassphrase
            }
        }

        // Get private key content: from form state (just browsed) or from Keychain (editing)
        let privateKeyContentToUse: String?
        if sshAuthMethod == .privateKey {
            if !sshPrivateKeyContent.isEmpty {
                privateKeyContentToUse = sshPrivateKeyContent
            } else if let connection = connectionToEdit {
                privateKeyContentToUse = try? keychainService.getSSHPrivateKey(for: connection.id)
            } else {
                privateKeyContentToUse = nil
            }
        } else {
            privateKeyContentToUse = nil
        }

        return SSHTunnelConfig(
            sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
            sshPort: Int(sshPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22,
            sshUsername: sshUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: sshAuthMethod,
            password: sshPasswordToUse,
            privateKeyPath: sshAuthMethod == .privateKey ? sshPrivateKeyPath : nil,
            privateKeyContent: privateKeyContentToUse,
            passphrase: sshPassphraseToUse,
            remoteHost: dbHost,
            remotePort: dbPort
        )
    }

    /// Open file picker for SSH private key
    func browseForPrivateKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.message = "Select SSH Private Key"
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    self?.sshPrivateKeyPath = url.path
                    // Read file contents now while sandbox access is active
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        self?.sshPrivateKeyContent = content
                    }
                }
            }
        }
    }

    /// Handle SSH password field change
    func handleSSHPasswordChange(_ newValue: String) {
        sshPassword = newValue
        if hasStoredSSHPassword && !sshPasswordModified {
            sshPasswordModified = true
        }
    }

    /// Handle SSH passphrase field change
    func handleSSHPassphraseChange(_ newValue: String) {
        sshPassphrase = newValue
        if hasStoredSSHPassphrase && !sshPassphraseModified {
            sshPassphraseModified = true
        }
    }

    /// Load SSH password from keychain when user clicks "Show"
    func loadSSHPasswordFromKeychain() -> Bool {
        guard let connection = connectionToEdit else { return true }
        do {
            if let stored = try keychainService.getSSHPassword(for: connection.id) {
                actualStoredSSHPassword = stored
            }
            return true
        } catch {
            connectionTestStatus = .error(
                message: "Unable to retrieve SSH password from keychain."
            )
            return false
        }
    }

    /// Load SSH passphrase from keychain when user clicks "Show"
    func loadSSHPassphraseFromKeychain() -> Bool {
        guard let connection = connectionToEdit else { return true }
        do {
            if let stored = try keychainService.getSSHPassphrase(for: connection.id) {
                actualStoredSSHPassphrase = stored
            }
            return true
        } catch {
            connectionTestStatus = .error(
                message: "Unable to retrieve SSH passphrase from keychain."
            )
            return false
        }
    }

    // MARK: - SSL Mode Handling

    func handleHostChange(_ newHost: String) {
        updateSSLModeForHostIfNeeded(newHost)
    }

    func setSSLModeSelection(_ newMode: SSLMode) {
        sslModeSelection = newMode
        isSSLModeUserSelected = true
    }

    func initializeSSLModeIfNeeded() {
        if let connection = connectionToEdit {
            sslModeSelection = connection.sslModeEnum
            isSSLModeUserSelected = true
        } else {
            sslModeSelection = SSLMode.defaultFor(host: host)
            isSSLModeUserSelected = false
        }
    }

    private func updateSSLModeForHostIfNeeded(_ newHost: String) {
        guard !isSSLModeUserSelected else { return }
        let trimmedHost = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        sslModeSelection = SSLMode.defaultFor(host: trimmedHost)
    }

    // MARK: - SSH Credential Persistence

    private func saveSSHCredentials(for connectionId: UUID) throws {
        if sshEnabled {
            if sshAuthMethod == .password {
                if !isEditing || sshPasswordModified {
                    if !sshPassword.isEmpty {
                        try keychainService.saveSSHPassword(sshPassword, for: connectionId)
                    } else {
                        try? keychainService.deleteSSHPassword(for: connectionId)
                    }
                }
                // Clean up passphrase if switching from privateKey to password
                try? keychainService.deleteSSHPassphrase(for: connectionId)
            } else {
                if !isEditing || sshPassphraseModified {
                    if !sshPassphrase.isEmpty {
                        try keychainService.saveSSHPassphrase(sshPassphrase, for: connectionId)
                    } else {
                        try? keychainService.deleteSSHPassphrase(for: connectionId)
                    }
                }
                // Save private key content to Keychain
                if !sshPrivateKeyContent.isEmpty {
                    try keychainService.saveSSHPrivateKey(sshPrivateKeyContent, for: connectionId)
                }
                // Clean up password if switching from password to privateKey
                try? keychainService.deleteSSHPassword(for: connectionId)
            }
        } else {
            // SSH disabled — clean up any SSH credentials
            try? keychainService.deleteSSHPassword(for: connectionId)
            try? keychainService.deleteSSHPassphrase(for: connectionId)
            try? keychainService.deleteSSHPrivateKey(for: connectionId)
        }
    }
}

// MARK: - Error Type

private struct ConnectionFormError: Error {
    let message: String
}
