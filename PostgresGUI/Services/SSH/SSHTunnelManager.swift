//
//  SSHTunnelManager.swift
//  PostgresGUI
//
//  Actor managing SSH tunnel lifecycle.
//  Establishes an SSH connection and creates a local TCP listener that forwards
//  traffic through the SSH tunnel to the remote database server.
//

import Foundation
import Citadel
import NIOCore
import NIOPosix
import NIOSSH
import Logging

/// Type alias to avoid naming conflict with our app's SSHAuthMethod enum
private typealias CitadelAuthMethod = Citadel.SSHAuthenticationMethod

/// Actor-isolated manager for SSH tunnel connections
actor SSHTunnelManager: SSHTunnelManagerProtocol {

    // MARK: - Properties

    private var sshClient: SSHClient?
    private var serverChannel: Channel?
    private var localEventLoopGroup: MultiThreadedEventLoopGroup?
    private var assignedPort: Int?
    private let logger = Logger(label: "com.postgresgui.ssh-tunnel")

    var isActive: Bool {
        sshClient != nil && serverChannel != nil
    }

    // MARK: - Establish Tunnel

    func establish(config: SSHTunnelConfig) async throws -> Int {
        // Tear down any existing tunnel first
        await teardown()

        // Register RSA-SHA2-512 algorithm support
        RSASHA512Setup.registerIfNeeded()

        logger.info("Establishing SSH tunnel to \(config.sshHost):\(config.sshPort)")

        // 1. Build authentication method
        let authMethod = try buildAuthMethod(from: config)

        // 2. Connect SSH client
        do {
            sshClient = try await SSHClient.connect(
                host: config.sshHost,
                port: config.sshPort,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )
        } catch {
            logger.error("SSH connection failed: \(error)")
            throw mapSSHError(error, config: config)
        }

        guard let client = sshClient else {
            throw SSHTunnelError.authenticationFailed
        }

        logger.info("SSH connection established, setting up local port forwarding")

        // 3. Bind local TCP listener on ephemeral port
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        localEventLoopGroup = group

        let remoteHost = config.remoteHost
        let remotePort = config.remotePort

        do {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .serverChannelOption(ChannelOptions.backlog, value: 8)
                .childChannelInitializer { channel in
                    channel.pipeline.addHandler(
                        SSHPortForwardingHandler(
                            sshClient: client,
                            remoteHost: remoteHost,
                            remotePort: remotePort,
                            logger: Logger(label: "com.postgresgui.ssh-tunnel.forward")
                        )
                    )
                }

            let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            serverChannel = channel

            guard let localAddress = channel.localAddress, let port = localAddress.port else {
                throw SSHTunnelError.channelOpenFailed
            }

            assignedPort = port
            logger.info("SSH tunnel ready: 127.0.0.1:\(port) → \(remoteHost):\(remotePort)")

            return port
        } catch let error as SSHTunnelError {
            throw error
        } catch {
            logger.error("Failed to bind local listener: \(error)")
            await teardown()
            throw SSHTunnelError.channelOpenFailed
        }
    }

    // MARK: - Tear Down

    func teardown() async {
        if let channel = serverChannel {
            logger.info("Closing local listener")
            try? await channel.close()
            serverChannel = nil
        }

        if let client = sshClient {
            logger.info("Closing SSH connection")
            try? await client.close()
            sshClient = nil
        }

        if let group = localEventLoopGroup {
            try? await group.shutdownGracefully()
            localEventLoopGroup = nil
        }

        assignedPort = nil
        logger.info("SSH tunnel torn down")
    }

    // MARK: - Test Connection

    /// Test SSH tunnel establishment without maintaining the connection
    static func testTunnel(config: SSHTunnelConfig) async throws -> Bool {
        let manager = SSHTunnelManager()
        do {
            let _ = try await manager.establish(config: config)
            await manager.teardown()
            return true
        } catch {
            await manager.teardown()
            throw error
        }
    }

    // MARK: - Private Helpers

    private func buildAuthMethod(from config: SSHTunnelConfig) throws -> CitadelAuthMethod {
        switch config.authMethod {
        case .password:
            guard let password = config.password, !password.isEmpty else {
                throw SSHTunnelError.authenticationFailed
            }
            return .passwordBased(username: config.sshUsername, password: password)

        case .privateKey:
            let keyString: String

            if let content = config.privateKeyContent, !content.isEmpty {
                // Key content from Keychain — no file access needed
                keyString = content
            } else if let keyPath = config.privateKeyPath, !keyPath.isEmpty {
                // Fallback to file path (first-time use before save)
                let expandedPath = (keyPath as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expandedPath) else {
                    throw SSHTunnelError.privateKeyNotFound(keyPath)
                }
                keyString = try String(contentsOfFile: expandedPath, encoding: .utf8)
            } else {
                throw SSHTunnelError.privateKeyNotFound("")
            }

            let parsed = try SSHKeyParser.parsePrivateKey(
                keyString,
                username: config.sshUsername,
                passphrase: config.passphrase
            )

            switch parsed {
            case .citadel(let authMethod):
                return authMethod
            case .rsaSHA512(let delegate):
                return .custom(delegate)
            }
        }
    }

    private func mapSSHError(_ error: Error, config: SSHTunnelConfig) -> SSHTunnelError {
        let description = String(describing: error).lowercased()
        if description.contains("authentication") || description.contains("auth") {
            // RSA keys using SHA-1 signatures are rejected by modern OpenSSH servers (8.8+)
            if config.authMethod == .privateKey {
                return .authenticationFailed
            }
            return .authenticationFailed
        } else if description.contains("timeout") {
            return .timeout
        } else if description.contains("connect") || description.contains("refused") || description.contains("unreachable") {
            return .hostUnreachable(config.sshHost)
        }
        return .hostUnreachable("\(config.sshHost):\(config.sshPort) — \(error.localizedDescription)")
    }
}

