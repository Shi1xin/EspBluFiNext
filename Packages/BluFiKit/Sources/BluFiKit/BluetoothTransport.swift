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
    private struct PendingReader {
        let id: UUID
        let continuation: CheckedContinuation<[UInt8]?, Error>
    }

    private var packetsWritten: [[UInt8]] = []
    private var packetsToRead: [[UInt8]] = []
    private var readers: [PendingReader] = []
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

        let readerID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    readers.append(PendingReader(id: readerID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancelReader(id: readerID) }
        })
    }

    public func disconnect() {
        finish()
    }

    public func receive(_ packet: [UInt8]) {
        if !readers.isEmpty {
            readers.removeFirst().continuation.resume(returning: packet)
        } else {
            packetsToRead.append(packet)
        }
    }

    private func cancelReader(id: UUID) {
        guard let index = readers.firstIndex(where: { $0.id == id }) else {
            return
        }
        readers.remove(at: index).continuation.resume(throwing: CancellationError())
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
                reader.continuation.resume(throwing: error)
            } else {
                reader.continuation.resume(returning: nil)
            }
        }
    }

    public func writtenPackets() -> [[UInt8]] {
        packetsWritten
    }
}
