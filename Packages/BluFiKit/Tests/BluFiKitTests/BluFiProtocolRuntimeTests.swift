import XCTest
@testable import BluFiKit

final class BluFiProtocolRuntimeTests: XCTestCase {
    func testCRC16MatchesAndroidLibBlufiVector() {
        XCTAssertEqual(BluFiCRC16.calculate([0, 3, 1, 2, 3]), 0x141E)
    }

    func testFrameCodecUsesLittleEndianChecksumAfterPlaintextData() throws {
        let frame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            control: [.checksum],
            sequence: 0,
            data: [1, 2, 3]
        )

        let encoded = try BluFiFrameCodec.encode(frame)
        XCTAssertEqual(encoded, [0x4D, 0x02, 0x00, 0x03, 0x01, 0x02, 0x03, 0x1E, 0x14])
        XCTAssertEqual(try BluFiFrameCodec.decode(encoded), frame)
    }

    func testFrameCodecRejectsChecksumMismatch() throws {
        let packet = [UInt8](arrayLiteral: 0x4D, 0x02, 0x00, 0x03, 0x01, 0x02, 0x03, 0x00, 0x14)

        XCTAssertThrowsError(try BluFiFrameCodec.decode(packet)) { error in
            XCTAssertEqual(
                error as? BluFiProtocolError,
                .invalidChecksum(expected: 0x141E, actual: 0x1400)
            )
        }
    }

    func testFragmenterMatchesTwentyBytePacketLayoutAndReassembles() throws {
        let data = Array(0 ..< 40).map(UInt8.init)
        var sequence: UInt8 = 0
        let frames = try BluFiFragmenter.frames(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            control: [],
            data: data,
            packetLength: 20
        ) {
            defer { sequence &+= 1 }
            return sequence
        }

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(frames[0].data, [40, 0] + Array(0 ..< 14))
        XCTAssertEqual(frames[1].data, [40, 0] + Array(14 ..< 28))
        XCTAssertEqual(frames[2].data, Array(28 ..< 40))
        XCTAssertTrue(frames[0].control.contains(.fragmented))
        XCTAssertTrue(frames[1].control.contains(.fragmented))
        XCTAssertFalse(frames[2].control.contains(.fragmented))

        var reassembler = BluFiFragmentReassembler()
        XCTAssertNil(try reassembler.append(frames[0]))
        XCTAssertNil(try reassembler.append(frames[1]))
        XCTAssertEqual(try reassembler.append(frames[2])?.data, data)
    }

    func testClientRequestWritesGetVersion() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))

        let versionTask = Task {
            try await client.requestDeviceVersion()
        }

        let versionResponse = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .version),
            control: [.inputDirection],
            sequence: 0,
            data: [1, 3]
        )
        await transport.receive(try BluFiFrameCodec.encode(versionResponse))

        let version = try await versionTask.value
        XCTAssertEqual(version, BluFiDeviceVersion(major: 1, minor: 3))

        let writes = await transport.writtenPackets()
        XCTAssertEqual(writes[0], [0x1C, 0x00, 0x00, 0x00])
    }

    func testPostWaitsForAcknowledgementOfEachFragment() async throws {
        let transport = BluFiFakeTransport()
        let session = try await BluFiSession(transport: transport, commandTimeout: .seconds(1))

        let postTask = Task {
            try await session.post(
                type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
                data: Array(repeating: 0xA5, count: 17),
                options: .init(requiresAcknowledgement: true)
            )
        }

        let firstAck = BluFiFrame(type: 0x00, control: [.inputDirection], sequence: 0, data: [0])
        let secondAck = BluFiFrame(type: 0x00, control: [.inputDirection], sequence: 1, data: [1])
        await transport.receive(try BluFiFrameCodec.encode(firstAck))
        await transport.receive(try BluFiFrameCodec.encode(secondAck))
        try await postTask.value

        let writes = await transport.writtenPackets()
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.map { $0[2] }, [0, 1])
    }

    func testClientReceivesUnsolicitedCustomData() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))
        let receiveTask = Task {
            try await client.receiveCustomData()
        }

        let response = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            control: [.inputDirection],
            sequence: 0,
            data: [0xDE, 0xAD, 0xBE, 0xEF]
        )
        await transport.receive(try BluFiFrameCodec.encode(response))

        let received = try await receiveTask.value
        XCTAssertEqual(received, [0xDE, 0xAD, 0xBE, 0xEF])
    }

    func testClientPropagatesInvalidCRCFromResponse() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))
        let statusTask = Task {
            try await client.requestDeviceStatus()
        }

        let response = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .WiFiConnectionState),
            control: [.inputDirection, .checksum],
            sequence: 0,
            data: [0x01]
        )
        var packet = try BluFiFrameCodec.encode(response)
        packet[packet.count - 1] ^= 0xFF
        await transport.receive(packet)

        do {
            _ = try await statusTask.value
            XCTFail("Expected the invalid CRC to fail the request.")
        } catch let error as BluFiProtocolError {
            guard case .invalidChecksum = error else {
                XCTFail("Expected invalidChecksum, received \(error).")
                return
            }
        }
    }

    func testClientRejectsUnexpectedResponseSequence() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))
        let versionTask = Task {
            try await client.requestDeviceVersion()
        }

        let response = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .version),
            control: [.inputDirection],
            sequence: 1,
            data: [1, 3]
        )
        await transport.receive(try BluFiFrameCodec.encode(response))

        do {
            _ = try await versionTask.value
            XCTFail("Expected the unexpected sequence to fail the request.")
        } catch let error as BluFiProtocolError {
            XCTAssertEqual(error, .unexpectedSequence(expected: 0, actual: 1))
        }
    }

    func testSessionReportsAcknowledgementTimeout() async throws {
        let transport = BluFiFakeTransport()
        let session = try await BluFiSession(transport: transport, commandTimeout: .milliseconds(100))

        do {
            try await session.post(
                type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
                data: [0xA5],
                options: .init(requiresAcknowledgement: true)
            )
            XCTFail("Expected the missing acknowledgement to time out.")
        } catch let error as BluFiProtocolError {
            XCTAssertEqual(error, .acknowledgementTimeout(sequence: 0))
        }
    }

    func testSessionPropagatesTransportDisconnect() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))
        let versionTask = Task {
            try await client.requestDeviceVersion()
        }

        await transport.finish()

        do {
            _ = try await versionTask.value
            XCTFail("Expected the closed transport to fail the request.")
        } catch let error as BluFiProtocolError {
            XCTAssertEqual(error, .transportClosed)
        }
    }

    func testFragmentReassemblerReportsInterruptedPayload() throws {
        let type = BluFiProtocol.typeValue(package: .data, subtype: .customData)
        var reassembler = BluFiFragmentReassembler()

        let firstFragment = BluFiFrame(
            type: type,
            control: [.fragmented],
            sequence: 0,
            data: [5, 0, 0x01, 0x02]
        )
        XCTAssertNil(try reassembler.append(firstFragment))

        let interruptedPayload = BluFiFrame(
            type: type,
            control: [],
            sequence: 1,
            data: [0x03]
        )
        XCTAssertThrowsError(try reassembler.append(interruptedPayload)) { error in
            XCTAssertEqual(error as? BluFiProtocolError, .fragmentLengthMismatch(expected: 5, actual: 3))
        }
    }
}
