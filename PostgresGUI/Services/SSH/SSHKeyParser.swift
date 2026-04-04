//
//  SSHKeyParser.swift
//  PostgresGUI
//
//  Parses SSH private keys from multiple formats and returns Citadel auth methods.
//
//  Supported formats & algorithms:
//    OpenSSH  (-----BEGIN OPENSSH PRIVATE KEY-----)  — RSA, Ed25519
//    PEM RSA  (-----BEGIN RSA PRIVATE KEY-----)      — RSA (PKCS#1, converted to OpenSSH in memory)
//    PEM EC   (-----BEGIN EC PRIVATE KEY-----)       — ECDSA P-256, P-384, P-521
//    PEM PKCS#8 (-----BEGIN PRIVATE KEY-----)        — ECDSA P-256, P-384, P-521
//

import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

/// Parses SSH private key files in various formats and produces Citadel auth methods
nonisolated enum SSHKeyParser {

    /// Result of parsing a private key — either a Citadel auth method or a custom RSA-SHA2-512 delegate
    enum ParsedKey {
        case citadel(Citadel.SSHAuthenticationMethod)
        case rsaSHA512(RSASHA512AuthDelegate)
    }

    /// Parse a private key file and return the appropriate authentication
    static func parsePrivateKey(
        _ keyString: String,
        username: String,
        passphrase: String?
    ) throws -> ParsedKey {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") {
            return try parseOpenSSHKey(trimmed, username: username, passphrase: passphrase)
        } else if trimmed.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") {
            return try parsePKCS1RSAKey(trimmed, username: username)
        } else if trimmed.hasPrefix("-----BEGIN EC PRIVATE KEY-----") {
            return .citadel(try parsePEMECKey(trimmed, username: username))
        } else if trimmed.hasPrefix("-----BEGIN PRIVATE KEY-----") {
            return try parsePKCS8Key(trimmed, username: username)
        } else if trimmed.hasPrefix("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
            throw SSHTunnelError.privateKeyInvalid(
                "PKCS#8 encrypted keys are not supported. Decrypt with:\nssh-keygen -p -f <keyfile>"
            )
        } else {
            throw SSHTunnelError.privateKeyInvalid(
                "Unrecognized key format. Supported: OpenSSH, PEM RSA, PEM EC, PKCS#8."
            )
        }
    }

    // MARK: - OpenSSH Format

    private static func parseOpenSSHKey(
        _ keyString: String,
        username: String,
        passphrase: String?
    ) throws -> ParsedKey {
        do {
            let keyType = try SSHKeyDetection.detectPrivateKeyType(from: keyString)
            let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) }

            switch keyType {
            case .ed25519:
                let key = try Curve25519.Signing.PrivateKey(
                    sshEd25519: keyString,
                    decryptionKey: decryptionKey
                )
                return .citadel(.ed25519(username: username, privateKey: key))

            case .rsa:
                // Use RSA-SHA2-512 for modern SSH server compatibility
                let key = try Insecure.RSA.PrivateKey(
                    sshRsa: keyString,
                    decryptionKey: decryptionKey
                )
                // For OpenSSH format RSA keys, we need to re-parse through SecKey
                // to get SHA-512 signing. Extract the PEM from the OpenSSH format
                // and use Citadel's SHA-1 as fallback, but prefer SHA-512.
                // Since we can't easily extract PKCS#1 DER from OpenSSH binary format,
                // fall back to Citadel's RSA (SHA-1) for OpenSSH-format RSA keys.
                // Users with OpenSSH RSA keys on modern servers should use ed25519 instead.
                return .citadel(.rsa(username: username, privateKey: key))

            case .ecdsaP256, .ecdsaP384, .ecdsaP521:
                throw SSHTunnelError.privateKeyInvalid(
                    "OpenSSH ECDSA keys: convert to PEM with:\nssh-keygen -p -m PEM -f <keyfile>"
                )

            default:
                throw SSHTunnelError.privateKeyInvalid("Unsupported key type: \(keyType)")
            }
        } catch let error as SSHKeyDetectionError where error == .passphraseRequired || error == .encryptedPrivateKey {
            throw SSHTunnelError.passphraseRequired
        } catch let error as SSHKeyDetectionError where error == .incorrectPassphrase {
            throw SSHTunnelError.privateKeyInvalid("Incorrect passphrase")
        } catch let error as SSHTunnelError {
            throw error
        } catch let error as InvalidOpenSSHKey {
            let desc = String(describing: error).lowercased()
            if desc.contains("check") {
                if passphrase == nil || passphrase?.isEmpty == true {
                    throw SSHTunnelError.passphraseRequired
                }
                throw SSHTunnelError.privateKeyInvalid("Incorrect passphrase")
            }
            throw SSHTunnelError.privateKeyInvalid(String(describing: error))
        } catch {
            if passphrase == nil || passphrase?.isEmpty == true {
                let desc = String(describing: error).lowercased()
                if desc.contains("decrypt") || desc.contains("passphrase") || desc.contains("check") || desc.contains("missing") {
                    throw SSHTunnelError.passphraseRequired
                }
            }
            throw SSHTunnelError.privateKeyInvalid(error.localizedDescription)
        }
    }

    // MARK: - PEM PKCS#1 RSA → OpenSSH Conversion

    /// Parses a PEM RSA PKCS#1 key using RSA-SHA2-512 for modern SSH server compatibility
    private static func parsePKCS1RSAKey(
        _ keyString: String,
        username: String
    ) throws -> ParsedKey {
        if keyString.contains("Proc-Type: 4,ENCRYPTED") {
            throw SSHTunnelError.privateKeyInvalid(
                "Encrypted PEM RSA keys: decrypt first with:\nssh-keygen -p -f <keyfile>"
            )
        }

        // Extract PKCS#1 DER data from PEM
        let derData = try RSASHA512PEMParser.extractPKCS1DER(from: keyString)

        // Create RSA-SHA2-512 key using Security framework
        let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(derData)
        return .rsaSHA512(RSASHA512AuthDelegate(username: username, privateKey: privateKey))
    }

    // MARK: - PEM EC (SEC 1)

    private static func parsePEMECKey(
        _ keyString: String,
        username: String
    ) throws -> Citadel.SSHAuthenticationMethod {
        if keyString.contains("Proc-Type: 4,ENCRYPTED") {
            throw SSHTunnelError.privateKeyInvalid(
                "Encrypted PEM EC keys: decrypt first with:\nssh-keygen -p -f <keyfile>"
            )
        }

        if let key = try? P256.Signing.PrivateKey(pemRepresentation: keyString) {
            return .p256(username: username, privateKey: key)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: keyString) {
            return .p384(username: username, privateKey: key)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: keyString) {
            return .p521(username: username, privateKey: key)
        }

        throw SSHTunnelError.privateKeyInvalid("Failed to parse EC key — unsupported curve")
    }

    // MARK: - PEM PKCS#8

    private static func parsePKCS8Key(
        _ keyString: String,
        username: String
    ) throws -> ParsedKey {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: keyString) {
            return .citadel(.p256(username: username, privateKey: key))
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: keyString) {
            return .citadel(.p384(username: username, privateKey: key))
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: keyString) {
            return .citadel(.p521(username: username, privateKey: key))
        }

        // Try RSA PKCS#8: unwrap the PKCS#8 envelope to get PKCS#1, then use SHA-512
        do {
            let pkcs1Data = try PKCS8Unwrapper.unwrapRSA(pemString: keyString)
            let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(pkcs1Data)
            return .rsaSHA512(RSASHA512AuthDelegate(username: username, privateKey: privateKey))
        } catch let error as SSHTunnelError {
            throw error
        } catch {
            // Fall through
        }

        throw SSHTunnelError.privateKeyInvalid(
            "Unsupported PKCS#8 key algorithm. Supported: RSA, ECDSA (P-256/P-384/P-521). For Ed25519, use OpenSSH format."
        )
    }
}

