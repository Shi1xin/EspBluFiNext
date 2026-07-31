import Foundation

public struct BluFiPostOptions: Sendable, Equatable {
    public var encrypted: Bool
    public var checksum: Bool
    public var requiresAcknowledgement: Bool

    public init(encrypted: Bool = false, checksum: Bool = false, requiresAcknowledgement: Bool = false) {
        self.encrypted = encrypted
        self.checksum = checksum
        self.requiresAcknowledgement = requiresAcknowledgement
    }

    var frameControl: BluFiFrameControl {
        var control: BluFiFrameControl = []
        if encrypted {
            control.insert(.encrypted)
        }
        if checksum {
            control.insert(.checksum)
        }
        if requiresAcknowledgement {
            control.insert(.requireAcknowledgement)
        }
        return control
    }
}

/// Serializes all frame writes and notifications for one active BluFi device.
/// A session starts its send and receive sequence counters at zero, matching
/// Espressif's Android lib-blufi 2.5.1 implementation.
public actor BluFiSession {
    private let transport: any BluetoothTransport
    private let packetLength: Int
    private let commandTimeout: Duration
    private var nextSendSequence: UInt8 = 0
    private var expectedReadSequence: UInt8 = 0
    private var reassembler = BluFiFragmentReassembler()
    private var deferredFrames: [BluFiFrame] = []
    private var security: BluFiSecurityContext?

    public init(
        transport: any BluetoothTransport,
        packetLength: Int = BluFiProtocol.defaultPacketLength,
        commandTimeout: Duration = .seconds(15)
    ) async throws {
        guard (BluFiProtocol.minimumPacketLength ... BluFiProtocol.maximumPacketLength).contains(packetLength) else {
            throw BluFiProtocolError.packetLengthOutOfRange(packetLength)
        }

        self.transport = transport
        self.packetLength = packetLength
        self.commandTimeout = commandTimeout
    }

    public func post(
        type: UInt8,
        data: [UInt8] = [],
        options: BluFiPostOptions = .init()
    ) async throws {
        var sequence = nextSendSequence
        let frames = try BluFiFragmenter.frames(
            type: type,
            control: options.frameControl,
            data: data,
            packetLength: packetLength
        ) {
            defer { sequence &+= 1 }
            return sequence
        }
        nextSendSequence = sequence

        for frame in frames {
            let activeSecurity = security
            let packet = try BluFiFrameCodec.encode(frame) { data, sequence in
                guard let activeSecurity else {
                    throw BluFiProtocolError.securityRequired
                }
                return try activeSecurity.encrypt(data, sequence: sequence)
            }
            try await transport.write(packet)
            if options.requiresAcknowledgement {
                try await waitForAcknowledgement(of: frame.sequence)
            }
        }
    }

    public func request(
        type: UInt8,
        responseType: UInt8,
        data: [UInt8] = [],
        options: BluFiPostOptions = .init()
    ) async throws -> BluFiFrame {
        try await post(type: type, data: data, options: options)
        let timeout = commandTimeout
        return try await Self.withTimeout(timeout, error: .responseTimeout(type: responseType)) { [self] in
            try await receiveFrame(matchingType: responseType)
        }
    }

    public func close() async {
        security = nil
        await transport.disconnect()
    }

    public func requestWiFiScan() async throws -> [BluFiWiFiScanResult] {
        let response = try await request(
            type: BluFiProtocol.typeValue(package: .control, subtype: .getWiFiList),
            responseType: BluFiProtocol.typeValue(package: .data, subtype: .WiFiList),
            options: defaultCommandOptions()
        )
        return try BluFiProvisioningParser.wiFiScanResults(from: response.data)
    }

    public func requestWiFiStatus() async throws -> BluFiWiFiStatus {
        let response = try await request(
            type: BluFiProtocol.typeValue(package: .control, subtype: .getWiFiStatus),
            responseType: BluFiProtocol.typeValue(package: .data, subtype: .WiFiConnectionState),
            options: defaultCommandOptions()
        )
        return try BluFiProvisioningParser.wiFiStatus(from: response.data)
    }

    public func configure(_ configuration: BluFiProvisioningConfiguration) async throws {
        try configuration.validate()

        try await post(
            type: BluFiProtocol.typeValue(package: .control, subtype: .setOperationMode),
            data: [configuration.mode.rawValue],
            options: defaultCommandOptions(requiresAcknowledgement: true)
        )

        if let station = configuration.station {
            try await postProvisioningData(
                subtype: .stationWiFiSSID,
                data: Array(station.ssid.utf8),
                requiresAcknowledgement: configuration.requiresAcknowledgement
            )
            try await provisioningInterFrameDelay()
            try await postProvisioningData(
                subtype: .stationWiFiPassword,
                data: station.password.bytes,
                requiresAcknowledgement: configuration.requiresAcknowledgement
            )
            try await provisioningInterFrameDelay()
            try await post(
                type: BluFiProtocol.typeValue(package: .control, subtype: .connectWiFi),
                options: BluFiPostOptions(requiresAcknowledgement: configuration.requiresAcknowledgement)
            )
        }

        if let softAP = configuration.softAP {
            if let ssid = softAP.ssid, !ssid.isEmpty {
                try await postProvisioningData(
                    subtype: .softAPWiFiSSID,
                    data: Array(ssid.utf8),
                    requiresAcknowledgement: configuration.requiresAcknowledgement
                )
                try await provisioningInterFrameDelay()
            }
            if let password = softAP.password, password.byteCount > 0 {
                try await postProvisioningData(
                    subtype: .softAPWiFiPassword,
                    data: password.bytes,
                    requiresAcknowledgement: configuration.requiresAcknowledgement
                )
                try await provisioningInterFrameDelay()
            }
            if let channel = softAP.channel, channel > 0 {
                try await postProvisioningData(
                    subtype: .softAPChannel,
                    data: [channel],
                    requiresAcknowledgement: configuration.requiresAcknowledgement
                )
                try await provisioningInterFrameDelay()
            }
            if let maximumConnections = softAP.maximumConnections, maximumConnections > 0 {
                try await postProvisioningData(
                    subtype: .softAPMaximumConnectionCount,
                    data: [maximumConnections],
                    requiresAcknowledgement: configuration.requiresAcknowledgement
                )
                try await provisioningInterFrameDelay()
            }
            try await postProvisioningData(
                subtype: .softAPAuthenticationMode,
                data: [softAP.security.rawValue],
                requiresAcknowledgement: configuration.requiresAcknowledgement
            )
        }
    }

    public func defaultCommandOptions(requiresAcknowledgement: Bool = false) -> BluFiPostOptions {
        guard security != nil else {
            return BluFiPostOptions(requiresAcknowledgement: requiresAcknowledgement)
        }
        return BluFiPostOptions(
            encrypted: true,
            checksum: true,
            requiresAcknowledgement: requiresAcknowledgement
        )
    }

    @discardableResult
    public func negotiateSecurity(
        deviceVersion: BluFiDeviceVersion,
        override: BluFiSecurityOverride = .automatic,
        requiresAcknowledgement: Bool = false
    ) async throws -> BluFiProtocol.SecurityVersion {
        security = nil
        let version = override.resolve(deviceVersion: deviceVersion)
        let negotiator = try BluFiSecurityNegotiator(version: version)
        let negotiationType = BluFiProtocol.typeValue(package: .data, subtype: .negotiateSecurity)
        let options = BluFiPostOptions(requiresAcknowledgement: requiresAcknowledgement)

        try await post(type: negotiationType, data: negotiator.totalLengthPayload, options: options)
        try await securityNegotiationInterFrameDelay()
        try await post(type: negotiationType, data: negotiator.parameterPayload, options: options)
        let response = try await Self.withTimeout(commandTimeout, error: .responseTimeout(type: negotiationType)) { [self] in
            try await receiveFrame(matchingType: negotiationType)
        }
        let context = try negotiator.makeSecurityContext(devicePublicKey: response.data)

        try await post(
            type: BluFiProtocol.typeValue(package: .control, subtype: .setSecurityMode),
            data: [0b0000_0011],
            options: BluFiPostOptions(checksum: true, requiresAcknowledgement: requiresAcknowledgement)
        )
        security = context
        return version
    }

    private func waitForAcknowledgement(of sequence: UInt8) async throws {
        let timeout = commandTimeout
        try await Self.withTimeout(timeout, error: .acknowledgementTimeout(sequence: sequence)) { [self] in
            try await receiveAcknowledgement(of: sequence)
        }
    }

    private func receiveAcknowledgement(of sequence: UInt8) async throws {
        while true {
            let frame = try await nextFrame()
            guard frame.type == BluFiProtocol.typeValue(package: .control, subtype: .ack) else {
                deferredFrames.append(frame)
                continue
            }
            guard frame.data.first == sequence else {
                deferredFrames.append(frame)
                continue
            }
            return
        }
    }

    private func postProvisioningData(
        subtype: BluFiProtocol.DataSubtype,
        data: [UInt8],
        requiresAcknowledgement: Bool
    ) async throws {
        try await post(
            type: BluFiProtocol.typeValue(package: .data, subtype: subtype),
            data: data,
            options: defaultCommandOptions(requiresAcknowledgement: requiresAcknowledgement)
        )
    }

    private func provisioningInterFrameDelay() async throws {
        try await Task.sleep(for: .milliseconds(10))
    }

    /// Espressif's Android client pauses between the negotiation length and
    /// PGK payloads so the device can allocate its security buffer.
    private func securityNegotiationInterFrameDelay() async throws {
        try await Task.sleep(for: .milliseconds(10))
    }

    private func receiveFrame(matchingType type: UInt8) async throws -> BluFiFrame {
        if let index = deferredFrames.firstIndex(where: { $0.type == type }) {
            return deferredFrames.remove(at: index)
        }

        while true {
            let frame = try await nextFrame()
            if frame.type == type {
                return frame
            }
            deferredFrames.append(frame)
        }
    }

    private func nextFrame() async throws -> BluFiFrame {
        while true {
            guard let packet = try await transport.nextPacket() else {
                throw BluFiProtocolError.transportClosed
            }

            let activeSecurity = security
            let frame = try BluFiFrameCodec.decode(packet) { data, sequence in
                guard let activeSecurity else {
                    throw BluFiProtocolError.securityRequired
                }
                return try activeSecurity.decrypt(data, sequence: sequence)
            }
            guard frame.sequence == expectedReadSequence else {
                throw BluFiProtocolError.unexpectedSequence(expected: expectedReadSequence, actual: frame.sequence)
            }
            expectedReadSequence &+= 1

            if let reassembled = try reassembler.append(frame) {
                return reassembled
            }
        }
    }

    private nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        error: BluFiProtocolError,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: timeout)
                throw error
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw BluFiProtocolError.transportClosed
            }
            return result
        }
    }
}
