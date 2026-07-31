import Foundation

public struct BluFiDeviceVersion: Sendable, Equatable {
    public let major: UInt8
    public let minor: UInt8

    public init(major: UInt8, minor: UInt8) {
        self.major = major
        self.minor = minor
    }

    public var value: UInt16 {
        (UInt16(major) << 8) | UInt16(minor)
    }

    public var securityVersion: BluFiProtocol.SecurityVersion {
        BluFiProtocol.securityVersion(forDeviceVersion: value)
    }
}

/// High-level command facade. SwiftUI and CoreBluetooth integrations only use
/// this API; packet framing and sequence handling remain inside BluFiSession.
public actor BluFiClient {
    private let session: BluFiSession

    public init(
        transport: any BluetoothTransport,
        packetLength: Int = BluFiProtocol.defaultPacketLength,
        commandTimeout: Duration = .seconds(15)
    ) async throws {
        session = try await BluFiSession(
            transport: transport,
            packetLength: packetLength,
            commandTimeout: commandTimeout
        )
    }

    public func requestDeviceVersion() async throws -> BluFiDeviceVersion {
        let response = try await session.request(
            type: BluFiProtocol.typeValue(package: .control, subtype: .getVersion),
            responseType: BluFiProtocol.typeValue(package: .data, subtype: .version)
        )
        guard response.data.count == 2 else {
            throw BluFiProtocolError.invalidPayload(description: "BluFi version response must contain exactly two bytes.")
        }
        return BluFiDeviceVersion(major: response.data[0], minor: response.data[1])
    }

    public func requestDeviceStatus() async throws -> [UInt8] {
        let response = try await session.request(
            type: BluFiProtocol.typeValue(package: .control, subtype: .getWiFiStatus),
            responseType: BluFiProtocol.typeValue(package: .data, subtype: .WiFiConnectionState)
        )
        return response.data
    }

    public func postCustomData(_ data: [UInt8], options: BluFiPostOptions = .init()) async throws {
        try await session.post(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            data: data,
            options: options
        )
    }

    public func closeConnection() async throws {
        try await session.post(
            type: BluFiProtocol.typeValue(package: .control, subtype: .closeConnection)
        )
        await session.close()
    }
}
