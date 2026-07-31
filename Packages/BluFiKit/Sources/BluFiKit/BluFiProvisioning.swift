import Foundation

public enum BluFiOperationMode: UInt8, Sendable, CaseIterable {
    case none = 0x00
    case station = 0x01
    case softAP = 0x02
    case stationAndSoftAP = 0x03
}

public enum BluFiSoftAPSecurity: UInt8, Sendable, CaseIterable {
    case open = 0x00
    case wep = 0x01
    case wpa = 0x02
    case wpa2 = 0x03
    case wpaWPA2 = 0x04
}

public enum BluFiStationConnectionState: Sendable, Equatable {
    case connected
    case failed
    case connecting
    case noIP
    case unknown(UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .connected
        case 0x01: self = .failed
        case 0x02: self = .connecting
        case 0x03: self = .noIP
        default: self = .unknown(rawValue)
        }
    }
}

public struct BluFiSensitiveValue: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let bytes: [UInt8]

    public init(utf8 value: String) {
        bytes = Array(value.utf8)
    }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var byteCount: Int {
        bytes.count
    }

    public var description: String {
        "<redacted: \(bytes.count) bytes>"
    }

    public var debugDescription: String {
        description
    }
}

public struct BluFiStationProvisioning: Sendable, Equatable {
    public let ssid: String
    public let password: BluFiSensitiveValue

    public init(ssid: String, password: BluFiSensitiveValue) {
        self.ssid = ssid
        self.password = password
    }
}

public struct BluFiSoftAPProvisioning: Sendable, Equatable {
    public let security: BluFiSoftAPSecurity
    public let ssid: String?
    public let password: BluFiSensitiveValue?
    public let channel: UInt8?
    public let maximumConnections: UInt8?

    public init(
        security: BluFiSoftAPSecurity,
        ssid: String? = nil,
        password: BluFiSensitiveValue? = nil,
        channel: UInt8? = nil,
        maximumConnections: UInt8? = nil
    ) {
        self.security = security
        self.ssid = ssid
        self.password = password
        self.channel = channel
        self.maximumConnections = maximumConnections
    }
}

public struct BluFiProvisioningConfiguration: Sendable, Equatable {
    public let mode: BluFiOperationMode
    public let station: BluFiStationProvisioning?
    public let softAP: BluFiSoftAPProvisioning?
    /// Matches Espressif Android's default `mRequireAck = false` for data frames.
    /// The operation-mode control frame always requests an ACK.
    public let requiresAcknowledgement: Bool

    public init(
        mode: BluFiOperationMode,
        station: BluFiStationProvisioning? = nil,
        softAP: BluFiSoftAPProvisioning? = nil,
        requiresAcknowledgement: Bool = false
    ) {
        self.mode = mode
        self.station = station
        self.softAP = softAP
        self.requiresAcknowledgement = requiresAcknowledgement
    }

    func validate() throws {
        switch mode {
        case .none:
            return
        case .station:
            guard station != nil else { throw BluFiProvisioningError.stationConfigurationRequired }
        case .softAP:
            guard softAP != nil else { throw BluFiProvisioningError.softAPConfigurationRequired }
        case .stationAndSoftAP:
            guard station != nil else { throw BluFiProvisioningError.stationConfigurationRequired }
            guard softAP != nil else { throw BluFiProvisioningError.softAPConfigurationRequired }
        }

        if let station {
            guard !station.ssid.isEmpty else { throw BluFiProvisioningError.stationSSIDRequired }
        }
    }
}

public enum BluFiProvisioningError: Error, Sendable, Equatable, LocalizedError {
    case stationConfigurationRequired
    case softAPConfigurationRequired
    case stationSSIDRequired
    case malformedStatus
    case malformedWiFiList

    public var errorDescription: String? {
        switch self {
        case .stationConfigurationRequired:
            "Station provisioning requires an SSID and password configuration."
        case .softAPConfigurationRequired:
            "SoftAP provisioning requires a SoftAP configuration."
        case .stationSSIDRequired:
            "Station SSID must not be empty."
        case .malformedStatus:
            "BluFi Wi-Fi status payload is malformed."
        case .malformedWiFiList:
            "BluFi Wi-Fi scan payload is malformed."
        }
    }
}

public struct BluFiWiFiScanResult: Sendable, Equatable, Identifiable {
    public let ssidBytes: [UInt8]
    public let rssi: Int8

    public init(ssidBytes: [UInt8], rssi: Int8) {
        self.ssidBytes = ssidBytes
        self.rssi = rssi
    }

    public var id: String {
        "\(ssidBytes.map { String(format: "%02X", $0) }.joined())-\(rssi)"
    }

