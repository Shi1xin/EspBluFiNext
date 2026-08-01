import XCTest
@testable import EspBlufiNext

@MainActor
final class EspBlufiNextTests: XCTestCase {
    func testAppTestTargetIsWired() {
        XCTAssertTrue(true)
    }

    func testAppCoordinatorShowsSessionTab() {
        let coordinator = AppCoordinator()

        coordinator.showSession()

        XCTAssertEqual(coordinator.selectedTab, .session)
    }

    func testPayloadCodecRoundTripsSupportedFormats() throws {
        let binaryBytes: [UInt8] = [0x00, 0x2A, 0xDE, 0xAD, 0xBE, 0xEF]
        for format in [BluFiPayloadFormat.hex, .base64] {
            let encoded = BluFiPayloadCodec.encode(binaryBytes, format: format)
            XCTAssertEqual(try BluFiPayloadCodec.decode(encoded, format: format), binaryBytes)
        }

        let utf8Bytes = Array("BluFi ✓".utf8)
        let utf8Encoded = BluFiPayloadCodec.encode(utf8Bytes, format: .utf8)
        XCTAssertEqual(try BluFiPayloadCodec.decode(utf8Encoded, format: .utf8), utf8Bytes)

        XCTAssertEqual(
            try BluFiPayloadCodec.decode("0xDE:AD-be,ef", format: .hex),
            [0xDE, 0xAD, 0xBE, 0xEF]
        )
    }

    func testPayloadCodecRejectsMalformedPayloads() {
        XCTAssertThrowsError(try BluFiPayloadCodec.decode("ABC", format: .hex)) { error in
            XCTAssertEqual(error as? BluFiPayloadCodecError, .oddHexLength)
        }
        XCTAssertThrowsError(try BluFiPayloadCodec.decode("GG", format: .hex)) { error in
            XCTAssertEqual(error as? BluFiPayloadCodecError, .invalidHexCharacter("G"))
        }
        XCTAssertThrowsError(try BluFiPayloadCodec.decode("not base64", format: .base64)) { error in
            XCTAssertEqual(error as? BluFiPayloadCodecError, .invalidBase64)
        }
    }

    func testDiagnosticsPersistRedactedStructuredEventsAndSessionHistory() {
        let suiteName = "EspBluFiNext.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let device = BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )
        let store = BluFiDiagnosticsStore(defaults: defaults)
        let sessionID = store.beginSession(for: device)

        store.record(
            category: .provisioning,
            title: "Station configuration accepted",
            detail: "SSID provided; password omitted",
            sessionID: sessionID,
            deviceID: device.id
        )
        store.finishSession(sessionID, outcome: .disconnected)

        let reloaded = BluFiDiagnosticsStore(defaults: defaults)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.detail, "SSID provided; password omitted")
        XCTAssertEqual(reloaded.sessions.first?.id, sessionID)
        XCTAssertEqual(reloaded.sessions.first?.outcome, .disconnected)
        XCTAssertEqual(reloaded.sessions.first?.eventCount, 1)
    }

    func testDiagnosticsReconcilesPersistedActiveSessionsAfterReload() {
        let suiteName = "EspBluFiNext.active-session-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let device = BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )

        let store = BluFiDiagnosticsStore(defaults: defaults)
        let sessionID = store.beginSession(for: device)

        let reloaded = BluFiDiagnosticsStore(defaults: defaults)
        let session = try! XCTUnwrap(reloaded.sessions.first(where: { $0.id == sessionID }))
        XCTAssertEqual(session.outcome, .disconnected)
        XCTAssertNotNil(session.endedAt)
    }

    func testDiagnosticsRemoveSessionAlsoRemovesItsEvents() {
        let suiteName = "EspBluFiNext.remove-session-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let device = BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-0000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )
        let store = BluFiDiagnosticsStore(defaults: defaults)
        let sessionID = store.beginSession(for: device)
        store.record(
            category: .connection,
            title: "Connection requested",
            sessionID: sessionID,
            deviceID: device.id
        )

        store.removeSession(sessionID)

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testDiagnosticExportContainsRedactionPolicyAndOmitsCredentials() throws {
        let suiteName = "EspBluFiNext.export-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let device = BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )
        let store = BluFiDiagnosticsStore(defaults: defaults)
        let sessionID = store.beginSession(for: device)
        store.record(
            category: .provisioning,
            title: "Station provisioning started",
            detail: "SSID provided; password omitted",
            sessionID: sessionID,
            deviceID: device.id
        )

        let export = String(data: try store.exportData(), encoding: .utf8)!
        XCTAssertTrue(export.contains("redactionPolicy"))
        XCTAssertTrue(export.contains("password omitted"))
        XCTAssertFalse(export.contains("secret-password"))
    }
}
