import Foundation

enum BluFiPayloadFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case utf8
    case hex
    case base64

    var id: Self { self }

    var title: String {
        switch self {
        case .utf8:
            "UTF-8"
        case .hex:
            "Hex"
        case .base64:
            "Base64"
        }
    }

    var placeholder: String {
        switch self {
        case .utf8:
            "Enter text to send"
        case .hex:
            "DE AD BE EF"
        case .base64:
            "3q2+7w=="
        }
    }
}

enum BluFiPayloadCodecError: Error, LocalizedError, Equatable {
    case invalidHexCharacter(Character)
    case oddHexLength
    case invalidBase64

    var localizationKey: String {
        switch self {
        case .invalidHexCharacter:
            "Invalid hex character"
        case .oddHexLength:
            "Hex payload must contain pairs of characters."
        case .invalidBase64:
            "The payload is not valid Base64."
        }
    }

    var errorDescription: String? {
        switch self {
        case let .invalidHexCharacter(character):
            String(localized: "Invalid hex character") + ": \(character)"
        case .oddHexLength:
            String(localized: "Hex payload must contain pairs of characters.")
        case .invalidBase64:
            String(localized: "The payload is not valid Base64.")
        }
    }
}

enum BluFiPayloadCodec {
    static func decode(_ value: String, format: BluFiPayloadFormat) throws -> [UInt8] {
        switch format {
        case .utf8:
            return Array(value.utf8)
        case .hex:
            return try decodeHex(value)
        case .base64:
            guard let data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw BluFiPayloadCodecError.invalidBase64
            }
            return Array(data)
        }
    }

    static func encode(_ bytes: [UInt8], format: BluFiPayloadFormat) -> String {
        switch format {
        case .utf8:
            String(decoding: bytes, as: UTF8.self)
        case .hex:
            bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .base64:
            Data(bytes).base64EncodedString()
        }
    }

    private static func decodeHex(_ value: String) throws -> [UInt8] {
        let normalized = value
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .filter { !$0.isWhitespace && $0 != ":" && $0 != "-" && $0 != "," }

        guard normalized.count.isMultiple(of: 2) else {
            throw BluFiPayloadCodecError.oddHexLength
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let pair = normalized[index ..< nextIndex]
            guard let byte = UInt8(pair, radix: 16) else {
                throw BluFiPayloadCodecError.invalidHexCharacter(pair.first ?? "?")
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
}

enum BluFiConsoleDirection: String, Codable, Sendable {
    case sent
    case received

    var title: String {
        switch self {
        case .sent:
            "Sent"
        case .received:
            "Received"
        }
    }

    var symbolName: String {
        switch self {
        case .sent:
            "arrow.up.circle"
        case .received:
            "arrow.down.circle"
        }
    }
}

struct BluFiConsoleMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let direction: BluFiConsoleDirection
    let format: BluFiPayloadFormat
    let byteCount: Int
    let payload: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        direction: BluFiConsoleDirection,
        format: BluFiPayloadFormat,
        bytes: [UInt8]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.format = format
        byteCount = bytes.count
        payload = BluFiPayloadCodec.encode(bytes, format: format)
    }
}
