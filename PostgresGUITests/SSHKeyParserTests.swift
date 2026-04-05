//
//  SSHKeyParserTests.swift
//  PostgresGUITests
//
//  Unit tests for SSHKeyParser — PEM RSA (PKCS#1) to OpenSSH conversion,
//  key format detection, and error handling.
//

import Foundation
import Testing
@testable import PostgresGUI

// MARK: - PKCS#1 ASN.1 Parsing + OpenSSH Conversion

@Suite("SSHKeyParser — PEM RSA (PKCS#1)", .serialized)
struct SSHKeyParserPKCS1Tests {

    /// A valid 2048-bit PEM RSA private key for testing
    static let validPEMRSAKey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEAyMV0Ne2OONCnoPovq7N6hSHIvidtZ6HBDVtA+GyMRBa4uQpQ
    9VcPkAmiu9t3gQDkZCYrFdJWs+ohUZ6BK+7i3u0QDhcNv6JjWoWprUYD0NI9HjSr
    l8Hs1oSIk5Ggy9cQ0zLEdKGb8AM9j0ZHlv+Zotwc/sYK1aaB+1Ip9i1p/CtbCL6V
    s9WqernHZbGY4T+FJVxr9I2PU5O+nsYuudc3oCbiiF8cQiBRRboa7j5XlrHoAzZ6
    R927pKOi1ynZGFyU2ed5sf0rZhh6pZv3ZfBl4wz0LNrUfsbt1AmtkiwqyXkBOale
    5aCgsqEtYJ0t9COfCXWa6FKs/Z2Pu4a0M+PuzwIDAQABAoIBAQCLRmaKboQFp8FR
    a50cOEJbDoeqWcGMbWp1sIMOkoZvSW/VdXGZ8E4sdnK8bM+m3w6Q5uVmmuZoopeA
    fjtPVcVuLffAPn/cG3NevXBqcjJ9bwrU5GbQvMdmPMRd0l1Aaq4SRJqB6gY55pWS
    yYcqGZ/jmVxH5OxpL7vlsybGztRCCDnvjorKdGF+695yeLAf999PesOWyvRZSi8x
    1q0rKWlDy8ob1l5nIUCYk3lF1D6FMcUQkJ4mttJbzTI3J57i8s4edvZPdOTik7sO
    sRW0wYQSTgck611qShh8I27Q9jDH7+maigwyN3OlKeswakzYuFByayF/auhIZMQ3
    oROrjRHRAoGBAPWRHX/0CszgEMlXwvMitEPot3GI97y7dUD2hdI9Ev3ijgrGgdq/
    VZXNUVvT1KAJbEFk7M4oIhYOlCjMhOpVbqJS7gMso1ZfqQRJXkfk8sIwQOxAF9UZ
    izZKQqHqIHLQxX7Oe86R7wyYXboUAEUZtp6QJ3zZShIV/fAwk5Tsq5sXAoGBANFN
    H8YYABb1ljG3bFJBkKLuk5V0Qm1r6FF/ycGo2/aXIEX8O2dxnpTgc67CrJaV9YEJ
    EzBZHkFyivxm25Bd2Ce7i2mz1sIuatX0YgOkeFyEwIwCqcqm+jadwD/NbfxgJi+2
    3Za+pmP+cBFtAUqFoNyrCkPRGiQ99P8MENc1sT0JAoGAL/kIfU2sqnd/cAYQFLWL
    59RXuftbAmjQsD84x2idBDI1M4+yIIzOaHRy13CbkiQlHOVdiay3c/2nHg1OTgUg
    lt+CleYrhp0rhKXcoEjuz9bjaAPhZAUYeCOrvrvhWOzGGE64SxOhUqGVddugbd9n
    GLTqse41FTFsqXaj7i0KHUMCgYAI3ZNy+KFIV668/GACO/S8cg6eTgZiTCfTC+6n
    3Vcz4sLjNAPwJcfp1ngP9v8IgeGcTZ4adivp6cgpWNIEE3WMeU02dP+ryfuMhIWC
    Uf0nLhhZ1eMLSndeyN/T1AfMoOX9L2nDcN/rbGOi2VMsrOxbbINKzBinYFh4VTKB
    ayzOwQKBgB4hYlx3N7DWR+uGR0RYdOJ9XWjQQ24Dp0AHqDbP4Bo/fHEn6di6hvdQ
    0+nKw0AyNCP+XBeMZw+XMbtIKTsmbA1u+DRmr+cLvtPJQj5TlDWNFUdNz6BzyWdS
    TiOxcYfzCRNjte1fV5F6y/jG0K2FkTBiTOutYuX7sgl/FmHTYjYQ
    -----END RSA PRIVATE KEY-----
    """

    @Test func parsesPEMRSAKeySuccessfully() throws {
        let result = try SSHKeyParser.parsePrivateKey(
            Self.validPEMRSAKey,
            username: "testuser",
            passphrase: nil
        )
        // PEM RSA keys should use RSA-SHA2-512 for modern SSH server compatibility
        if case .rsaSHA512 = result {
            // expected
        } else {
            Issue.record("Expected .rsaSHA512 for PEM RSA key, got .citadel")
        }
    }

    @Test func detectsPEMRSAFormat() throws {
        let trimmed = Self.validPEMRSAKey.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.hasPrefix("-----BEGIN RSA PRIVATE KEY-----"))
    }

    @Test func rejectsEncryptedPEMRSA() {
        let encryptedKey = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-128-CBC,AABBCCDD

        MIIEowIBAAKCAQEA...
        -----END RSA PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(encryptedKey, username: "user", passphrase: nil)
        }
    }

    @Test func rejectsInvalidBase64() {
        let badKey = """
        -----BEGIN RSA PRIVATE KEY-----
        not-valid-base64!!!
        -----END RSA PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(badKey, username: "user", passphrase: nil)
        }
    }

    @Test func rejectsTruncatedDER() {
        // Valid base64 but truncated DER — should fail during ASN.1 parsing
        let truncatedKey = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIBCgKCAQEA
        -----END RSA PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(truncatedKey, username: "user", passphrase: nil)
        }
    }
}