// MARK: - RSA Components

/// Raw RSA key components extracted from PKCS#1 ASN.1
private struct RSAComponents {
    let n: [UInt8]      // modulus
    let e: [UInt8]      // public exponent
    let d: [UInt8]      // private exponent
    let iqmp: [UInt8]   // CRT coefficient
    let p: [UInt8]      // prime1
    let q: [UInt8]      // prime2
}

// MARK: - PKCS#1 ASN.1 Parser

/// Minimal ASN.1 DER parser for PKCS#1 RSA private keys
private enum PKCS1Parser {

    static func parse(_ der: Data) throws -> RSAComponents {
        var offset = 0
        let bytes = [UInt8](der)

        // SEQUENCE
        guard readTag(bytes, at: &offset) == 0x30 else {
            throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#1: expected SEQUENCE")
        }
        _ = try readLength(bytes, at: &offset)

        // version INTEGER (should be 0)
        let version = try readInteger(bytes, at: &offset)
        guard version.count == 1 && version[0] == 0 else {
            throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#1: unsupported version")
        }

        let n = try readInteger(bytes, at: &offset)
        let e = try readInteger(bytes, at: &offset)
        let d = try readInteger(bytes, at: &offset)
        let p = try readInteger(bytes, at: &offset)
        let q = try readInteger(bytes, at: &offset)
        _ = try readInteger(bytes, at: &offset) // dp (not needed for OpenSSH)
        _ = try readInteger(bytes, at: &offset) // dq (not needed for OpenSSH)
        let iqmp = try readInteger(bytes, at: &offset)

        return RSAComponents(n: n, e: e, d: d, iqmp: iqmp, p: p, q: q)
    }

