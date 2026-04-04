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
                // Parse OpenSSH binary format to extract RSA components,
                // then build PKCS#1 DER and use RSA-SHA2-512 via SecKey
                let derData = try OpenSSHRSAParser.extractPKCS1DER(
                    from: keyString,
                    passphrase: passphrase
                )
                let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(derData)
                return .rsaSHA512(RSASHA512AuthDelegate(username: username, privateKey: privateKey))

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

// MARK: - OpenSSH RSA Key Parser

/// Parses an OpenSSH private key (v1 format) to extract RSA components,
/// then builds a PKCS#1 DER blob suitable for SecKeyCreateWithData.
///
/// OpenSSH v1 format:
///   "openssh-key-v1\0" magic
///   string ciphername, string kdfname, string kdfoptions
///   uint32 number_of_keys
///   string public_key_blob
///   string private_key_blob (encrypted if cipher != "none")
///
/// Decrypted private section for RSA:
///   uint32 check1, uint32 check2 (must match)
///   string "ssh-rsa"
///   mpint n, mpint e, mpint d, mpint iqmp, mpint p, mpint q
///   string comment
///   padding bytes (1,2,3,...)
private nonisolated enum OpenSSHRSAParser {

    static func extractPKCS1DER(from keyString: String, passphrase: String?) throws -> Data {
        // 1. Decode PEM envelope
        var content = keyString
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard content.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"),
              content.hasSuffix("-----END OPENSSH PRIVATE KEY-----") else {
            throw SSHTunnelError.privateKeyInvalid("Not an OpenSSH private key")
        }
        content.removeFirst("-----BEGIN OPENSSH PRIVATE KEY-----".count)
        content.removeLast("-----END OPENSSH PRIVATE KEY-----".count)

        guard let data = Data(base64Encoded: content) else {
            throw SSHTunnelError.privateKeyInvalid("Invalid base64 in OpenSSH key")
        }

        let bytes = [UInt8](data)
        var offset = 0

        // 2. Verify magic
        let magic = "openssh-key-v1\0"
        let magicBytes = [UInt8](magic.utf8)
        guard bytes.count > magicBytes.count,
              Array(bytes[0..<magicBytes.count]) == magicBytes else {
            throw SSHTunnelError.privateKeyInvalid("Invalid OpenSSH key magic")
        }
        offset = magicBytes.count

        // 3. Read cipher, kdf, kdfoptions
        let cipherName = try readSSHString(bytes, at: &offset)
        let _ = try readSSHString(bytes, at: &offset)  // kdfname
        let _ = try readSSHStringBytes(bytes, at: &offset)  // kdfoptions

        // 4. Number of keys
        let numKeys = try readUInt32(bytes, at: &offset)
        guard numKeys == 1 else {
            throw SSHTunnelError.privateKeyInvalid("Multiple keys not supported")
        }

        // 5. Skip public key blob
        let _ = try readSSHStringBytes(bytes, at: &offset)

        // 6. Read private key blob
        let privateBlob = try readSSHStringBytes(bytes, at: &offset)

        // 7. Check if encrypted
        let isEncrypted = cipherName != "none"
        if isEncrypted {
            if passphrase == nil || passphrase?.isEmpty == true {
                throw SSHTunnelError.passphraseRequired
            }
            // Encrypted OpenSSH RSA keys require decryption (bcrypt KDF + AES-CTR).
            // Convert to PEM format for full support.
            throw SSHTunnelError.privateKeyInvalid(
                "Encrypted OpenSSH RSA keys: convert to PEM with:\nssh-keygen -p -m PEM -f <keyfile>"
            )
        }

        // 8. Parse the unencrypted private section
        var pOff = 0
        let pBytes = [UInt8](privateBlob)

        let check1 = try readUInt32(pBytes, at: &pOff)
        let check2 = try readUInt32(pBytes, at: &pOff)
        guard check1 == check2 else {
            throw SSHTunnelError.privateKeyInvalid("OpenSSH key checksum mismatch")
        }

        let keyType = try readSSHString(pBytes, at: &pOff)
        guard keyType == "ssh-rsa" else {
            throw SSHTunnelError.privateKeyInvalid("Expected ssh-rsa, got \(keyType)")
        }

        // RSA components in OpenSSH order: n, e, d, iqmp, p, q
        let n = try readSSHMPIntBytes(pBytes, at: &pOff)
        let e = try readSSHMPIntBytes(pBytes, at: &pOff)
        let d = try readSSHMPIntBytes(pBytes, at: &pOff)
        let iqmp = try readSSHMPIntBytes(pBytes, at: &pOff)
        let p = try readSSHMPIntBytes(pBytes, at: &pOff)
        let q = try readSSHMPIntBytes(pBytes, at: &pOff)

        // 9. Build PKCS#1 DER
        return PKCS1DERBuilder.build(n: n, e: e, d: d, p: p, q: q, iqmp: iqmp)
    }

    // MARK: - SSH Binary Readers

    private static func readUInt32(_ bytes: [UInt8], at offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Truncated OpenSSH key")
        }
        let value = UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }

    private static func readSSHStringBytes(_ bytes: [UInt8], at offset: inout Int) throws -> [UInt8] {
        let length = Int(try readUInt32(bytes, at: &offset))
        guard offset + length <= bytes.count else {
            throw SSHTunnelError.privateKeyInvalid("Truncated OpenSSH key string")
        }
        let result = Array(bytes[offset..<(offset + length)])
        offset += length
        return result
    }

    private static func readSSHString(_ bytes: [UInt8], at offset: inout Int) throws -> String {
        let raw = try readSSHStringBytes(bytes, at: &offset)
        guard let str = String(bytes: raw, encoding: .utf8) else {
            throw SSHTunnelError.privateKeyInvalid("Invalid UTF-8 in OpenSSH key")
        }
        return str
    }

    private static func readSSHMPIntBytes(_ bytes: [UInt8], at offset: inout Int) throws -> [UInt8] {
        try readSSHStringBytes(bytes, at: &offset)
    }
}

