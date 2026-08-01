/// Protocol constants validated against Espressif's Android lib-blufi 2.5.1
/// and the BluFi protocol documentation.
///
/// This file is the phase-0 contract for frame construction and parsing. It
/// deliberately leaves transport, reliability, and cryptographic state to
/// later layers.
public enum BluFiProtocol {
    public static let serviceUUID = "0000FFFF-0000-1000-8000-00805F9B34FB"
    public static let writeCharacteristicUUID = "0000FF01-0000-1000-8000-00805F9B34FB"
    public static let notificationCharacteristicUUID = "0000FF02-0000-1000-8000-00805F9B34FB"
    public static let notificationDescriptorUUID = "00002902-0000-1000-8000-00805F9B34FB"

    public static let frameHeaderLength = 4
    public static let defaultPacketLength = 20
    public static let minimumPacketLength = 20
    public static let maximumPacketLength = 255
    public static let securityV2DeviceVersion: UInt16 = 0x0104

    public enum Package: UInt8, Sendable {
        case control = 0x00
        case data = 0x01
    }

    public enum ControlSubtype: UInt8, Sendable {
        case ack = 0x00
        case setSecurityMode = 0x01
        case setOperationMode = 0x02
        case connectWiFi = 0x03
        case disconnectWiFi = 0x04
        case getWiFiStatus = 0x05
        case deauthenticate = 0x06
        case getVersion = 0x07
        case closeConnection = 0x08
        case getWiFiList = 0x09
    }

    public enum DataSubtype: UInt8, Sendable {
        case negotiateSecurity = 0x00
        case stationWiFiBSSID = 0x01
        case stationWiFiSSID = 0x02
        case stationWiFiPassword = 0x03
        case softAPWiFiSSID = 0x04
        case softAPWiFiPassword = 0x05
        case softAPMaximumConnectionCount = 0x06
        case softAPAuthenticationMode = 0x07
        case softAPChannel = 0x08
        case username = 0x09
        case caCertification = 0x0A
        case clientCertification = 0x0B
        case serverCertification = 0x0C
        case clientPrivateKey = 0x0D
        case serverPrivateKey = 0x0E
        case WiFiConnectionState = 0x0F
        case version = 0x10
        case WiFiList = 0x11
        case error = 0x12
        case customData = 0x13
        case stationWiFiMaximumConnectionRetry = 0x14
        case stationWiFiConnectionEndReason = 0x15
        case stationWiFiConnectionRSSI = 0x16
    }

    public enum SecurityVersion: UInt8, Sendable {
        case v1 = 1
        case v2 = 2
    }

    /// The V1/V2 selection threshold follows Android lib-blufi 2.5.1:
    /// device version 0x0104 and newer selects V2.
    public static func securityVersion(forDeviceVersion deviceVersion: UInt16) -> SecurityVersion {
        deviceVersion >= securityV2DeviceVersion ? .v2 : .v1
    }

    public static func typeValue(package: Package, subtype: UInt8) -> UInt8 {
        ((subtype & 0x3F) << 2) | package.rawValue
    }

    public static func typeValue(package: Package, subtype: ControlSubtype) -> UInt8 {
        typeValue(package: package, subtype: subtype.rawValue)
    }

    public static func typeValue(package: Package, subtype: DataSubtype) -> UInt8 {
        typeValue(package: package, subtype: subtype.rawValue)
    }

    public static func package(from typeValue: UInt8) -> Package? {
        Package(rawValue: typeValue & 0x03)
    }

    public static func subtype(from typeValue: UInt8) -> UInt8 {
        (typeValue & 0xFC) >> 2
    }
}

public struct BluFiFrameControl: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let encrypted = Self(rawValue: 1 << 0)
    public static let checksum = Self(rawValue: 1 << 1)
    public static let inputDirection = Self(rawValue: 1 << 2)
    public static let requireAcknowledgement = Self(rawValue: 1 << 3)
    public static let fragmented = Self(rawValue: 1 << 4)
}
