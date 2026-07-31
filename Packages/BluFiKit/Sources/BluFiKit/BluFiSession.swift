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
            try await transport.write(BluFiFrameCodec.encode(frame))
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
        await transport.disconnect()
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

            let frame = try BluFiFrameCodec.decode(packet)
            guard frame.sequence == expectedReadSequence else {
                throw BluFiProtocolError.unexpectedSequence(expected: expectedReadSequence, actual: frame.sequence)
            }
            expectedReadSequence &+= 1

            if frame.control.contains(.requireAcknowledgement) {
                try await sendAcknowledgement(for: frame.sequence)
            }
            if let reassembled = try reassembler.append(frame) {
                return reassembled
            }
        }
    }

    private func sendAcknowledgement(for receivedSequence: UInt8) async throws {
        let frame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .control, subtype: .ack),
            control: [],
            sequence: takeSendSequence(),
            data: [receivedSequence]
        )
        try await transport.write(BluFiFrameCodec.encode(frame))
    }

    private func takeSendSequence() -> UInt8 {
        defer { nextSendSequence &+= 1 }
        return nextSendSequence
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
