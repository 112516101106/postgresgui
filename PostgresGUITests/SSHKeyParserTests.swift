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
