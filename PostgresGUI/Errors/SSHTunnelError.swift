//
//  SSHTunnelError.swift
//  PostgresGUI
//

import Foundation

/// Errors related to SSH tunnel establishment and lifecycle
enum SSHTunnelError: LocalizedError {
    case authenticationFailed
    case hostUnreachable(String)
    case channelOpenFailed
    case privateKeyNotFound(String)
    case privateKeyInvalid(String)
    case passphraseRequired
    case tunnelClosed
    case timeout

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "SSH authentication failed"
        case .hostUnreachable(let host):
            return "SSH host unreachable: \(host)"
        case .channelOpenFailed:
            return "Failed to open SSH tunnel channel"
        case .privateKeyNotFound(let path):
            return "Private key not found at: \(path)"
        case .privateKeyInvalid(let reason):
            return "Invalid private key: \(reason)"
        case .passphraseRequired:
            return "Private key is encrypted — passphrase required"
        case .tunnelClosed:
            return "SSH tunnel was closed unexpectedly"
        case .timeout:
            return "SSH connection timed out"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            return "Check your SSH username and password or private key."
        case .hostUnreachable:
            return "Verify the SSH host and port are correct and the server is running."
        case .channelOpenFailed:
            return "The SSH server may not allow port forwarding. Check server configuration."
        case .privateKeyNotFound:
            return "Select a valid private key file."
        case .privateKeyInvalid:
            return "The private key file format is not supported. Use OpenSSH or PEM format."
        case .passphraseRequired:
            return "Enter the passphrase for the encrypted private key."
        case .tunnelClosed:
            return "The SSH connection was lost. Try reconnecting."
        case .timeout:
            return "The SSH server did not respond in time. Check your network connection."
        }
    }
}
