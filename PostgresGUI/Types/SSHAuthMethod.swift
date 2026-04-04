//
//  SSHAuthMethod.swift
//  PostgresGUI
//

import Foundation

/// Authentication method for SSH tunnel connections
enum SSHAuthMethod: String, Sendable, CaseIterable {
    case password = "password"
    case privateKey = "privateKey"

    nonisolated var displayName: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "Private Key"
        }
    }
}
