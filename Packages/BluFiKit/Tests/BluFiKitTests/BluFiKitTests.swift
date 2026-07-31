import XCTest
@testable import BluFiKit

#if canImport(CommonCrypto)
import CommonCrypto
#endif

final class BluFiKitTests: XCTestCase {
    func testBluFiUUIDsMatchEspressifClient() {
        XCTAssertEqual(BluFiKit.serviceUUID, "0000FFFF-0000-1000-8000-00805F9B34FB")
        XCTAssertEqual(BluFiKit.writeCharacteristicUUID, "0000FF01-0000-1000-8000-00805F9B34FB")
        XCTAssertEqual(BluFiKit.notificationCharacteristicUUID, "0000FF02-0000-1000-8000-00805F9B34FB")
    }

    func testAndroidControlAndDataTypeValues() {
        XCTAssertEqual(
            BluFiProtocol.typeValue(package: .control, subtype: .getVersion),
            0x1C
        )
        XCTAssertEqual(
            BluFiProtocol.typeValue(package: .data, subtype: .negotiateSecurity),
            0x01
        )
        XCTAssertEqual(
            BluFiProtocol.typeValue(package: .data, subtype: .customData),
            0x4D
        )
        XCTAssertEqual(BluFiProtocol.package(from: 0x4D), .data)
        XCTAssertEqual(BluFiProtocol.subtype(from: 0x4D), 0x13)
    }

    func testFrameControlBitPositionsMatchAndroid() {
        let outgoing = BluFiFrameControl([
            .checksum,
            .requireAcknowledgement,
            .fragmented
        ])
        XCTAssertEqual(outgoing.rawValue, 0x1A)

        let incoming = BluFiFrameControl([
            .encrypted,
            .checksum,
            .inputDirection,
            .requireAcknowledgement,
            .fragmented
        ])
        XCTAssertEqual(incoming.rawValue, 0x1F)
    }

    func testSecurityVersionThresholdMatchesAndroidLibrary() {
        XCTAssertEqual(BluFiProtocol.securityVersion(forDeviceVersion: 0x0103), .v1)
        XCTAssertEqual(BluFiProtocol.securityVersion(forDeviceVersion: 0x0104), .v2)
        XCTAssertEqual(BluFiProtocol.securityVersion(forDeviceVersion: 0x0200), .v2)
    }

    #if canImport(CommonCrypto)
    func testAppleCryptoBackendExposesBluFiCipherModes() {
        XCTAssertEqual(kCCModeCFB, 3)
        XCTAssertEqual(kCCModeCTR, 4)
        XCTAssertEqual(kCCAlgorithmAES, 0)
    }
    #endif
}
