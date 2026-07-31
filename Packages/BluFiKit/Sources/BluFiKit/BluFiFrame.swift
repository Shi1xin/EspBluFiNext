import Foundation

public struct BluFiFrame: Sendable, Equatable {
    public let type: UInt8
    public let control: BluFiFrameControl
    public let sequence: UInt8
    public let data: [UInt8]

    public init(type: UInt8, control: BluFiFrameControl, sequence: UInt8, data: [UInt8] = []) {
        self.type = type
        self.control = control
        self.sequence = sequence
        self.data = data
    }

    public var package: BluFiProtocol.Package? {
        BluFiProtocol.package(from: type)
    }

    public var subtype: UInt8 {
        BluFiProtocol.subtype(from: type)
    }
}

public enum BluFiProtocolError: Error, Sendable, Equatable, LocalizedError {
    case packetLengthOutOfRange(Int)
    case dataLengthOutOfRange(Int)
    case packetTooShort(Int)
    case packetLengthMismatch(expected: Int, actual: Int)
    case checksumMissing
    case invalidChecksum(expected: UInt16, actual: UInt16)
    case unexpectedSequence(expected: UInt8, actual: UInt8)
    case malformedFragment
    case fragmentLengthMismatch(expected: Int, actual: Int)
    case invalidPayload(description: String)
    case securityRequired
    case cryptographicFailure(status: Int32)
    case unexpectedFrame(type: UInt8)
    case acknowledgementTimeout(sequence: UInt8)
    case responseTimeout(type: UInt8)
    case transportClosed

    public var errorDescription: String? {
        switch self {
        case let .packetLengthOutOfRange(length):
            "BluFi packet length \(length) is outside 20...255."
        case let .dataLengthOutOfRange(length):
            "BluFi frame data length \(length) exceeds the one-byte header limit."
        case let .packetTooShort(length):
            "BluFi packet has \(length) bytes; a header requires 4 bytes."
        case let .packetLengthMismatch(expected, actual):
            "BluFi packet length is \(actual); header declares \(expected)."
        case .checksumMissing:
            "BluFi frame control requires a checksum, but the packet omits it."
        case let .invalidChecksum(expected, actual):
            "BluFi CRC mismatch: expected \(String(format: "%04X", expected)), received \(String(format: "%04X", actual))."
        case let .unexpectedSequence(expected, actual):
            "BluFi sequence mismatch: expected \(expected), received \(actual)."
        case .malformedFragment:
            "BluFi fragment omits its two-byte total payload length."
        case let .fragmentLengthMismatch(expected, actual):
            "BluFi reassembled \(actual) bytes; fragment declares \(expected)."
        case let .invalidPayload(description):
            description
        case .securityRequired:
            "BluFi frame encryption was requested before security negotiation completed."
        case let .cryptographicFailure(status):
            "Apple cryptographic operation failed with status \(status)."
        case let .unexpectedFrame(type):
            "Received unexpected BluFi frame type \(String(format: "0x%02X", type))."
        case let .acknowledgementTimeout(sequence):
            "Timed out waiting for acknowledgement of BluFi sequence \(sequence)."
        case let .responseTimeout(type):
            "Timed out waiting for BluFi response type \(String(format: "0x%02X", type))."
        case .transportClosed:
            "The BluFi transport closed before the command completed."
        }
    }
}

public enum BluFiCRC16 {
    /// Espressif lib-blufi's CRC-16 implementation. The complemented input and
    /// output let callers extend an existing calculation one byte range at a time.
    public static func calculate(_ bytes: some Collection<UInt8>, initial: UInt16 = 0) -> UInt16 {
        var crc = ~initial

        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 {
                let carries = (crc & 0x8000) != 0
                crc <<= 1
                if carries {
                    crc ^= 0x1021
                }
            }
        }

        return ~crc
    }
}

public enum BluFiFrameCodec {
    public static func encode(
        _ frame: BluFiFrame,
        encrypting: (([UInt8], UInt8) throws -> [UInt8])? = nil
    ) throws -> [UInt8] {
        guard frame.data.count <= Int(UInt8.max) else {
            throw BluFiProtocolError.dataLengthOutOfRange(frame.data.count)
        }

        var packet = [frame.type, frame.control.rawValue, frame.sequence, UInt8(frame.data.count)]

        if frame.control.contains(.checksum) {
            let checksum = BluFiCRC16.calculate([frame.sequence, UInt8(frame.data.count)] + frame.data)
            packet.append(UInt8(truncatingIfNeeded: checksum))
            packet.append(UInt8(truncatingIfNeeded: checksum >> 8))
        }

        let encryptedData: [UInt8]
        if frame.control.contains(.encrypted), !frame.data.isEmpty {
            guard let encrypting else {
                throw BluFiProtocolError.securityRequired
            }
            encryptedData = try encrypting(frame.data, frame.sequence)
        } else {
            encryptedData = frame.data
        }
        packet.insert(contentsOf: encryptedData, at: BluFiProtocol.frameHeaderLength)

        return packet
    }

    public static func decode(
        _ packet: [UInt8],
        decrypting: (([UInt8], UInt8) throws -> [UInt8])? = nil
    ) throws -> BluFiFrame {
        guard packet.count >= BluFiProtocol.frameHeaderLength else {
            throw BluFiProtocolError.packetTooShort(packet.count)
        }

        let control = BluFiFrameControl(rawValue: packet[1])
        let dataLength = Int(packet[3])
        let checksumLength = control.contains(.checksum) ? 2 : 0
        let expectedLength = BluFiProtocol.frameHeaderLength + dataLength + checksumLength

        guard packet.count == expectedLength else {
            throw BluFiProtocolError.packetLengthMismatch(expected: expectedLength, actual: packet.count)
        }

        let encryptedData = Array(packet[4 ..< 4 + dataLength])
        let data: [UInt8]
        if control.contains(.encrypted), !encryptedData.isEmpty {
            guard let decrypting else {
                throw BluFiProtocolError.securityRequired
            }
            data = try decrypting(encryptedData, packet[2])
        } else {
            data = encryptedData
        }
        if control.contains(.checksum) {
            guard packet.count >= 6 else {
                throw BluFiProtocolError.checksumMissing
            }

            let actual = UInt16(packet[packet.count - 2]) | (UInt16(packet[packet.count - 1]) << 8)
            let checksum = BluFiCRC16.calculate([packet[2], packet[3]] + data)
            guard checksum == actual else {
                throw BluFiProtocolError.invalidChecksum(expected: checksum, actual: actual)
            }
        }

        return BluFiFrame(type: packet[0], control: control, sequence: packet[2], data: data)
    }
}
