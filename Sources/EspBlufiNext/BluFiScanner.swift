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

    var title: String {
        switch self {
        case .unknown:
            "Checking Bluetooth"
        case .resetting:
            "Bluetooth resetting"
        case .unsupported:
            "Bluetooth unavailable"
        case .unauthorized:
            "Bluetooth permission required"
        case .poweredOff:
            "Bluetooth is off"
        case .poweredOn:
            "Bluetooth ready"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown, .resetting:
            "ellipsis.circle"
        case .unsupported:
            "xmark.circle"
        case .unauthorized:
            "lock.circle"
        case .poweredOff:
            "bluetooth.slash"
        case .poweredOn:
            "bluetooth"
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

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = BluFiBluetoothState(central.state)

        if !bluetoothState.canScan {
            stopScanning()
        }
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