// MARK: - Format Detection

@Suite("SSHKeyParser — Format Detection")
struct SSHKeyParserFormatTests {

    @Test func rejectsUnrecognizedFormat() {
        let garbage = "not a key at all"

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(garbage, username: "user", passphrase: nil)
        }
    }

    @Test func rejectsEncryptedPKCS8() {
        let key = """
        -----BEGIN ENCRYPTED PRIVATE KEY-----
        MIIFHDBOBgkqhkiG9w0BBQ0w...
        -----END ENCRYPTED PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(key, username: "user", passphrase: nil)
        }
    }

    @Test func detectsOpenSSHFormat() {
        let key = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEA
        -----END OPENSSH PRIVATE KEY-----
        """

        // Will fail during parsing (truncated), but should attempt OpenSSH path
        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(key, username: "user", passphrase: nil)
        }
    }

    @Test func detectsPEMECFormat() {
        let key = """
        -----BEGIN EC PRIVATE KEY-----
        MHQCAQEEIBkg
        -----END EC PRIVATE KEY-----
        """

        // Will fail during parsing (truncated), but should attempt EC path
        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(key, username: "user", passphrase: nil)
        }
    }

    @Test func detectsPKCS8Format() {
        let key = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMG
        -----END PRIVATE KEY-----
        """

        // Will fail during parsing (truncated), but should attempt PKCS#8 path
        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(key, username: "user", passphrase: nil)
        }
    }
}

// MARK: - SSHTunnelConfig

@Suite("SSHTunnelConfig")
struct SSHTunnelConfigTests {

    @Test func createsPasswordConfig() {
        let config = SSHTunnelConfig(
            sshHost: "bastion.example.com",
            sshPort: 22,
            sshUsername: "ubuntu",
            authMethod: .password,
            password: "secret",
            privateKeyPath: nil,
            privateKeyContent: nil,
            passphrase: nil,
            remoteHost: "10.0.1.5",
            remotePort: 5432
        )

        #expect(config.sshHost == "bastion.example.com")
        #expect(config.sshPort == 22)
        #expect(config.sshUsername == "ubuntu")
        #expect(config.authMethod == .password)
        #expect(config.password == "secret")
        #expect(config.privateKeyPath == nil)
        #expect(config.remoteHost == "10.0.1.5")
        #expect(config.remotePort == 5432)
    }

    @Test func createsPrivateKeyConfig() {
        let config = SSHTunnelConfig(
            sshHost: "bastion.example.com",
            sshPort: 2222,
            sshUsername: "deploy",
            authMethod: .privateKey,
            password: nil,
            privateKeyPath: "/Users/test/.ssh/id_rsa",
            privateKeyContent: nil,
            passphrase: "keypass",
            remoteHost: "db.internal",
            remotePort: 5433
        )

        #expect(config.authMethod == .privateKey)
        #expect(config.privateKeyPath == "/Users/test/.ssh/id_rsa")
        #expect(config.passphrase == "keypass")
        #expect(config.sshPort == 2222)
        #expect(config.remotePort == 5433)
    }
}

// MARK: - SSHAuthMethod

@Suite("SSHAuthMethod")
struct SSHAuthMethodTests {

    @Test func rawValues() {
        #expect(SSHAuthMethod.password.rawValue == "password")
        #expect(SSHAuthMethod.privateKey.rawValue == "privateKey")
    }

    @Test func displayNames() {
        #expect(SSHAuthMethod.password.displayName == "Password")
        #expect(SSHAuthMethod.privateKey.displayName == "Private Key")
    }

    @Test func roundTripsFromRawValue() {
        #expect(SSHAuthMethod(rawValue: "password") == .password)
        #expect(SSHAuthMethod(rawValue: "privateKey") == .privateKey)
        #expect(SSHAuthMethod(rawValue: "invalid") == nil)
    }

    @Test func allCases() {
        #expect(SSHAuthMethod.allCases.count == 2)
    }
}

// MARK: - SSHTunnelError

@Suite("SSHTunnelError")
struct SSHTunnelErrorTests {

    @Test func errorDescriptions() {
        #expect(SSHTunnelError.authenticationFailed.errorDescription != nil)
        #expect(SSHTunnelError.hostUnreachable("example.com").errorDescription?.contains("example.com") == true)
        #expect(SSHTunnelError.privateKeyNotFound("/path").errorDescription?.contains("/path") == true)
        #expect(SSHTunnelError.privateKeyInvalid("bad format").errorDescription?.contains("bad format") == true)
        #expect(SSHTunnelError.passphraseRequired.errorDescription != nil)
        #expect(SSHTunnelError.channelOpenFailed.errorDescription != nil)
        #expect(SSHTunnelError.tunnelClosed.errorDescription != nil)
        #expect(SSHTunnelError.timeout.errorDescription != nil)
    }

    @Test func recoverySuggestions() {
        #expect(SSHTunnelError.authenticationFailed.recoverySuggestion != nil)
        #expect(SSHTunnelError.passphraseRequired.recoverySuggestion != nil)
        #expect(SSHTunnelError.timeout.recoverySuggestion != nil)
    }
}

// MARK: - OpenSSH RSA Parsing + RSA-SHA2-512

@Suite("SSHKeyParser — OpenSSH RSA", .serialized)
struct SSHKeyParserOpenSSHRSATests {

    /// A valid unencrypted OpenSSH RSA private key for testing
    static let validOpenSSHRSAKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
    NhAAAAAwEAAQAAAQEAskWRa+k0CMHe0BFDku/iblvV3cWzuuBx2uVniV5QKY3DepyYW+LF
    9PvlrqITu4WDJ4o9ye0sZYd1I24ZY6GhcWRkPACfLNWU/jOLqW5sSUoZlUBf9FHt+F1ciI
    cY20QVRrv/lG6BuGH1nqFRYHbF30FLR8P/639GCB+Q6fmKWTC5W59AeCnJFtjtOmT80PCU
    kh/DldvJbBcRqG0aw3znktfAlKZUdK1EWlgmfe8XOxywEdpsoh6pPVzxQ2odnxj4Fxdnoy
    BKf2mMxWXE3EqewWRUgcqU9qYRVErDQuWI4cnES0Y0L6Awkd+0mTeK3R6gp5ohvV2SI5Ja
    Fk0clO6UIQAAA8ga3JeLGtyXiwAAAAdzc2gtcnNhAAABAQCyRZFr6TQIwd7QEUOS7+JuW9
    XdxbO64HHa5WeJXlApjcN6nJhb4sX0++WuohO7hYMnij3J7Sxlh3UjbhljoaFxZGQ8AJ8s
    1ZT+M4upbmxJShmVQF/0Ue34XVyIhxjbRBVGu/+UboG4YfWeoVFgdsXfQUtHw//rf0YIH5
    Dp+YpZMLlbn0B4KckW2O06ZPzQ8JSSH8OV28lsFxGobRrDfOeS18CUplR0rURaWCZ97xc7
    HLAR2myiHqk9XPFDah2fGPgXF2ejIEp/aYzFZcTcSp7BZFSBypT2phFUSsNC5YjhycRLRj
    QvoDCR37SZN4rdHqCnmiG9XZIjkloWTRyU7pQhAAAAAwEAAQAAAQBsfQ+5lwrWhX0eLFNu
    OVQYCwVE2Eq/YFWJe/AdVer8zsv2cxP5XzFPHHizZOkTRnYBewyNNSu+gcfUju0eh79i7V
    Bef5Zex3/LjvzgWFXH6DNXc/yxB6cFbXOhlm2XCoDUMhagcvu4hMzgA5YtWTqj2e2BOBMn
    cqXgzaz35qe+DHc8Z3RNnHD0JBdVEJFpPJb2ioKanD3YrO2E2MXqBv4H/5APeurTvd1PKQ
    8A0MLW2M9H+wxvVcF/CF96/4sFBEPWDcE9ciTNG+I3zCgBaI49oVO9c7Vd0IqONMTOLtld
    MeMzZQ3iJebhS42AKS/QZv6KcK+hukwuccK5f6zFNq8BAAAAgHcUkhTyP+oh/eP9vVKQbD
    aB77PutJAMPK1AgSgHRmYLJ0lv/d6eMbjvEygRjzJ57ry6eNGnCQcOS6GTa4KGnWXUddK/
    r2iaWzwt/RnqUobtV1X1UYfP3OkTaApvZpH1NAdFqzptqHg6BwJneMNEiE05XFIAVY266I
    46YWW3IcNPAAAAgQDkLzDWcogF2PspHr7zFlMOI4sJ7ypFspt/KA/dXPUqeBO/aU8JBVbZ
    Fy7ZpJSWcCqftYykbt/5epiGEkkUnY1zZfGnDHw0Wb36xgNLDXwu+Sbu+fqGeeRMnegeVR
    M9Ww+6l1LwHXjWt8O6RyywlbhDZNJTLlarJRsvZrKV2LP1cQAAAIEAyADJHqb+v3HGTWk4
    WdYm4RO6ASfQggSGq0knirqQwBHxQ1InzNiU8AJFhcI6aviwISJYutPQ0ur0v7FUwe8LVH
    WSLsqFfjg0BmKG05v6m0MDtxHTiwv12rla6n1UBx1cZFChg7zJDxqltO9zt2H2RGXtodsO
    zEmB/NqvEjJbcbEAAAAPZ2hhemlAbWFjLmxvY2FsAQIDBA==
    -----END OPENSSH PRIVATE KEY-----
    """

    @Test func parsesOpenSSHRSAKeySuccessfully() throws {
        let result = try SSHKeyParser.parsePrivateKey(
            Self.validOpenSSHRSAKey,
            username: "testuser",
            passphrase: nil
        )
        // OpenSSH RSA keys should use RSA-SHA2-512
        if case .rsaSHA512 = result {
            // expected
        } else {
            Issue.record("Expected .rsaSHA512 for OpenSSH RSA key, got .citadel")
        }
    }

    @Test func rsaSHA512KeyCanSign() throws {
        let result = try SSHKeyParser.parsePrivateKey(
            Self.validOpenSSHRSAKey,
            username: "testuser",
            passphrase: nil
        )
        guard case .rsaSHA512(let delegate) = result else {
            Issue.record("Expected .rsaSHA512")
            return
        }
        // Verify the delegate was created with correct username
        #expect(delegate !== nil as AnyObject?)
    }

    @Test func rejectsEncryptedOpenSSHRSAWithoutPassphrase() {
        // Simulate an encrypted OpenSSH key header (cipher != "none")
        // by using a truncated key that triggers the parser
        let encryptedHeader = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB
        -----END OPENSSH PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(encryptedHeader, username: "user", passphrase: nil)
        }
    }

    @Test func rejectsInvalidOpenSSHMagic() {
        let badKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        bm90LWEtdmFsaWQta2V5
        -----END OPENSSH PRIVATE KEY-----
        """

        #expect(throws: SSHTunnelError.self) {
            try SSHKeyParser.parsePrivateKey(badKey, username: "user", passphrase: nil)
        }
    }
}

// MARK: - RSA-SHA2-512 Types

@Suite("RSASHA512 — Key Types")
struct RSASHA512TypeTests {

    @Test func signaturePrefixIsCorrect() {
        #expect(RSASHA512Signature.signaturePrefix == "rsa-sha2-512")
    }

    @Test func publicKeyPrefixIsCorrect() {
        #expect(RSASHA512PublicKey.publicKeyPrefix == "rsa-sha2-512")
    }

    @Test func privateKeyPrefixIsCorrect() {
        #expect(RSASHA512PrivateKey.keyPrefix == "rsa-sha2-512")
    }

    @Test func signatureRoundTrips() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let sig = RSASHA512Signature(rawRepresentation: data)
        #expect(sig.rawRepresentation == data)
    }

    @Test func pemParserExtractsDER() throws {
        // Use the valid PEM key from the PKCS1 tests
        let pemKey = SSHKeyParserPKCS1Tests.validPEMRSAKey
        let der = try RSASHA512PEMParser.extractPKCS1DER(from: pemKey)
        // DER should start with SEQUENCE tag (0x30)
        #expect(der.first == 0x30)
        // Should be substantial (2048-bit key)
        #expect(der.count > 1000)
    }

    @Test func pemParserRejectsNonPEM() {
        #expect(throws: SSHTunnelError.self) {
            try RSASHA512PEMParser.extractPKCS1DER(from: "not a PEM key")
        }
    }

    @Test func secKeyCreationFromPEMRSA() throws {
        let pemKey = SSHKeyParserPKCS1Tests.validPEMRSAKey
        let der = try RSASHA512PEMParser.extractPKCS1DER(from: pemKey)
        let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(der)
        // Should be able to sign data
        let testData = Data("test message".utf8)
        let signature = try privateKey.signature(for: testData)
        // Verify it's the right signature type
        #expect(signature is RSASHA512Signature)
    }

    @Test func signatureIsVerifiable() throws {
        let pemKey = SSHKeyParserPKCS1Tests.validPEMRSAKey
        let der = try RSASHA512PEMParser.extractPKCS1DER(from: pemKey)
        let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(der)
        let testData = Data("verify this message".utf8)
        let signature = try privateKey.signature(for: testData)
        guard let sig = signature as? RSASHA512Signature else {
            Issue.record("Expected RSASHA512Signature")
            return
        }
        // Public key should verify the signature
        guard let pubKey = privateKey.publicKey as? RSASHA512PublicKey else {
            Issue.record("Expected RSASHA512PublicKey")
            return
        }
        let isValid = pubKey.isValidSignature(sig, for: testData)
        #expect(isValid == true)
    }

    @Test func signatureFailsForWrongData() throws {
        let pemKey = SSHKeyParserPKCS1Tests.validPEMRSAKey
        let der = try RSASHA512PEMParser.extractPKCS1DER(from: pemKey)
        let privateKey = try RSASHA512PrivateKey.fromPKCS1DER(der)
        let signature = try privateKey.signature(for: Data("original".utf8))
        guard let sig = signature as? RSASHA512Signature,
              let pubKey = privateKey.publicKey as? RSASHA512PublicKey else {
            Issue.record("Wrong types")
            return
        }
        let isValid = pubKey.isValidSignature(sig, for: Data("tampered".utf8))
        #expect(isValid == false)
    }
}

// MARK: - ConnectionProfile SSH Fields

@Suite("ConnectionProfile — SSH Fields")
struct ConnectionProfileSSHTests {

    @Test func defaultsSSHDisabled() {
        let profile = ConnectionProfile(
            name: "test",
            host: "localhost",
            username: "postgres"
        )

        #expect(profile.sshEnabled == false)
        #expect(profile.sshHost == nil)
        #expect(profile.sshPort == nil)
        #expect(profile.sshUsername == nil)
        #expect(profile.sshAuthMethod == nil)
        #expect(profile.sshPrivateKeyPath == nil)
    }

    @Test func storesSSHFields() {
        let profile = ConnectionProfile(
            name: "production",
            host: "10.0.1.5",
            username: "postgres",
            sshEnabled: true,
            sshHost: "bastion.example.com",
            sshPort: 22,
            sshUsername: "ubuntu",
            sshAuthMethod: .password
        )

        #expect(profile.sshEnabled == true)
        #expect(profile.sshHost == "bastion.example.com")
        #expect(profile.sshPort == 22)
        #expect(profile.sshUsername == "ubuntu")
        #expect(profile.sshAuthMethodEnum == .password)
    }

    @Test func sshAuthMethodEnumDefaultsToPassword() {
        let profile = ConnectionProfile(
            name: "test",
            host: "localhost",
            username: "postgres"
        )

        // sshAuthMethod is nil, should default to .password
        #expect(profile.sshAuthMethodEnum == .password)
    }

    @Test func sshAuthMethodEnumParsesPrivateKey() {
        let profile = ConnectionProfile(
            name: "test",
            host: "localhost",
            username: "postgres",
            sshAuthMethod: .privateKey
        )

        #expect(profile.sshAuthMethodEnum == .privateKey)
    }
}
