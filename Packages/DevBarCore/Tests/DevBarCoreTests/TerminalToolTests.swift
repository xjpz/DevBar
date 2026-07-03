import Crypto
import Foundation
import Testing
@testable import DevBarCore

@Test
func terminalShortcutKeysProduceExpectedBytes() {
    #expect(TerminalShortcutKey.escape.payload == Data([0x1B]))
    #expect(TerminalShortcutKey.tab.payload == Data([0x09]))
    #expect(TerminalShortcutKey.controlC.payload == Data([0x03]))
    #expect(TerminalShortcutKey.controlD.payload == Data([0x04]))
    #expect(TerminalShortcutKey.arrowUp.payload == Data([0x1B, 0x5B, 0x41]))
    #expect(TerminalShortcutKey.arrowDown.payload == Data([0x1B, 0x5B, 0x42]))
    #expect(TerminalShortcutKey.arrowRight.payload == Data([0x1B, 0x5B, 0x43]))
    #expect(TerminalShortcutKey.arrowLeft.payload == Data([0x1B, 0x5B, 0x44]))
    #expect(TerminalShortcutKey.controlA.payload == Data([0x01]))
    #expect(TerminalShortcutKey.controlE.payload == Data([0x05]))
    #expect(TerminalShortcutKey.controlL.payload == Data([0x0C]))
    #expect(TerminalShortcutKey.clear.payload == Data([0x0C]))
    #expect(TerminalShortcutKey.slash.payload == Data([0x2F]))
    #expect(TerminalShortcutKey.pipe.payload == Data([0x7C]))
}

@Test
func terminalDeleteBackwardProducesExpectedByte() {
    #expect(TerminalInputControl.deleteBackward == Data([0x7F]))
}

@Test
func terminalViewportCalculatorFitsIPhoneWidth() {
    let columns = TerminalViewportCalculator.columns(forWidth: 393)

    #expect(columns >= 40)
    #expect(columns <= 48)
}

@Test
func terminalViewportCalculatorClampsTinyWidth() {
    #expect(TerminalViewportCalculator.columns(forWidth: 80) == 24)
}

@Test
func terminalRemoteOSDetectorParsesUbuntuRelease() {
    let release = """
    NAME="Ubuntu"
    ID=ubuntu
    ID_LIKE=debian
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .ubuntu)
}

@Test
func terminalRemoteOSDetectorParsesDebianLikeRelease() {
    let release = """
    PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
    ID=debian
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .debian)
}

@Test
func terminalRemoteOSDetectorParsesRHELLikeRelease() {
    let release = """
    NAME="Amazon Linux"
    ID=amzn
    ID_LIKE="fedora rhel centos"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .centos)
}

@Test
func terminalRemoteOSDetectorParsesLinuxMintRelease() {
    let release = """
    NAME="Linux Mint"
    ID=linuxmint
    ID_LIKE="ubuntu debian"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .linuxMint)
}

@Test
func terminalRemoteOSDetectorParsesAlpineRelease() {
    let release = """
    NAME="Alpine Linux"
    ID=alpine
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .alpine)
}

@Test
func terminalRemoteOSDetectorParsesArchLikeRelease() {
    let release = """
    NAME="Garuda Linux"
    ID=garuda
    ID_LIKE=arch
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .garuda)
}

@Test
func terminalRemoteOSDetectorParsesRedHatRelease() {
    let release = """
    NAME="Red Hat Enterprise Linux"
    ID=rhel
    ID_LIKE="fedora"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .redHat)
}

@Test
func terminalRemoteOSDetectorParsesRockyRelease() {
    let release = """
    NAME="Rocky Linux"
    ID=rocky
    ID_LIKE="rhel centos fedora"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .rocky)
}

@Test
func terminalRemoteOSDetectorParsesAlmaLinuxRelease() {
    let release = """
    NAME="AlmaLinux"
    ID=almalinux
    ID_LIKE="rhel centos fedora"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .almaLinux)
}

@Test
func terminalRemoteOSDetectorParsesNixOSRelease() {
    let release = """
    NAME=NixOS
    ID=nixos
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .nixOS)
}