    public var ssid: String {
        String(bytes: ssidBytes, encoding: .utf8) ?? ssidBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public struct BluFiWiFiStatus: Sendable, Equatable {
    public let operationMode: BluFiOperationMode?
    public let stationState: BluFiStationConnectionState
    public let softAPConnectionCount: UInt8
    public let stationBSSID: String?
    public let stationSSID: String?
    public let stationMaximumRetry: UInt8?
    public let stationEndReason: UInt8?
    public let stationRSSI: Int8?
    public let stationPasswordPresent: Bool
    public let softAPSecurity: BluFiSoftAPSecurity?
    public let softAPSSID: String?
    public let softAPPasswordPresent: Bool
    public let softAPChannel: UInt8?
    public let softAPMaximumConnections: UInt8?
    public let unknownFieldTypes: [UInt8]

    public var hasIP: Bool {
        stationState == .connected
    }

    public var isConnecting: Bool {
        stationState == .connecting
    }

    public var failureReason: UInt8? {
        stationState == .failed ? stationEndReason : nil
    }
}

public enum BluFiProvisioningParser {
    public static func wiFiScanResults(from data: [UInt8]) throws -> [BluFiWiFiScanResult] {
        var index = 0
        var results: [BluFiWiFiScanResult] = []

        while index < data.count {
            let length = Int(data[index])
            index += 1
            guard length >= 1, index + length <= data.count else {
                throw BluFiProvisioningError.malformedWiFiList
            }

            let rssi = Int8(bitPattern: data[index])
            let ssid = Array(data[(index + 1) ..< (index + length)])
            results.append(BluFiWiFiScanResult(ssidBytes: ssid, rssi: rssi))
            index += length
        }

        return results
    }

    public static func wiFiStatus(from data: [UInt8]) throws -> BluFiWiFiStatus {
        guard data.count >= 3 else {
            throw BluFiProvisioningError.malformedStatus
        }

        let operationMode = BluFiOperationMode(rawValue: data[0])
        let stationState = BluFiStationConnectionState(rawValue: data[1])
        let softAPConnectionCount = data[2]

        var stationBSSID: String?
        var stationSSID: String?
        var stationMaximumRetry: UInt8?
        var stationEndReason: UInt8?
        var stationRSSI: Int8?
        var stationPasswordPresent = false
        var softAPSecurity: BluFiSoftAPSecurity?
        var softAPSSID: String?
        var softAPPasswordPresent = false
        var softAPChannel: UInt8?
        var softAPMaximumConnections: UInt8?
        var unknownFieldTypes: [UInt8] = []
        var index = 3

        while index < data.count {
            guard index + 2 <= data.count else {
                throw BluFiProvisioningError.malformedStatus
            }
            let type = data[index]
            let length = Int(data[index + 1])
            index += 2
            guard index + length <= data.count else {
                throw BluFiProvisioningError.malformedStatus
            }
            let value = Array(data[index ..< index + length])
            index += length

            switch BluFiProtocol.DataSubtype(rawValue: type) {
            case .stationWiFiBSSID:
                stationBSSID = value.map { String(format: "%02X", $0) }.joined(separator: ":")
            case .stationWiFiSSID:
                stationSSID = String(bytes: value, encoding: .utf8)
            case .stationWiFiPassword:
                stationPasswordPresent = true
            case .softAPAuthenticationMode:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                softAPSecurity = BluFiSoftAPSecurity(rawValue: value)
            case .softAPChannel:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                softAPChannel = value
            case .softAPMaximumConnectionCount:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                softAPMaximumConnections = value
            case .softAPWiFiPassword:
                softAPPasswordPresent = true
            case .softAPWiFiSSID:
                softAPSSID = String(bytes: value, encoding: .utf8)
            case .stationWiFiMaximumConnectionRetry:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                stationMaximumRetry = value
            case .stationWiFiConnectionEndReason:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                stationEndReason = value
            case .stationWiFiConnectionRSSI:
                guard let value = value.first else { throw BluFiProvisioningError.malformedStatus }
                stationRSSI = Int8(bitPattern: value)
            default:
                unknownFieldTypes.append(type)
            }
        }

        return BluFiWiFiStatus(
            operationMode: operationMode,
            stationState: stationState,
            softAPConnectionCount: softAPConnectionCount,
            stationBSSID: stationBSSID,
            stationSSID: stationSSID,
            stationMaximumRetry: stationMaximumRetry,
            stationEndReason: stationEndReason,
            stationRSSI: stationRSSI,
            stationPasswordPresent: stationPasswordPresent,
            softAPSecurity: softAPSecurity,
            softAPSSID: softAPSSID,
            softAPPasswordPresent: softAPPasswordPresent,
            softAPChannel: softAPChannel,
            softAPMaximumConnections: softAPMaximumConnections,
            unknownFieldTypes: unknownFieldTypes
        )
    }
}
