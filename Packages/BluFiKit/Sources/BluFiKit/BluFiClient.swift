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
        let options = await session.defaultCommandOptions()
        let response = try await session.request(
            type: BluFiProtocol.typeValue(package: .control, subtype: .getVersion),
            responseType: BluFiProtocol.typeValue(package: .data, subtype: .version),
            options: options
        )
        guard response.data.count == 2 else {
            throw BluFiProtocolError.invalidPayload(description: "BluFi version response must contain exactly two bytes.")
        }
        return BluFiDeviceVersion(major: response.data[0], minor: response.data[1])
    }

    public func requestDeviceStatus() async throws -> BluFiWiFiStatus {
        try await session.requestWiFiStatus()
    }

    public func requestDeviceWiFiScan() async throws -> [BluFiWiFiScanResult] {
        try await session.requestWiFiScan()
    }

    public func postCustomData(_ data: [UInt8], requiresAcknowledgement: Bool = false) async throws {
        let options = await session.defaultCommandOptions(requiresAcknowledgement: requiresAcknowledgement)
        try await session.post(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            data: data,
            options: options
        )
    }

    /// Waits for one unsolicited custom-data frame from the active device.
    /// The app serializes this operation with all other commands at its session
    /// controller boundary so a notification has a single reader.
    public func receiveCustomData() async throws -> [UInt8] {
        try await session.receiveCustomData()
    }

    @discardableResult
    public func negotiateSecurity(
        deviceVersion: BluFiDeviceVersion,
        override: BluFiSecurityOverride = .automatic,
        requiresAcknowledgement: Bool = false
    ) async throws -> BluFiProtocol.SecurityVersion {
        try await session.negotiateSecurity(
            deviceVersion: deviceVersion,
            override: override,
            requiresAcknowledgement: requiresAcknowledgement
        )
    }

    public func configure(
        _ configuration: BluFiProvisioningConfiguration,
        waitForStationStatus: Bool = false
    ) async throws -> BluFiWiFiStatus? {
        try await session.configure(
            configuration,
            waitForStationStatus: waitForStationStatus
        )
    }

    public func closeConnection() async throws {
        try await session.post(
            type: BluFiProtocol.typeValue(package: .control, subtype: .closeConnection)
        )
        await session.close()
    }
}
