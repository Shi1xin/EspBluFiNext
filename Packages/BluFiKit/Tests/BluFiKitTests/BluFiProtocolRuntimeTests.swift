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
}
