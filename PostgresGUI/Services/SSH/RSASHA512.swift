//
//  RSASHA512.swift
//  PostgresGUI
//
//  RSA-SHA2-512 key types for modern SSH servers (OpenSSH 8.8+).
//
//  OpenSSH 8.8 disabled ssh-rsa (SHA-1) signatures by default.
//  This file provides rsa-sha2-512 signing using Apple's Security framework,
//  conforming to NIOSSH's custom key protocols so Citadel can use them.
//
//  Reference: RFC 8332 — Use of RSA Keys with SHA-256 and SHA-512 in SSH
//

import Foundation
import Security
import NIOCore
import NIOSSH
import Citadel

// MARK: - SSH Wire Format Helpers

private nonisolated enum SSHWireFormat {
    /// Write a length-prefixed byte string (uint32 length + bytes)
    @discardableResult
    static func writeString(_ data: Data, to buffer: inout ByteBuffer) -> Int {
        let written = buffer.writeInteger(UInt32(data.count))
        return written + buffer.writeBytes(data)
    }

    /// Read a length-prefixed byte string
    static func readString(from buffer: inout ByteBuffer) -> Data? {
        guard let length = buffer.readInteger(as: UInt32.self) else { return nil }
        guard let bytes = buffer.readBytes(length: Int(length)) else { return nil }
        return Data(bytes)
    }
}

// MARK: - RSA-SHA2-512 Signature

nonisolated struct RSASHA512Signature: NIOSSHSignatureProtocol, ContiguousBytes {
    static let signaturePrefix = "rsa-sha2-512"

    let rawRepresentation: Data

    init(rawRepresentation: Data) {
        self.rawRepresentation = rawRepresentation
    }

    init<D: DataProtocol>(rawRepresentation: D) {
        self.rawRepresentation = Data(rawRepresentation)
    }

    func write(to buffer: inout ByteBuffer) -> Int {
        SSHWireFormat.writeString(rawRepresentation, to: &buffer)
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSASHA512Signature {
        guard let data = SSHWireFormat.readString(from: &buffer) else {
            throw SSHTunnelError.privateKeyInvalid("Invalid rsa-sha2-512 signature format")
        }
        return RSASHA512Signature(rawRepresentation: data)
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try rawRepresentation.withUnsafeBytes(body)
    }
}

// MARK: - RSA-SHA2-512 Public Key

nonisolated final class RSASHA512PublicKey: NIOSSHPublicKeyProtocol {
    static let publicKeyPrefix = "rsa-sha2-512"

    private let secKey: SecKey
    /// Raw public key components for SSH wire format
    private let eBytes: Data
    private let nBytes: Data

    var rawRepresentation: Data {
        var buffer = ByteBuffer()
        SSHWireFormat.writeString(eBytes, to: &buffer)
        SSHWireFormat.writeString(nBytes, to: &buffer)
        return Data(buffer.readableBytesView)
    }

    init(secKey: SecKey, eBytes: Data, nBytes: Data) {
        self.secKey = secKey
        self.eBytes = eBytes
        self.nBytes = nBytes
    }

    func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        guard let sig = signature as? RSASHA512Signature else { return false }
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA512,
            Data(data) as CFData,
            sig.rawRepresentation as CFData,
            &error
        )
    }

    func write(to buffer: inout ByteBuffer) -> Int {
        var written = 0
        written += SSHWireFormat.writeString(eBytes, to: &buffer)
        written += SSHWireFormat.writeString(nBytes, to: &buffer)
        return written
    }

    static func read(from buffer: inout ByteBuffer) throws -> RSASHA512PublicKey {
        throw SSHTunnelError.privateKeyInvalid("RSASHA512PublicKey.read not supported")
    }
}

// MARK: - RSA-SHA2-512 Private Key