// MARK: - PKCS#1 DER Builder

/// Builds a PKCS#1 RSA private key DER blob from raw RSA components.
/// Format: SEQUENCE { version, n, e, d, p, q, dp, dq, iqmp }
private nonisolated enum PKCS1DERBuilder {

    static func build(n: [UInt8], e: [UInt8], d: [UInt8], p: [UInt8], q: [UInt8], iqmp: [UInt8]) -> Data {
        // Compute dp = d mod (p-1), dq = d mod (q-1) — required by PKCS#1
        // For SecKey we can pass 0 and let the framework compute them,
        // but some implementations require valid values.
        // Use a simple big-integer mod for this.
        let dp = bigIntMod(d, subtractOne(p))
        let dq = bigIntMod(d, subtractOne(q))

        var inner = [UInt8]()
        writeASN1Integer(&inner, [0])  // version = 0
        writeASN1Integer(&inner, n)
        writeASN1Integer(&inner, e)
        writeASN1Integer(&inner, d)
        writeASN1Integer(&inner, p)
        writeASN1Integer(&inner, q)
        writeASN1Integer(&inner, dp)
        writeASN1Integer(&inner, dq)
        writeASN1Integer(&inner, iqmp)

        var result = [UInt8]()
        result.append(0x30) // SEQUENCE
        writeASN1Length(&result, inner.count)
        result.append(contentsOf: inner)

        return Data(result)
    }

    private static func writeASN1Integer(_ buf: inout [UInt8], _ value: [UInt8]) {
        // Strip leading zeros but keep at least one byte
        var start = 0
        while start < value.count - 1 && value[start] == 0 {
            start += 1
        }
        let stripped = Array(value[start...])

        buf.append(0x02) // INTEGER tag
        // Need leading zero if high bit is set (to keep positive)
        if stripped[0] & 0x80 != 0 {
            writeASN1Length(&buf, stripped.count + 1)
            buf.append(0x00)
        } else {
            writeASN1Length(&buf, stripped.count)
        }
        buf.append(contentsOf: stripped)
    }

    private static func writeASN1Length(_ buf: inout [UInt8], _ length: Int) {
        if length < 0x80 {
            buf.append(UInt8(length))
        } else if length <= 0xFF {
            buf.append(0x81)
            buf.append(UInt8(length))
        } else if length <= 0xFFFF {
            buf.append(0x82)
            buf.append(UInt8((length >> 8) & 0xFF))
            buf.append(UInt8(length & 0xFF))
        } else {
            buf.append(0x83)
            buf.append(UInt8((length >> 16) & 0xFF))
            buf.append(UInt8((length >> 8) & 0xFF))
            buf.append(UInt8(length & 0xFF))
        }
    }

    // MARK: - Simple big-integer helpers (byte arrays, big-endian, unsigned)

    /// Subtract 1 from a big-endian unsigned byte array
    private static func subtractOne(_ value: [UInt8]) -> [UInt8] {
        var result = value
        var i = result.count - 1
        while i >= 0 {
            if result[i] > 0 {
                result[i] -= 1
                break
            }
            result[i] = 0xFF
            i -= 1
        }
        return result
    }

    /// Compute a mod m using schoolbook division on byte arrays
    /// Both values are big-endian unsigned.
    private static func bigIntMod(_ a: [UInt8], _ m: [UInt8]) -> [UInt8] {
        // Strip leading zeros from both
        let aStripped = stripLeadingZeros(a)
        let mStripped = stripLeadingZeros(m)

        guard !mStripped.isEmpty, mStripped != [0] else { return [0] }

        // Use a simple repeated-subtraction-via-shift approach
        // Convert to a mutable working copy
        var remainder = aStripped

        // If a < m, result is a
        if compare(remainder, mStripped) < 0 { return remainder }

        // Bit-by-bit long division
        let mBits = bitLength(mStripped)
        let aBits = bitLength(remainder)
        var shift = aBits - mBits

        var shifted = leftShift(mStripped, by: shift)
        while shift >= 0 {
            if compare(remainder, shifted) >= 0 {
                remainder = subtract(remainder, shifted)
            }
            shifted = rightShift(shifted, by: 1)
            shift -= 1
        }

        return remainder.isEmpty ? [0] : remainder
    }

    private static func stripLeadingZeros(_ v: [UInt8]) -> [UInt8] {
        var start = 0
        while start < v.count - 1 && v[start] == 0 { start += 1 }
        return Array(v[start...])
    }

    private static func bitLength(_ v: [UInt8]) -> Int {
        guard let first = v.first, first != 0 else { return 0 }
        return (v.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    }

    private static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let a = stripLeadingZeros(a), b = stripLeadingZeros(b)
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in 0..<a.count {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        }
        return 0
    }

    private static func subtract(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        var aP = [UInt8](repeating: 0, count: maxLen - a.count) + a
        let bP = [UInt8](repeating: 0, count: maxLen - b.count) + b
        var borrow: Int = 0
        for i in stride(from: maxLen - 1, through: 0, by: -1) {
            let diff = Int(aP[i]) - Int(bP[i]) - borrow
            if diff < 0 {
                aP[i] = UInt8(diff + 256)
                borrow = 1
            } else {
                aP[i] = UInt8(diff)
                borrow = 0
            }
        }
        return stripLeadingZeros(aP)
    }

    private static func leftShift(_ v: [UInt8], by bits: Int) -> [UInt8] {
        guard bits > 0 else { return v }
        let byteShift = bits / 8
        let bitShift = bits % 8
        var result = v + [UInt8](repeating: 0, count: byteShift)
        if bitShift > 0 {
            var carry: UInt8 = 0
            for i in stride(from: result.count - 1, through: 0, by: -1) {
                let newCarry = result[i] >> (8 - bitShift)
                result[i] = (result[i] << bitShift) | carry
                carry = newCarry
            }
            if carry != 0 { result.insert(carry, at: 0) }
        }
        return result
    }

    private static func rightShift(_ v: [UInt8], by bits: Int) -> [UInt8] {
        guard bits > 0, !v.isEmpty else { return v }
        let byteShift = bits / 8
        let bitShift = bits % 8
        guard byteShift < v.count else { return [0] }
        var result = Array(v[0..<(v.count - byteShift)])
        if bitShift > 0 {
            var carry: UInt8 = 0
            for i in 0..<result.count {
                let newCarry = result[i] << (8 - bitShift)
                result[i] = (result[i] >> bitShift) | carry
                carry = newCarry
            }
        }
        return stripLeadingZeros(result)
    }
}