    private static func readTag(_ bytes: [UInt8], at offset: inout Int) -> UInt8? {
        guard offset < bytes.count else { return nil }
        let tag = bytes[offset]
        offset += 1
        return tag
    }

    private static func readLength(_ bytes: [UInt8], at offset: inout Int) throws -> Int {
        guard offset < bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1: unexpected end")
        }
        let first = bytes[offset]
        offset += 1

        if first < 0x80 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard numBytes <= 4, offset + numBytes <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1: length too large")
        }

        var length = 0
        for i in 0..<numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }

    /// Read an ASN.1 INTEGER and return its raw bytes (stripped of leading zero padding)
    private static func readInteger(_ bytes: [UInt8], at offset: inout Int) throws -> [UInt8] {
        guard readTag(bytes, at: &offset) == 0x02 else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1: expected INTEGER")
        }
        let length = try readLength(bytes, at: &offset)
        guard offset + length <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1: integer truncated")
        }
        let value = Array(bytes[offset..<(offset + length)])
        offset += length
        return value
    }
}

// MARK: - PKCS#8 RSA Unwrapper

/// Unwraps a PKCS#8 PEM envelope to extract the inner PKCS#1 RSA key
private nonisolated enum PKCS8Unwrapper {

    /// RSA OID: 1.2.840.113549.1.1.1
    private static let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func unwrapRSA(pemString: String) throws -> Data {
        var content = pemString.replacingOccurrences(of: "\n", with: "")
        content = content.replacingOccurrences(of: "\r", with: "")
        guard content.hasPrefix("-----BEGIN PRIVATE KEY-----"),
              content.hasSuffix("-----END PRIVATE KEY-----") else {
            throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8 PEM format")
        }
        content.removeFirst("-----BEGIN PRIVATE KEY-----".count)
        content.removeLast("-----END PRIVATE KEY-----".count)

        guard let der = Data(base64Encoded: content) else {
            throw SSHTunnelError.privateKeyInvalid("Invalid base64 in PKCS#8 key")
        }

        let bytes = [UInt8](der)
        var offset = 0

        // Outer SEQUENCE
        guard bytes[offset] == 0x30 else { throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8") }
        offset += 1
        _ = try readLength(bytes, at: &offset)

        // version INTEGER (should be 0)
        guard bytes[offset] == 0x02 else { throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8") }
        offset += 1
        let versionLen = try readLength(bytes, at: &offset)
        offset += versionLen

        // AlgorithmIdentifier SEQUENCE
        guard bytes[offset] == 0x30 else { throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8") }
        offset += 1
        let algoLen = try readLength(bytes, at: &offset)
        let algoEnd = offset + algoLen

        // OID inside AlgorithmIdentifier
        guard bytes[offset] == 0x06 else { throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8") }
        offset += 1
        let oidLen = try readLength(bytes, at: &offset)
        let oid = Array(bytes[offset..<(offset + oidLen)])

        guard oid == rsaOID else {
            throw SSHTunnelError.privateKeyInvalid("Not an RSA key")
        }
        offset = algoEnd

        // privateKey OCTET STRING containing PKCS#1
        guard bytes[offset] == 0x04 else { throw SSHTunnelError.privateKeyInvalid("Invalid PKCS#8") }
        offset += 1
        let pkcs1Len = try readLength(bytes, at: &offset)
        let pkcs1Data = Data(bytes[offset..<(offset + pkcs1Len)])

        return pkcs1Data
    }

    private static func readLength(_ bytes: [UInt8], at offset: inout Int) throws -> Int {
        guard offset < bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1")
        }
        let first = bytes[offset]
        offset += 1
        if first < 0x80 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        guard numBytes <= 4, offset + numBytes <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Invalid ASN.1")
        }
        var length = 0
        for i in 0..<numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }
}

// MARK: - OpenSSH RSA Key Builder

/// Constructs an OpenSSH format RSA private key string from raw RSA components
private enum OpenSSHRSABuilder {

    static func build(from rsa: RSAComponents) -> String {
        var publicKeyBuf = [UInt8]()
        writeSSHString(&publicKeyBuf, "ssh-rsa")
        writeSSHMPInt(&publicKeyBuf, rsa.e)
        writeSSHMPInt(&publicKeyBuf, rsa.n)

        let checkInt = UInt32.random(in: UInt32.min...UInt32.max)

        var privateBuf = [UInt8]()
        writeUInt32(&privateBuf, checkInt)
        writeUInt32(&privateBuf, checkInt)
        writeSSHString(&privateBuf, "ssh-rsa")
        writeSSHMPInt(&privateBuf, rsa.n)
        writeSSHMPInt(&privateBuf, rsa.e)
        writeSSHMPInt(&privateBuf, rsa.d)
        writeSSHMPInt(&privateBuf, rsa.iqmp)
        writeSSHMPInt(&privateBuf, rsa.p)
        writeSSHMPInt(&privateBuf, rsa.q)
        writeSSHString(&privateBuf, "")  // comment

        // Padding to block size (8 for cipher "none")
        let blockSize = 8
        let padNeeded = blockSize - (privateBuf.count % blockSize)
        if padNeeded < blockSize {
            for i in 1...padNeeded {
                privateBuf.append(UInt8(i))
            }
        }

        // Build the full OpenSSH key
        var fullBuf = [UInt8]()

        // Magic
        fullBuf.append(contentsOf: "openssh-key-v1".utf8)
        fullBuf.append(0x00)

        // cipher = "none"
        writeSSHString(&fullBuf, "none")
        // kdf = "none"
        writeSSHString(&fullBuf, "none")
        // kdf options = empty
        writeSSHBytes(&fullBuf, [])
        // number of keys = 1
        writeUInt32(&fullBuf, 1)
        // public key
        writeSSHBytes(&fullBuf, publicKeyBuf)
        // private section
        writeSSHBytes(&fullBuf, privateBuf)

        // Use raw base64 without line breaks — Citadel strips \n but not \r,
        // and Apple's .lineLength* options insert \r\n on some platforms
        let base64 = Data(fullBuf).base64EncodedString()
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(base64)\n-----END OPENSSH PRIVATE KEY-----\n"
    }

    // MARK: - Binary Helpers

    private static func writeUInt32(_ buf: inout [UInt8], _ value: UInt32) {
        buf.append(UInt8((value >> 24) & 0xFF))
        buf.append(UInt8((value >> 16) & 0xFF))
        buf.append(UInt8((value >> 8) & 0xFF))
        buf.append(UInt8(value & 0xFF))
    }

    private static func writeSSHString(_ buf: inout [UInt8], _ string: String) {
        let bytes = [UInt8](string.utf8)
        writeUInt32(&buf, UInt32(bytes.count))
        buf.append(contentsOf: bytes)
    }

    private static func writeSSHBytes(_ buf: inout [UInt8], _ bytes: [UInt8]) {
        writeUInt32(&buf, UInt32(bytes.count))
        buf.append(contentsOf: bytes)
    }

    /// Write an SSH mpint (multi-precision integer)
    /// Strips leading zeros, adds a leading zero byte if high bit is set
    private static func writeSSHMPInt(_ buf: inout [UInt8], _ value: [UInt8]) {
        // Strip leading zeros
        var start = 0
        while start < value.count - 1 && value[start] == 0 {
            start += 1
        }
        let stripped = Array(value[start...])

        // Add leading zero if high bit set (to keep it positive)
        if stripped[0] & 0x80 != 0 {
            writeUInt32(&buf, UInt32(stripped.count + 1))
            buf.append(0x00)
            buf.append(contentsOf: stripped)
        } else {
            writeUInt32(&buf, UInt32(stripped.count))
            buf.append(contentsOf: stripped)
        }
    }
}