nonisolated final class RSASHA512PrivateKey: NIOSSHPrivateKeyProtocol {
    static let keyPrefix = "rsa-sha2-512"

    private let secKey: SecKey
    private let _publicKey: RSASHA512PublicKey

    var publicKey: NIOSSHPublicKeyProtocol { _publicKey }

    init(secKey: SecKey, publicKey: RSASHA512PublicKey) {
        self.secKey = secKey
        self._publicKey = publicKey
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA512,
            Data(data) as CFData,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                throw SSHTunnelError.privateKeyInvalid("RSA-SHA2-512 signing failed: \(err)")
            }
            throw SSHTunnelError.privateKeyInvalid("RSA-SHA2-512 signing failed")
        }
        return RSASHA512Signature(rawRepresentation: sig as Data)
    }

    // MARK: - Factory

    /// Create from PKCS#1 DER data (the raw bytes inside a PEM RSA key)
    static func fromPKCS1DER(_ derData: Data) throws -> RSASHA512PrivateKey {
        // Create SecKey from PKCS#1 DER
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let privateSecKey = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            let msg = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw SSHTunnelError.privateKeyInvalid("Failed to create SecKey from RSA key: \(msg)")
        }

        // Extract public key
        guard let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw SSHTunnelError.privateKeyInvalid("Failed to extract public key from RSA key")
        }

        // Get public key external representation to extract e and n
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicSecKey, nil) as? Data else {
            throw SSHTunnelError.privateKeyInvalid("Failed to export RSA public key")
        }

        // Parse PKCS#1 public key DER to get e and n
        let (eBytes, nBytes) = try parseRSAPublicKeyDER(publicKeyData)

        let pubKey = RSASHA512PublicKey(secKey: publicSecKey, eBytes: eBytes, nBytes: nBytes)
        return RSASHA512PrivateKey(secKey: privateSecKey, publicKey: pubKey)
    }

    /// Parse PKCS#1 RSA public key DER (SEQUENCE { modulus INTEGER, publicExponent INTEGER })
    private static func parseRSAPublicKeyDER(_ data: Data) throws -> (e: Data, n: Data) {
        let bytes = [UInt8](data)
        var offset = 0

        // SEQUENCE
        guard offset < bytes.count, bytes[offset] == 0x30 else {
            throw SSHTunnelError.privateKeyInvalid("Invalid RSA public key DER: expected SEQUENCE")
        }
        offset += 1
        _ = try readDERLength(bytes, at: &offset)

        // modulus INTEGER
        let n = try readDERInteger(bytes, at: &offset)
        // publicExponent INTEGER
        let e = try readDERInteger(bytes, at: &offset)

        return (e: Data(e), n: Data(n))
    }

    private static func readDERLength(_ bytes: [UInt8], at offset: inout Int) throws -> Int {
        guard offset < bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid DER: unexpected end")
        }
        let first = bytes[offset]
        offset += 1
        if first < 0x80 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        guard numBytes <= 4, offset + numBytes <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid DER: length too large")
        }
        var length = 0
        for i in 0..<numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }

    private static func readDERInteger(_ bytes: [UInt8], at offset: inout Int) throws -> [UInt8] {
        guard offset < bytes.count, bytes[offset] == 0x02 else {
            throw SSHTunnelError.privateKeyInvalid("Invalid DER: expected INTEGER")
        }
        offset += 1
        let length = try readDERLength(bytes, at: &offset)
        guard offset + length <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid DER: integer truncated")
        }
        let value = Array(bytes[offset..<(offset + length)])
        offset += length
        return value
    }
}

// MARK: - Custom Auth Delegate

/// NIOSSHClientUserAuthenticationDelegate that offers RSA-SHA2-512 public key auth
nonisolated final class RSASHA512AuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: RSASHA512PrivateKey
    private var offered = false

    init(username: String, privateKey: RSASHA512PrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true

        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }

        let offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: NIOSSHPrivateKey(custom: privateKey)))
        )
        nextChallengePromise.succeed(offer)
    }
}

// MARK: - Algorithm Registration

nonisolated enum RSASHA512Setup {
    private nonisolated(unsafe) static var registered = false

    /// Register RSA-SHA2-512 key types with NIOSSH. Safe to call multiple times.
    nonisolated static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        NIOSSHAlgorithms.register(publicKey: RSASHA512PublicKey.self, signature: RSASHA512Signature.self)
    }
}

// MARK: - PEM Helpers

nonisolated enum RSASHA512PEMParser {
    /// Extract PKCS#1 DER data from a PEM RSA private key string
    static func extractPKCS1DER(from pemString: String) throws -> Data {
        var content = pemString
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        if content.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") && content.hasSuffix("-----END RSA PRIVATE KEY-----") {
            content.removeFirst("-----BEGIN RSA PRIVATE KEY-----".count)
            content.removeLast("-----END RSA PRIVATE KEY-----".count)
        } else {
            throw SSHTunnelError.privateKeyInvalid("Not a PEM RSA key")
        }

        guard let data = Data(base64Encoded: content) else {
            throw SSHTunnelError.privateKeyInvalid("Invalid base64 in PEM RSA key")
        }
        return data
    }
}