@Test
func terminalRemoteOSDetectorParsesPopOSRelease() {
    let release = """
    NAME="Pop!_OS"
    ID=pop
    ID_LIKE="ubuntu debian"
    """

    #expect(TerminalRemoteOSDetector.detect(from: release) == .popOS)
}

@Test
func terminalRemoteOSDetectorFallsBackToLinuxFromUname() {
    #expect(TerminalRemoteOSDetector.detect(from: "Linux\n") == .linux)
}

@Test
func terminalRemoteOSDetectorParsesFreeBSDFromUname() {
    #expect(TerminalRemoteOSDetector.detect(from: "FreeBSD\n") == .freeBSD)
}

@Test
func terminalRemoteOSDetectorParsesMacOSFromDarwinUname() {
    #expect(TerminalRemoteOSDetector.detect(from: "Darwin\n") == .macOS)
}

@Test
func terminalPromptSetupShowsOnlyHashInHomeAndPathElsewhere() {
    let command = TerminalPromptSetup.command

    #expect(command.contains("PS1="))
    #expect(command.contains("PROMPT="))
    #expect(command.contains("[ \"$p\" = \"$HOME\" ]"))
    #expect(command.contains("printf \"# \""))
    #expect(command.contains("printf \"%s# \" \"$p\""))
    #expect(command.contains("printf '\\033[H\\033[2J'"))
    #expect(command.contains("[H"))
    #expect(command.contains("[2J"))
    #expect(!command.contains("\u{0000}33"))
    #expect(!command.contains("> "))
}

@Test
func terminalOutputSanitizerRemovesANSIEscapeSequences() {
    let raw = "\u{001B}[01;34mDocuments\u{001B}[0m  \u{001B}[32mRUNNING_PID\u{001B}[0m"

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(sanitized == "Documents  RUNNING_PID")
}

@Test
func terminalOutputSanitizerRemovesOSCSequences() {
    let raw = "\u{001B}]0;root@example:~\u{0007}> "

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(sanitized == "> ")
}

@Test
func terminalOutputSanitizerNormalizesCRLFToSingleLineBreak() {
    let raw = "# \r\n# "

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(sanitized == "# \n# ")
}

@Test
func terminalOutputSanitizerAppliesClearScreenSequence() {
    var output = "setopt PROMPT_SUBST\nexport PS1=...\n"

    TerminalOutputSanitizer.append("\u{001B}[H\u{001B}[2J# ", to: &output)

    #expect(output == "# ")
}

@Test
func terminalOutputSanitizerRemovesPromptSetupEchoLines() {
    let raw = """
    qnyx@qnyx-19:~$ setopt PROMPT_SUBST 2>/dev/null
    qnyx@qnyx-19:~$ export PS1='$(p="$PWD"; if [ "$p" = "$HOME" ]; then printf "# "; else printf "%s# " "$p"; fi)'
    # export PROMPT='$(p="$PWD"; if [ "$p" = "$HOME" ]; then printf "# "; else printf "%s# " "$p"; fi)'
    #\u{20}
    """

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(!sanitized.contains("setopt PROMPT_SUBST"))
    #expect(!sanitized.contains("export PS1="))
    #expect(!sanitized.contains("export PROMPT="))
    #expect(sanitized == "# ")
}

@Test
func terminalOutputSanitizerRemovesLegacyNullEscapedPromptSetupEchoLine() {
    let raw = "# printf '\u{0000}33[H\u{0000}33[2J'\n# "

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(!sanitized.contains("printf"))
    #expect(!sanitized.contains("\u{0000}33"))
    #expect(sanitized == "# ")
}

@Test
func terminalOutputSanitizerAppliesBackspaceEchoWithinChunk() {
    let raw = "abc\u{0008} \u{0008}d"

    let sanitized = TerminalOutputSanitizer.sanitize(raw)

    #expect(sanitized == "abd")
}

