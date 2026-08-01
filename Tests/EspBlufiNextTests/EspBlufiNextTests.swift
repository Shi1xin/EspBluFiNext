import XCTest
@testable import EspBlufiNext

@MainActor
final class EspBlufiNextTests: XCTestCase {
    func testAppTestTargetIsWired() {
        XCTAssertTrue(true)
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
}
