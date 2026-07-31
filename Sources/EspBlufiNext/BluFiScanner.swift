import CoreBluetooth
import Foundation
import Observation
import BluFiKit

enum BluFiBluetoothState: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn

    init(_ state: CBManagerState) {
        switch state {
        case .unknown:
            self = .unknown
        case .resetting:
            self = .resetting
        case .unsupported:
            self = .unsupported
        case .unauthorized:
            self = .unauthorized
        case .poweredOff:
            self = .poweredOff
        case .poweredOn:
            self = .poweredOn
        @unknown default:
            self = .unknown
        }
    }

    var canScan: Bool {
        self == .poweredOn
    }
}

struct BluFiDiscoveredDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rssi: Int
    var isConnectable: Bool
}

@MainActor
@Observable
final class BluFiScanner: NSObject, @preconcurrency CBCentralManagerDelegate {
    private static let serviceUUID = CBUUID(string: BluFiProtocol.serviceUUID)

    private(set) var bluetoothState: BluFiBluetoothState = .unknown
    private(set) var devices: [BluFiDiscoveredDevice] = []
    private(set) var isScanning = false
    var namePrefix = ""

    @ObservationIgnored
    private var central: CBCentralManager?

    @ObservationIgnored
    private var peripherals: [UUID: CBPeripheral] = [:]

    @ObservationIgnored
    private var activeTransport: BluFiCoreBluetoothTransport?

    init(startCentralManager: Bool = true) {
        super.init()
        if startCentralManager {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func toggleScanning() {
        isScanning ? stopScanning() : startScanning()
    }

    func startScanning() {
        guard bluetoothState.canScan, let central else {
            return
        }

        devices.removeAll()
        peripherals.removeAll()
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }

    func stopScanning() {
        guard isScanning else {
            return
        }

        central?.stopScan()
        isScanning = false
    }

    func peripheral(for id: UUID) -> CBPeripheral? {
        peripherals[id]
    }

    func connect(to device: BluFiDiscoveredDevice) async throws -> BluFiClient {
        guard let central else {
            throw BluFiGATTError.connectionFailed("Bluetooth central manager is unavailable")
        }
        guard bluetoothState.canScan else {
            throw BluFiGATTError.connectionFailed("Bluetooth is not ready")
        }
        guard let peripheral = peripherals[device.id] else {
            throw BluFiGATTError.connectionFailed("The selected device is no longer available")
        }

        stopScanning()
        activeTransport?.disconnect()

        let transport = BluFiCoreBluetoothTransport(peripheral: peripheral)
        activeTransport = transport
        do {
            try await transport.connect(using: central)
            try await transport.prepare()
            return try await BluFiClient(transport: transport, packetLength: transport.packetLength)
        } catch {
            if activeTransport === transport {
                activeTransport = nil
            }
            throw error
        }
    }

    func disconnectActiveDevice() {
        activeTransport?.disconnect()
        activeTransport = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = BluFiBluetoothState(central.state)

        if !bluetoothState.canScan {
            stopScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard activeTransport?.matches(peripheral) == true else {
            return
        }
        activeTransport?.connected()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard activeTransport?.matches(peripheral) == true else {
            return
        }
        activeTransport?.connectionFailed(error)
        activeTransport = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard activeTransport?.matches(peripheral) == true else {
            return
        }
        activeTransport?.disconnected(error)
        activeTransport = nil
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Unnamed BluFi Device"
        let normalizedPrefix = namePrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedPrefix.isEmpty || name.lowercased().hasPrefix(normalizedPrefix.lowercased()) else {
            return
        }

        peripherals[peripheral.identifier] = peripheral

        let device = BluFiDiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        )

        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }

        devices.sort { lhs, rhs in
            if lhs.rssi == rhs.rssi {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.rssi > rhs.rssi
        }
    }

    static func preview() -> BluFiScanner {
        let scanner = BluFiScanner(startCentralManager: false)
        scanner.bluetoothState = .poweredOn
        scanner.devices = [
            BluFiDiscoveredDevice(
                id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
                name: "xiaozhi",
                rssi: -48,
                isConnectable: true
            ),
            BluFiDiscoveredDevice(
                id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000002")!,
                name: "ESP BluFi",
                rssi: -71,
                isConnectable: true
            )
        ]
        return scanner
    }
}