@Test
func terminalOutputSanitizerAppliesBackspaceEchoAcrossChunks() {
    var output = "abc"

    TerminalOutputSanitizer.append("\u{0008} \u{0008}", to: &output)

    #expect(output == "ab")
}

@Test
func terminalServerValidationNormalizesValidPasswordConfiguration() throws {
    let draft = TerminalServerDraft(
        name: "  Prod  ",
        host: "  example.com  ",
        portText: " 22 ",
        username: " root ",
        authentication: .password(secret: " p@ss ")
    )

    let configuration = try TerminalServerValidator.validate(draft)

    #expect(configuration.name == "Prod")
    #expect(configuration.host == "example.com")
    #expect(configuration.port == 22)
    #expect(configuration.username == "root")
    #expect(configuration.authentication == .password(secret: "p@ss"))
}

@Test
func terminalServerValidationRejectsInvalidInputs() {
    #expect(throws: TerminalServerValidationError.missingHost) {
        try TerminalServerValidator.validate(.init(
            name: "Prod",
            host: " ",
            portText: "22",
            username: "root",
            authentication: .password(secret: "p")
        ))
    }

    #expect(throws: TerminalServerValidationError.invalidPort) {
        try TerminalServerValidator.validate(.init(
            name: "Prod",
            host: "example.com",
            portText: "70000",
            username: "root",
            authentication: .password(secret: "p")
        ))
    }

    #expect(throws: TerminalServerValidationError.missingUsername) {
        try TerminalServerValidator.validate(.init(
            name: "Prod",
            host: "example.com",
            portText: "22",
            username: " ",
            authentication: .password(secret: "p")
        ))
    }

    #expect(throws: TerminalServerValidationError.missingCredential) {
        try TerminalServerValidator.validate(.init(
            name: "Prod",
            host: "example.com",
            portText: "22",
            username: "root",
            authentication: .privateKey(secret: " ")
        ))
    }
}

@Test
func terminalCredentialStoreSavesLoadsAndDeletesSecrets() {
    let backend = InMemoryTerminalSecretBackend()
    let store = TerminalCredentialStore(backend: backend)
    let serverID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    let passwordKey = store.savePassword("secret", serverID: serverID)
    let keyRef = store.savePrivateKey("-----BEGIN KEY-----\nabc\n-----END KEY-----", serverID: serverID)
    let passphraseKey = store.savePrivateKeyPassphrase("phrase", serverID: serverID)

    #expect(passwordKey == "ios.terminal.server.00000000-0000-0000-0000-000000000123.password")
    #expect(keyRef == "ios.terminal.server.00000000-0000-0000-0000-000000000123.privateKey")
    #expect(passphraseKey == "ios.terminal.server.00000000-0000-0000-0000-000000000123.privateKeyPassphrase")
    #expect(store.loadSecret(forKey: passwordKey) == "secret")
    #expect(store.loadSecret(forKey: keyRef) == "-----BEGIN KEY-----\nabc\n-----END KEY-----")
    #expect(store.loadSecret(forKey: passphraseKey) == "phrase")

    store.deleteSecrets(serverID: serverID)

    #expect(store.loadSecret(forKey: passwordKey) == nil)
    #expect(store.loadSecret(forKey: keyRef) == nil)
    #expect(store.loadSecret(forKey: passphraseKey) == nil)
}

@Test
func terminalPrivateKeyParserAcceptsUnencryptedOpenSSHEd25519Key() throws {
    let privateKey = makeOpenSSHEd25519PrivateKey()

    _ = try TerminalPrivateKeyParser.parse(privateKey)
}

@Test
func terminalPrivateKeyParserAcceptsEncryptedOpenSSHEd25519KeyWithPassphrase() throws {
    _ = try TerminalPrivateKeyParser.parse(encryptedEd25519PrivateKey, passphrase: "devbar-passphrase")
}

@Test
func terminalPrivateKeyParserRequiresExplicitPassphraseForEncryptedKey() {
    #expect(throws: TerminalPrivateKeyParserError.missingPassphrase) {
        try TerminalPrivateKeyParser.parse(encryptedEd25519PrivateKey)
    }
}

