import CoreBluetooth
import Foundation
import BluFiKit

enum BluFiGATTError: Error, LocalizedError {
    case connectionFailed(String)
    case disconnected(String)
    case serviceMissing
    case writeCharacteristicMissing
    case notificationCharacteristicMissing
    case notificationSetupFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .connectionFailed(message): "Bluetooth connection failed: \(message)"
        case let .disconnected(message): "Bluetooth disconnected: \(message)"
        case .serviceMissing: "The connected device does not expose the BluFi FFFF service."
        case .writeCharacteristicMissing: "The BluFi service does not expose the FF01 write characteristic."
        case .notificationCharacteristicMissing: "The BluFi service does not expose the FF02 notification characteristic."
        case let .notificationSetupFailed(message): "Unable to enable BluFi notifications: \(message)"
        case let .writeFailed(message): "BluFi write failed: \(message)"
        }
    }
}

/// CoreBluetooth adapter for BluFiKit's transport-independent session runtime.
/// Scanner-owned central callbacks forward connection changes here; this object
/// owns only the selected peripheral, GATT discovery, writes and notifications.
@MainActor
final class BluFiCoreBluetoothTransport: NSObject, BluetoothTransport, @preconcurrency CBPeripheralDelegate {
    private static let connectionTimeout: Duration = .seconds(12)

