import Foundation

public enum BluFiFragmenter {
    public static func frames(
        type: UInt8,
        control: BluFiFrameControl,
        data: [UInt8],
        packetLength: Int,
        nextSequence: () -> UInt8
    ) throws -> [BluFiFrame] {
        guard (BluFiProtocol.minimumPacketLength ... BluFiProtocol.maximumPacketLength).contains(packetLength) else {
            throw BluFiProtocolError.packetLengthOutOfRange(packetLength)
        }

        let checksumLength = control.contains(.checksum) ? 2 : 0
        let unfragmentedCapacity = packetLength - BluFiProtocol.frameHeaderLength - checksumLength
        guard data.count > unfragmentedCapacity else {
            return [BluFiFrame(type: type, control: control.subtracting(.fragmented), sequence: nextSequence(), data: data)]
        }

        let fragmentCapacity = unfragmentedCapacity - 2
        precondition(fragmentCapacity > 0, "BluFi's minimum packet length leaves room for a fragment length prefix.")

        var frames: [BluFiFrame] = []
        var offset = 0
        while data.count - offset > unfragmentedCapacity {
            let end = offset + fragmentCapacity
            var fragmentData = [
                UInt8(truncatingIfNeeded: data.count),
                UInt8(truncatingIfNeeded: data.count >> 8)
            ]
            fragmentData.append(contentsOf: data[offset ..< end])
            frames.append(
                BluFiFrame(
                    type: type,
                    control: control.union(.fragmented),
                    sequence: nextSequence(),
                    data: fragmentData
                )
            )
            offset = end
        }

        frames.append(
            BluFiFrame(
                type: type,
                control: control.subtracting(.fragmented),
                sequence: nextSequence(),
                data: Array(data[offset...])
            )
        )
        return frames
    }
}

public struct BluFiFragmentReassembler: Sendable {
    private var type: UInt8?
    private var expectedLength: Int?
    private var data: [UInt8] = []

    public init() {}

    public var isAssembling: Bool {
        expectedLength != nil
    }

    public mutating func append(_ frame: BluFiFrame) throws -> BluFiFrame? {
        if frame.control.contains(.fragmented) {
            guard frame.data.count >= 2 else {
                throw BluFiProtocolError.malformedFragment
            }

            let declaredLength = Int(frame.data[0]) | (Int(frame.data[1]) << 8)
            if let type, type != frame.type {
                throw BluFiProtocolError.unexpectedFrame(type: frame.type)
            }
            if let expectedLength, expectedLength != declaredLength {
                throw BluFiProtocolError.fragmentLengthMismatch(expected: expectedLength, actual: declaredLength)
            }

            type = frame.type
            expectedLength = declaredLength
            data.append(contentsOf: frame.data.dropFirst(2))
            guard data.count < declaredLength else {
                throw BluFiProtocolError.fragmentLengthMismatch(expected: declaredLength, actual: data.count)
            }
            return nil
        }

        guard let expectedLength else {
            return frame
        }
        guard type == frame.type else {
            throw BluFiProtocolError.unexpectedFrame(type: frame.type)
        }

        data.append(contentsOf: frame.data)
        guard data.count == expectedLength else {
            throw BluFiProtocolError.fragmentLengthMismatch(expected: expectedLength, actual: data.count)
        }

        let assembled = BluFiFrame(
            type: frame.type,
            control: frame.control.subtracting(.fragmented),
            sequence: frame.sequence,
            data: data
        )
        self = Self()
        return assembled
    }
}
