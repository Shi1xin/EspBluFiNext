import XCTest
@testable import BluFiKit

final class BluFiProvisioningTests: XCTestCase {
    func testWiFiScanParserMatchesEspressifLengthRSSIAndSSIDFormat() throws {
        let results = try BluFiProvisioningParser.wiFiScanResults(from: [4, 0xC8, 0x61, 0x62, 0x63, 1, 0xD8])

        XCTAssertEqual(results, [
            BluFiWiFiScanResult(ssidBytes: [0x61, 0x62, 0x63], rssi: -56),
            BluFiWiFiScanResult(ssidBytes: [], rssi: -40)
        ])
        XCTAssertEqual(results[0].ssid, "abc")
    }

    func testWiFiStatusParserPreservesConnectionProgressAndRedactsPasswords() throws {
        let status = try BluFiProvisioningParser.wiFiStatus(from: [
            0x03, 0x02, 0x01,
            0x02, 0x04, 0x68, 0x6F, 0x6D, 0x65,
            0x03, 0x06, 0x73, 0x65, 0x63, 0x72, 0x65, 0x74,
            0x14, 0x01, 0x03,
            0x15, 0x01, 0xC9,
            0x16, 0x01, 0xC9,
            0x07, 0x01, 0x03,
            0x04, 0x03, 0x65, 0x73, 0x70,
            0x05, 0x02, 0x78, 0x78,
            0x08, 0x01, 0x06,
            0x06, 0x01, 0x04,
            0xAA, 0x02, 0x01, 0x02
        ])

        XCTAssertEqual(status.operationMode, .stationAndSoftAP)
        XCTAssertEqual(status.stationState, .connecting)
        XCTAssertTrue(status.isConnecting)
        XCTAssertFalse(status.hasIP)
        XCTAssertEqual(status.stationSSID, "home")
        XCTAssertTrue(status.stationPasswordPresent)
        XCTAssertEqual(status.stationMaximumRetry, 3)
        XCTAssertEqual(status.stationEndReason, 201)
        XCTAssertEqual(status.stationRSSI, -55)
        XCTAssertEqual(status.softAPSecurity, .wpa2)
        XCTAssertEqual(status.softAPSSID, "esp")
        XCTAssertTrue(status.softAPPasswordPresent)
        XCTAssertEqual(status.softAPChannel, 6)
        XCTAssertEqual(status.softAPMaximumConnections, 4)
        XCTAssertEqual(status.unknownFieldTypes, [0xAA])
    }

    func testDiagnosticRedactorCoversCredentialsCertificatesAndRawCustomData() {
        let passwordFrame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .stationWiFiPassword),
            control: [],
            sequence: 1,
            data: Array("s3cr3t".utf8)
        )
        let ssidFrame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .stationWiFiSSID),
            control: [],
            sequence: 2,
            data: Array("home".utf8)
        )
        let customFrame = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .customData),
            control: [],
            sequence: 3,
            data: [0xDE, 0xAD]
        )

        let password = BluFiDiagnosticRedactor.redact(passwordFrame)
        XCTAssertTrue(password.isSensitive)
        XCTAssertEqual(password.payload, "<redacted: 6 bytes>")
        XCTAssertFalse(password.payload.contains("s3cr3t"))
        XCTAssertFalse(BluFiDiagnosticRedactor.redact(ssidFrame).isSensitive)
        XCTAssertEqual(BluFiDiagnosticRedactor.redact(ssidFrame).payload, "68 6F 6D 65")
        XCTAssertTrue(BluFiDiagnosticRedactor.redact(customFrame).isSensitive)
    }

    func testConfigurePostsAndroidCompatibleStationAndSoftAPSequence() async throws {
        let transport = BluFiFakeTransport()
        let session = try await BluFiSession(transport: transport, commandTimeout: .seconds(1))
        let configuration = BluFiProvisioningConfiguration(
            mode: .stationAndSoftAP,
            station: BluFiStationProvisioning(
                ssid: "home",
                password: BluFiSensitiveValue(utf8: "station-secret")
            ),
            softAP: BluFiSoftAPProvisioning(
                security: .wpa2,
                ssid: "esp-ap",
                password: BluFiSensitiveValue(utf8: "softap-secret"),
                channel: 6,
                maximumConnections: 4
            )
        )

        let configurationTask = Task {
            _ = try await session.configure(configuration)
        }
        let operationModeAck = BluFiFrame(type: 0x00, control: [.inputDirection], sequence: 0, data: [0])
        await transport.receive(try BluFiFrameCodec.encode(operationModeAck))
        try await configurationTask.value

        let packets = await transport.writtenPackets()
        XCTAssertEqual(packets.map { $0[0] }, [0x08, 0x09, 0x0D, 0x0C, 0x11, 0x15, 0x21, 0x19, 0x1D])
        XCTAssertEqual(packets[0][1], BluFiFrameControl.requireAcknowledgement.rawValue)
        XCTAssertEqual(Array(packets[3].prefix(4)), [0x0C, 0x00, 0x03, 0x00])

        let sensitiveFrame = try BluFiFrameCodec.decode(packets[2])
        XCTAssertEqual(BluFiDiagnosticRedactor.redact(sensitiveFrame).payload, "<redacted: 14 bytes>")
    }

    func testStationProvisioningConsumesUnsolicitedConnectionReport() async throws {
        let transport = BluFiFakeTransport()
        let session = try await BluFiSession(transport: transport, commandTimeout: .seconds(1))
        let configuration = BluFiProvisioningConfiguration(
            mode: .station,
            station: BluFiStationProvisioning(
                ssid: "home",
                password: BluFiSensitiveValue(utf8: "station-secret")
            )
        )

        let configurationTask = Task {
            try await session.configure(configuration, waitForStationStatus: true)
        }
        let operationModeAck = BluFiFrame(type: 0x00, control: [.inputDirection], sequence: 0, data: [0])
        await transport.receive(try BluFiFrameCodec.encode(operationModeAck))
        let connectionReport = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .WiFiConnectionState),
            control: [.inputDirection],
            sequence: 1,
            data: [BluFiOperationMode.station.rawValue, 0x00, 0x00]
        )
        await transport.receive(try BluFiFrameCodec.encode(connectionReport))

        let status = try await configurationTask.value
        XCTAssertEqual(status?.stationState, .connected)
        XCTAssertTrue(status?.hasIP == true)
    }

    func testClientRequestsDeviceWiFiScanAndParsesResult() async throws {
        let transport = BluFiFakeTransport()
        let client = try await BluFiClient(transport: transport, commandTimeout: .seconds(1))
        let scanTask = Task {
            try await client.requestDeviceWiFiScan()
        }

        let response = BluFiFrame(
            type: BluFiProtocol.typeValue(package: .data, subtype: .WiFiList),
            control: [.inputDirection],
            sequence: 0,
            data: [4, 0xC8, 0x65, 0x73, 0x70]
        )
        await transport.receive(try BluFiFrameCodec.encode(response))
        let results = try await scanTask.value

        XCTAssertEqual(results, [BluFiWiFiScanResult(ssidBytes: Array("esp".utf8), rssi: -56)])
        let packets = await transport.writtenPackets()
        XCTAssertEqual(packets.first, [0x24, 0x00, 0x00, 0x00])
    }
}
