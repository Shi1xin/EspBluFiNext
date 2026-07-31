import Foundation

public struct BluFiRedactedFrame: Sendable, Equatable {
    public let type: UInt8
    public let control: BluFiFrameControl
    public let sequence: UInt8
    public let payloadLength: Int
    public let payload: String
    public let isSensitive: Bool
}

public enum BluFiDiagnosticRedactor {
    public static func redact(_ frame: BluFiFrame) -> BluFiRedactedFrame {
        let sensitive = isSensitive(frame)
        let payload = sensitive
            ? "<redacted: \(frame.data.count) bytes>"
            : frame.data.map { String(format: "%02X", $0) }.joined(separator: " ")

        return BluFiRedactedFrame(
            type: frame.type,
            control: frame.control,
            sequence: frame.sequence,
            payloadLength: frame.data.count,
            payload: payload,
            isSensitive: sensitive
        )
    }

    public static func isSensitive(_ frame: BluFiFrame) -> Bool {
        guard frame.package == .data else {
            return false
        }

        return switch BluFiProtocol.DataSubtype(rawValue: frame.subtype) {
        case .stationWiFiPassword,
             .softAPWiFiPassword,
             .username,
             .caCertification,
             .clientCertification,
             .serverCertification,
             .clientPrivateKey,
             .serverPrivateKey,
             .negotiateSecurity,
             .customData:
            true
        default:
            false
        }
    }
}
