import XCTest
@testable import BluFiKit

final class BluFiSecurityTests: XCTestCase {
    func testV1NegotiationPayloadMatchesAndroidPGKLayout() throws {
        let negotiator = try BluFiSecurityNegotiator(version: .v1, privateKeyMaterial: [2])

        XCTAssertEqual(negotiator.totalLengthPayload, [0x00, 0x01, 0x07])
        XCTAssertEqual(negotiator.parameterPayload.count, 264)
        XCTAssertEqual(negotiator.parameterPayload[0], 0x01)
        XCTAssertEqual(Array(negotiator.parameterPayload[1 ..< 3]), [0x00, 0x80])
        XCTAssertEqual(Array(negotiator.parameterPayload[131 ..< 134]), [0x00, 0x01, 0x02])
        XCTAssertEqual(Array(negotiator.parameterPayload[134 ..< 136]), [0x00, 0x80])
        XCTAssertEqual(negotiator.publicKey.suffix(1), [0x04])
        XCTAssertEqual(negotiator.publicKey.count, 128)
    }

    func testV2NegotiationUses3072BitPaddedPublicKey() throws {
        let negotiator = try BluFiSecurityNegotiator(version: .v2, privateKeyMaterial: [2])

        XCTAssertEqual(negotiator.totalLengthPayload, [0x00, 0x03, 0x07])
        XCTAssertEqual(negotiator.parameterPayload.count, 776)
        XCTAssertEqual(negotiator.publicKey.count, 384)
        XCTAssertEqual(negotiator.publicKey.suffix(1), [0x04])
    }

    func testV1DerivesSharedSecretAndEncryptsWithSequenceIV() throws {
        let negotiator = try BluFiSecurityNegotiator(version: .v1, privateKeyMaterial: [2])
        let context = try negotiator.makeSecurityContext(devicePublicKey: [8])
        let plaintext = hexadecimal("000102030405060708090a0b0c0d0e0f")

        XCTAssertEqual(
            try context.encrypt(plaintext, sequence: 0),
            hexadecimal("da1574a931b71fa3724471f901d253dd")
        )
        XCTAssertEqual(
            try context.decrypt(hexadecimal("da1574a931b71fa3724471f901d253dd"), sequence: 0),
            plaintext
        )
    }

    func testV1CFBMatchesNISTVector() throws {
        let context = try BluFiSecurityContext(version: .v1, sharedSecret: Array("BluFi-v1-shared-secret".utf8))
        let plaintext = hexadecimal("0102030405060708090a0b0c0d0e0f10")

        XCTAssertEqual(
            try context.encrypt(plaintext, sequence: 7),
            hexadecimal("2e66a891ec357fba00f276d31aacc2f7")
        )
    }

    func testEncryptedFrameKeepsCRCOverPlaintext() throws {
        let sharedSecret = Array("frame-round-trip-secret".utf8)
        let sender = try BluFiSecurityContext(version: .v1, sharedSecret: sharedSecret)
        let receiver = try BluFiSecurityContext(version: .v1, sharedSecret: sharedSecret)
        let frame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            control: [.encrypted, .checksum],
            sequence: 9,
            data: [0xCA, 0xFE]
        )

        let packet = try BluFiFrameCodec.encode(frame) { data, sequence in
            try sender.encrypt(data, sequence: sequence)
        }
        XCTAssertNotEqual(Array(packet[4 ..< 6]), frame.data)
        XCTAssertEqual(
            try BluFiFrameCodec.decode(packet) { data, sequence in
                try receiver.decrypt(data, sequence: sequence)
            },
            frame
        )
    }

    func testV2CTRMaintainsSeparateDirectionalStreams() throws {
        let context = try BluFiSecurityContext(version: .v2, sharedSecret: Array("BluFi-v2-shared-secret".utf8))
        let outbound = hexadecimal("0102030405060708090a0b0c0d0e0f10111213")
        let inboundCiphertext = hexadecimal("37946dbc0f5de3c42fec37e88a13422f")

        let first = try context.encrypt(Array(outbound.prefix(8)), sequence: 0)
        let second = try context.encrypt(Array(outbound.dropFirst(8)), sequence: 1)
        XCTAssertEqual(
            first + second,
            hexadecimal("89d9d41ca64fe22e5f8232b2f217c1560d618d")
        )
        XCTAssertEqual(
            try context.decrypt(inboundCiphertext, sequence: 0),
            hexadecimal("2122232425262728292a2b2c2d2e2f30")
        )
    }

    func testClientSecurityNegotiationActivatesEncryptedChecksumFrames() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(2))
        let negotiationTask = Task {
            try await client.negotiateSecurity(
                deviceVersion: BluFiDeviceVersion(major: 1, minor: 3),
                override: .v1
            )
        }

        let devicePublicKey = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .negotiateSecurity),
            control: [.inputDirection],
            sequence: 0,
            data: [8]
        )
        await transport.receive(try BluFiFrameCodec.encode(devicePublicKey))
        let negotiatedVersion = try await negotiationTask.value
        XCTAssertEqual(negotiatedVersion, .v1)

        try await client.postCustomData([0x55])
        let writes = await transport.writtenPackets()
        XCTAssertEqual(writes.first, [0x01, 0x00, 0x00, 0x03, 0x00, 0x01, 0x07])

        let securityMode = writes[writes.count - 2]
        XCTAssertEqual(Array(securityMode.prefix(5)), [0x04, 0x02, securityMode[2], 0x01, 0x03])

        let encryptedCustomData = writes.last!
        XCTAssertEqual(Array(encryptedCustomData.prefix(2)), [0x4D, 0x03])
        XCTAssertEqual(encryptedCustomData.count, 7)
    }

    private func hexadecimal(_ value: String) -> [UInt8] {
        stride(from: 0, to: value.count, by: 2).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            return UInt8(value[start ..< end], radix: 16)!
        }
    }
}
