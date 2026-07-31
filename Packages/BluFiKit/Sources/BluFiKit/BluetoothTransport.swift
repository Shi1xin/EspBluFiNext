import Foundation

/// The BLE boundary used by the transport-independent BluFi runtime.
/// CoreBluetooth adapts its write and notification callbacks to this protocol.
public protocol BluetoothTransport: Sendable {
    func write(_ packet: [UInt8]) async throws
    func nextPacket() async throws -> [UInt8]?
    func disconnect() async
}

/// Deterministic transport for protocol and command tests.
public actor BluFiFakeTransport: BluetoothTransport {
    private var packetsWritten: [[UInt8]] = []
    private var packetsToRead: [[UInt8]] = []
    private var readers: [CheckedContinuation<[UInt8]?, Error>] = []
    private var terminalError: (any Error)?
    private var isClosed = false

    public init() {}

    public func write(_ packet: [UInt8]) {
        packetsWritten.append(packet)
    }

    public func nextPacket() async throws -> [UInt8]? {
        if !packetsToRead.isEmpty {
            return packetsToRead.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }
        if isClosed {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            readers.append(continuation)
        }
    }

    public func disconnect() {
        finish()
    }

    public func receive(_ packet: [UInt8]) {
        if !readers.isEmpty {
            readers.removeFirst().resume(returning: packet)
        } else {
            packetsToRead.append(packet)
        }
    }

    public func finish(throwing error: (any Error)? = nil) {
        guard !isClosed else {
            return
        }
        isClosed = true
        terminalError = error
        let pendingReaders = readers
        readers.removeAll()
        for reader in pendingReaders {
            if let error {
                reader.resume(throwing: error)
            } else {
                reader.resume(returning: nil)
            }
        }
    }

    public func writtenPackets() -> [[UInt8]] {
        packetsWritten
    }
}