    private let peripheral: CBPeripheral
    private weak var central: CBCentralManager?
    private var writeCharacteristic: CBCharacteristic?
    private var notificationCharacteristic: CBCharacteristic?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var preparationTimeoutTask: Task<Void, Never>?
    private var packetReaders: [CheckedContinuation<[UInt8]?, Error>] = []
    private var queuedPackets: [[UInt8]] = []
    private var terminalError: (any Error)?
    private var isClosed = false

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
    }

    var packetLength: Int {
        min(
            BluFiProtocol.maximumPacketLength,
            max(BluFiProtocol.minimumPacketLength, peripheral.maximumWriteValueLength(for: .withResponse))
        )
    }

    func matches(_ peripheral: CBPeripheral) -> Bool {
        self.peripheral.identifier == peripheral.identifier
    }

    func connect(using central: CBCentralManager) async throws {
        self.central = central
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            connectionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.connectionTimeout)
                guard !Task.isCancelled else {
                    return
                }
                self?.connectionDidTimeOut()
            }
            central.connect(peripheral)
        }
    }

    func prepare() async throws {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            preparationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.connectionTimeout)
                guard !Task.isCancelled else {
                    return
                }
                self?.preparationDidTimeOut()
            }
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: BluFiProtocol.serviceUUID)])
        }
    }

    func write(_ packet: [UInt8]) async throws {
        guard let writeCharacteristic else {
            throw BluFiGATTError.writeCharacteristicMissing
        }
        guard !isClosed else {
            throw terminalError ?? BluFiProtocolError.transportClosed
        }

        try await withCheckedThrowingContinuation { continuation in
            writeContinuation = continuation
            peripheral.writeValue(Data(packet), for: writeCharacteristic, type: .withResponse)
        }
    }

    func nextPacket() async throws -> [UInt8]? {
        if !queuedPackets.isEmpty {
            return queuedPackets.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }
        if isClosed {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            packetReaders.append(continuation)
        }
    }

    func disconnect() {
        central?.cancelPeripheralConnection(peripheral)
        finish(throwing: nil)
    }

    func connected() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connectContinuation?.resume()
        connectContinuation = nil
    }

    func connectionFailed(_ error: (any Error)?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        let failure = BluFiGATTError.connectionFailed(error?.localizedDescription ?? "Unknown CoreBluetooth error")
        connectContinuation?.resume(throwing: failure)
        connectContinuation = nil
        finish(throwing: failure)
    }

    func disconnected(_ error: (any Error)?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        let failure = BluFiGATTError.disconnected(error?.localizedDescription ?? "Peripheral disconnected")
        connectContinuation?.resume(throwing: failure)
        connectContinuation = nil
        readyContinuation?.resume(throwing: failure)
        readyContinuation = nil
        writeContinuation?.resume(throwing: failure)
        writeContinuation = nil
        finish(throwing: failure)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else {
            failPreparation(BluFiGATTError.connectionFailed(error!.localizedDescription))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: BluFiProtocol.serviceUUID) }) else {
            failPreparation(BluFiGATTError.serviceMissing)
            return
        }
        peripheral.discoverCharacteristics(
            [
                CBUUID(string: BluFiProtocol.writeCharacteristicUUID),
                CBUUID(string: BluFiProtocol.notificationCharacteristicUUID)
            ],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else {
            failPreparation(BluFiGATTError.connectionFailed(error!.localizedDescription))
            return
        }

        writeCharacteristic = service.characteristics?.first {
            $0.uuid == CBUUID(string: BluFiProtocol.writeCharacteristicUUID)
        }
        notificationCharacteristic = service.characteristics?.first {
            $0.uuid == CBUUID(string: BluFiProtocol.notificationCharacteristicUUID)
        }

        guard writeCharacteristic != nil else {
            failPreparation(BluFiGATTError.writeCharacteristicMissing)
            return
        }
        guard let notificationCharacteristic else {
            failPreparation(BluFiGATTError.notificationCharacteristicMissing)
            return
        }
        peripheral.setNotifyValue(true, for: notificationCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == CBUUID(string: BluFiProtocol.notificationCharacteristicUUID) else {
            return
        }
        guard error == nil, characteristic.isNotifying else {
            failPreparation(BluFiGATTError.notificationSetupFailed(error?.localizedDescription ?? "Notifications remain disabled"))
            return
        }
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        readyContinuation?.resume()
        readyContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == CBUUID(string: BluFiProtocol.writeCharacteristicUUID) else {
            return
        }
        if let error {
            writeContinuation?.resume(throwing: BluFiGATTError.writeFailed(error.localizedDescription))
        } else {
            writeContinuation?.resume()
        }
        writeContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == CBUUID(string: BluFiProtocol.notificationCharacteristicUUID) else {
            return
        }
        if let error {
            finish(throwing: BluFiGATTError.disconnected(error.localizedDescription))
            return
        }
        guard let value = characteristic.value else {
            return
        }

        let packet = Array(value)
        if !packetReaders.isEmpty {
            packetReaders.removeFirst().resume(returning: packet)
        } else {
            queuedPackets.append(packet)
        }
    }

    private func failPreparation(_ error: any Error) {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        finish(throwing: error)
    }

    private func connectionDidTimeOut() {
        guard connectContinuation != nil else {
            return
        }

        let error = BluFiGATTError.connectionFailed("Timed out waiting for the device to accept a Bluetooth connection.")
        central?.cancelPeripheralConnection(peripheral)
        connectContinuation?.resume(throwing: error)
        connectContinuation = nil
        finish(throwing: error)
    }

    private func preparationDidTimeOut() {
        guard readyContinuation != nil else {
            return
        }

        let error = BluFiGATTError.connectionFailed("Timed out discovering the BluFi service and characteristics.")
        central?.cancelPeripheralConnection(peripheral)
        failPreparation(error)
    }

    private func finish(throwing error: (any Error)?) {
        guard !isClosed else {
            return
        }
        isClosed = true
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        terminalError = error
        let termination = error ?? BluFiProtocolError.transportClosed
        connectContinuation?.resume(throwing: termination)
        connectContinuation = nil
        readyContinuation?.resume(throwing: termination)
        readyContinuation = nil
        writeContinuation?.resume(throwing: termination)
        writeContinuation = nil
        let readers = packetReaders
        packetReaders.removeAll()
        for reader in readers {
            if let error {
                reader.resume(throwing: error)
            } else {
                reader.resume(returning: nil)
            }
        }
    }
}
