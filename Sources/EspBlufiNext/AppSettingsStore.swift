import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            "System Default"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .current
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }
}

enum BluFiPacketLengthPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case twentyBytes

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .twentyBytes:
            "20 bytes (ATT baseline)"
        }
    }

    var packetLength: Int? {
        switch self {
        case .automatic:
            nil
        case .twentyBytes:
            20
        }
    }
}

@MainActor
@Observable
final class AppSettingsStore {
    static let minimumLogSeverityKey = "settings.minimumLogSeverity.v1"

    private static let languageKey = "settings.language.v1"
    private static let namePrefixKey = "settings.namePrefix.v1"
    private static let commandTimeoutKey = "settings.commandTimeout.v1"
    private static let packetLengthKey = "settings.packetLength.v1"

    var language: AppLanguage {
        didSet { persist() }
    }

    var namePrefix: String {
        didSet { persist() }
    }

    var commandTimeoutSeconds: Int {
        didSet { persist() }
    }

    var packetLengthPolicy: BluFiPacketLengthPolicy {
        didSet { persist() }
    }

    var minimumLogSeverity: BluFiDiagnosticSeverity {
        didSet { persist() }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    var commandTimeout: Duration {
        .seconds(commandTimeoutSeconds)
    }

    var packetLength: Int? {
        packetLengthPolicy.packetLength
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        namePrefix = defaults.string(forKey: Self.namePrefixKey) ?? ""
        commandTimeoutSeconds = defaults.object(forKey: Self.commandTimeoutKey) as? Int ?? 15
        packetLengthPolicy = defaults.string(forKey: Self.packetLengthKey)
            .flatMap(BluFiPacketLengthPolicy.init(rawValue:)) ?? .automatic
        minimumLogSeverity = defaults.string(forKey: Self.minimumLogSeverityKey)
            .flatMap(BluFiDiagnosticSeverity.init(rawValue:)) ?? .debug
    }

    private func persist() {
        defaults.set(language.rawValue, forKey: Self.languageKey)
        defaults.set(namePrefix, forKey: Self.namePrefixKey)
        defaults.set(commandTimeoutSeconds, forKey: Self.commandTimeoutKey)
        defaults.set(packetLengthPolicy.rawValue, forKey: Self.packetLengthKey)
        defaults.set(minimumLogSeverity.rawValue, forKey: Self.minimumLogSeverityKey)
    }
}
