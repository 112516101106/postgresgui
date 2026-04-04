//
//  ConnectionProfile.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import SwiftData

@Model
final class ConnectionProfile: Identifiable {
    var id: UUID
    var name: String?
    var host: String
    var port: Int
    var username: String
    var database: String
    var isFavorite: Bool
    var sslMode: String
    var password: String?

    // SSH Tunnel fields
    var sshEnabled: Bool
    var sshHost: String?
    var sshPort: Int?
    var sshUsername: String?
    var sshAuthMethod: String?
    var sshPrivateKeyPath: String?

    init(
        id: UUID = UUID(),
        name: String?,
        host: String,
        port: Int = Constants.PostgreSQL.defaultPort,
        username: String,
        database: String = Constants.PostgreSQL.defaultDatabase,
        isFavorite: Bool = false,
        sslMode: SSLMode = .default,
        password: String? = nil,
        sshEnabled: Bool = false,
        sshHost: String? = nil,
        sshPort: Int? = nil,
        sshUsername: String? = nil,
        sshAuthMethod: SSHAuthMethod? = nil,
        sshPrivateKeyPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.isFavorite = isFavorite
        self.sslMode = sslMode.rawValue
        self.password = password
        self.sshEnabled = sshEnabled
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshAuthMethod = sshAuthMethod?.rawValue
        self.sshPrivateKeyPath = sshPrivateKeyPath
    }
}

extension ConnectionProfile {
    /// Get the SSL mode as an enum
    var sslModeEnum: SSLMode {
        SSLMode(rawValue: sslMode) ?? .default
    }

    /// Get the SSH auth method as an enum
    var sshAuthMethodEnum: SSHAuthMethod {
        sshAuthMethod.flatMap { SSHAuthMethod(rawValue: $0) } ?? .password
    }

    /// Extract the root domain from the host
    /// Returns the root domain (e.g., "symcloud.net" from "postgresguitest.idb-node-01.symcloud.net")
    /// For localhost or IP addresses, returns the host as-is
    var rootDomain: String {
        // If it's localhost, return as-is
        if host.lowercased() == "localhost" {
            return host
        }
        
        // Check if it's an IP address (contains only digits and dots)
        let ipAddressPattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
        if host.range(of: ipAddressPattern, options: .regularExpression) != nil {
            return host
        }
        
        // Extract root domain (last two parts: domain.tld)
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            // Return the last two parts (e.g., "symcloud.net")
            return "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
        }
        
        // If we can't determine root domain, return host as-is
        return host
    }
    
    /// Returns a display name for the connection, with fallback if name is nil
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        return host
    }
}