// MARK: - SSH Port Forwarding Handler

/// NIO channel handler that bridges a local TCP connection to an SSH direct-tcpip channel
private final class SSHPortForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let sshClient: SSHClient
    private let remoteHost: String
    private let remotePort: Int
    private let logger: Logger
    private var sshChannel: Channel?

    init(sshClient: SSHClient, remoteHost: String, remotePort: Int, logger: Logger) {
        self.sshClient = sshClient
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.logger = logger
    }

    func channelActive(context: ChannelHandlerContext) {
        let localChannel = context.channel
        let remoteHost = self.remoteHost
        let remotePort = self.remotePort
        let logger = self.logger

        logger.debug("New local connection, opening SSH direct-tcpip to \(remoteHost):\(remotePort)")

        // Pause reads until the SSH channel relay is installed to prevent data loss
        context.channel.setOption(ChannelOptions.autoRead, value: false).whenFailure { error in
            logger.error("Failed to disable auto-read: \(error)")
        }

        Task {
            do {
                let originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                let sshChannel = try await sshClient.createDirectTCPIPChannel(
                    using: .init(
                        targetHost: remoteHost,
                        targetPort: remotePort,
                        originatorAddress: originatorAddress
                    )
                ) { channel in
                    channel.pipeline.addHandler(
                        SSHRelay(peerChannel: localChannel)
                    )
                }

                self.sshChannel = sshChannel

                // Add relay from local to SSH, then resume reads
                try await localChannel.pipeline.addHandler(
                    SSHRelay(peerChannel: sshChannel)
                ).get()

                // Re-enable reads now that the relay pipeline is wired up
                try await localChannel.setOption(ChannelOptions.autoRead, value: true).get()
                localChannel.read()

            } catch {
                logger.error("Failed to open SSH channel: \(error)")
                localChannel.close(promise: nil)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Data is forwarded by SSHRelay once installed
        context.fireChannelRead(data)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Port forwarding error: \(error)")
        context.close(promise: nil)
    }
}

// MARK: - SSH Relay Handler

/// Relays data between two NIO channels (local TCP <-> SSH channel)
private final class SSHRelay: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let peerChannel: Channel

    init(peerChannel: Channel) {
        self.peerChannel = peerChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        peerChannel.writeAndFlush(NIOAny(buffer), promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        peerChannel.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
        peerChannel.close(promise: nil)
    }
}
