//
//  SSHTunnelManagerProtocol.swift
//  PostgresGUI
//

import Foundation

/// Configuration for establishing an SSH tunnel
struct SSHTunnelConfig: Sendable {
    let sshHost: String
    let sshPort: Int
    let sshUsername: String
    let authMethod: SSHAuthMethod
    let password: String?
    let privateKeyPath: String?
    let passphrase: String?
    /// The database host as seen from the SSH server
    let remoteHost: String
    /// The database port as seen from the SSH server
    let remotePort: Int
}

/// Protocol for SSH tunnel management
/// Implemented by SSHTunnelManager for production and mocks for testing
protocol SSHTunnelManagerProtocol: Actor {
    /// Whether the tunnel is currently active
    var isActive: Bool { get }

    /// Establish an SSH tunnel and return the local port to connect through
    /// - Parameter config: SSH tunnel configuration
    /// - Returns: The local port number that forwards to the remote database
    func establish(config: SSHTunnelConfig) async throws -> Int

    /// Tear down the SSH tunnel and release all resources
    func teardown() async
}