@Test
func terminalPrivateKeyParserTreatsEmptyPassphraseAsExplicitPassphrase() {
    #expect(throws: TerminalPrivateKeyParserError.incorrectPassphrase) {
        try TerminalPrivateKeyParser.parse(encryptedEd25519PrivateKey, passphrase: "")
    }
}

@Test
func terminalPrivateKeyPassphrasePolicyIgnoresBlankInput() {
    #expect(TerminalPrivateKeyPassphrasePolicy.normalized("") == nil)
    #expect(TerminalPrivateKeyPassphrasePolicy.normalized("   ") == nil)
}

@Test
func terminalPrivateKeyPassphrasePolicyKeepsNonBlankInputVerbatim() {
    #expect(TerminalPrivateKeyPassphrasePolicy.normalized(" secret ") == " secret ")
}

@Test
func terminalPrivateKeyParserRejectsEncryptedOpenSSHKeyWithWrongPassphrase() {
    #expect(throws: TerminalPrivateKeyParserError.incorrectPassphrase) {
        try TerminalPrivateKeyParser.parse(encryptedEd25519PrivateKey, passphrase: "wrong-passphrase")
    }
}

@Test
func terminalPrivateKeyParserDetectsEncryptedOpenSSHKey() throws {
    #expect(try TerminalPrivateKeyParser.isEncrypted(encryptedEd25519PrivateKey))
    #expect(try !TerminalPrivateKeyParser.isEncrypted(makeOpenSSHEd25519PrivateKey()))
}

private let encryptedEd25519PrivateKey = """
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCmnG1Kej
fkHyYJlC+Vqp72AAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIGDsMObjh0xVpiPf
QAtYfLqiOu1uTiX90WoqGiigqs9JAAAAkPtMkSK7hSEm4z1TPB4IImL3exM25Kp+y88PEY
Av48tAZ7eNlr5sTObZIFnrJr/gxFVv9eUUcPUOAfddz2Rt39koGxfayPsXO1PvOGu5BmtJ
b0IHD1bBQunz9bb1bDvDENq/c7O7FeOP7L9iRX9fWAJtNRFDnY0gqBjocEtneqVfnoII4S
rGI88MAsMsfPHeEQ==
-----END OPENSSH PRIVATE KEY-----
"""

private func makeOpenSSHEd25519PrivateKey() -> String {
    makeOpenSSHPrivateKey()
}

private func makeOpenSSHPrivateKey(cipherName: String = "none", kdfName: String = "none") -> String {
    let seed = Data((0..<32).map(UInt8.init))
    let signingKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let publicKey = Data(signingKey.publicKey.rawRepresentation)

    var publicBlob = Data()
    publicBlob.appendSSHString("ssh-ed25519")
    publicBlob.appendSSHString(publicKey)

    var privateBlob = Data()
    privateBlob.appendUInt32(0xAABBCCDD)
    privateBlob.appendUInt32(0xAABBCCDD)
    privateBlob.appendSSHString("ssh-ed25519")
    privateBlob.appendSSHString(publicKey)
    privateBlob.appendSSHString(seed + publicKey)
    privateBlob.appendSSHString("devbar-test")
    privateBlob.append(contentsOf: [1, 2, 3, 4, 5])

    var container = Data("openssh-key-v1\0".utf8)
    container.appendSSHString(cipherName)
    container.appendSSHString(kdfName)
    container.appendSSHString(Data())
    container.appendUInt32(1)
    container.appendSSHString(publicBlob)
    container.appendSSHString(privateBlob)

    return """
    -----BEGIN OPENSSH PRIVATE KEY-----
    \(container.base64EncodedString())
    -----END OPENSSH PRIVATE KEY-----
    """
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ])
    }

    mutating func appendSSHString(_ value: String) {
        appendSSHString(Data(value.utf8))
    }

    mutating func appendSSHString(_ value: Data) {
        appendUInt32(UInt32(value.count))
        append(value)
    }
}
