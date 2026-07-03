import Foundation

public enum TerminalRemoteOSFamily: String, CaseIterable, Identifiable, Sendable {
    case auto
    case unknown
    case almaLinux = "almalinux"
    case android
    case alpine
    case arch
    case elementaryOS = "elementaryos"
    case feren
    case freeBSD = "freebsd"
    case garuda
    case haiku
    case kali
    case linux
    case linuxMint = "linuxmint"
    case macOS = "macos"
    case manjaro
    case nixOS = "nixos"
    case popOS = "popos"
    case redHat = "redhat"
    case rocky
    case serenityOS = "serenityos"
    case windows
    case ubuntu
    case debian
    case centos
    case fedora
    case gentoo
    case openSUSE = "opensuse"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            return "Auto Detect"
        case .unknown:
            return "Unknown"
        case .almaLinux:
            return "AlmaLinux"
        case .android:
            return "Android"
        case .alpine:
            return "Alpine"
        case .arch:
            return "Arch Linux"
        case .elementaryOS:
            return "Elementary OS"
        case .feren:
            return "Feren OS"
        case .freeBSD:
            return "FreeBSD"
        case .garuda:
            return "Garuda"
        case .haiku:
            return "Haiku"
        case .kali:
            return "Kali Linux"
        case .linux:
            return "Linux"
        case .linuxMint:
            return "Linux Mint"
        case .macOS:
            return "macOS"
        case .manjaro:
            return "Manjaro"
        case .nixOS:
            return "NixOS"
        case .popOS:
            return "Pop!_OS"
        case .redHat:
            return "Red Hat"
        case .rocky:
            return "Rocky Linux"
        case .serenityOS:
            return "SerenityOS"
        case .windows:
            return "Windows"
        case .ubuntu:
            return "Ubuntu"
        case .debian:
            return "Debian"
        case .centos:
            return "CentOS"
        case .fedora:
            return "Fedora"
        case .gentoo:
            return "Gentoo"
        case .openSUSE:
            return "openSUSE"
        }
    }
}

public enum TerminalRemoteOSDetector {
    public static let probeCommand = "cat /etc/os-release 2>/dev/null || uname -s"

    public static func detect(from output: String) -> TerminalRemoteOSFamily {
        let fields = parseOSRelease(output)
        let id = normalized(fields["ID"])
        let idLike = normalized(fields["ID_LIKE"])

        if let exact = family(for: id) {
            return exact
        }

        let candidates = idLike.split(separator: " ").map(String.init)
        if candidates.contains(where: { $0 == "rhel" || $0 == "centos" }) {
            return .centos
        }
        if let matched = candidates.compactMap(family(for:)).first {
            return matched
        }

        return fallbackFamily(from: output)
    }

    private static func family(for token: String) -> TerminalRemoteOSFamily? {
        switch token {
        case "almalinux", "alma":
            return .almaLinux
        case "android":
            return .android
        case "alpine":
            return .alpine
        case "arch", "archlinux":
            return .arch
        case "elementary", "elementaryos":
            return .elementaryOS
        case "feren", "ferenos":
            return .feren
        case "freebsd":
            return .freeBSD
        case "garuda":
            return .garuda
        case "haiku":
            return .haiku
        case "kali", "kalilinux":
            return .kali
        case "linuxmint", "mint":
            return .linuxMint
        case "macos", "darwin":
            return .macOS
        case "manjaro":
            return .manjaro
        case "nixos":
            return .nixOS
        case "pop", "popos":
            return .popOS
        case "redhat", "rhel":
            return .redHat
        case "rocky":
            return .rocky
        case "serenity", "serenityos":
            return .serenityOS
        case "windows", "msys", "mingw", "cygwin":
            return .windows
        case "ubuntu":
            return .ubuntu
        case "debian":
            return .debian
        case "centos", "amzn":
            return .centos
        case "fedora":
            return .fedora
        case "gentoo":
            return .gentoo
        case "opensuse", "opensuse-leap", "opensuse-tumbleweed", "sles", "suse":
            return .openSUSE
        default:
            return nil
        }
    }

    private static func fallbackFamily(from output: String) -> TerminalRemoteOSFamily {
        let normalizedOutput = output.lowercased()
        if normalizedOutput.contains("darwin") {
            return .macOS
        }
        if normalizedOutput.contains("freebsd") {
            return .freeBSD
        }
        if normalizedOutput.contains("haiku") {
            return .haiku
        }
        if normalizedOutput.contains("serenity") {
            return .serenityOS
        }
        if normalizedOutput.contains("windows") {
            return .windows
        }
        if normalizedOutput.contains("android") {
            return .android
        }
        if normalizedOutput.contains("linux") {
            return .linux
        }
        return .unknown
    }

    private static func parseOSRelease(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = unquote(value)
        }

        return fields
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
