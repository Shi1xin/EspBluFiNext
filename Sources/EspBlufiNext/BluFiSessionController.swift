import BluFiKit
import Foundation
import Observation

enum BluFiSessionPhase: Equatable {
    case idle
    case connecting
    case ready
    case securing
    case secured(BluFiProtocol.SecurityVersion)
    case working(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "No Active Session"
        case .connecting:
            "Connecting"
        case .ready:
            "Connected"
        case .securing:
            "Securing Session"
        case let .secured(version):
            "Secure Session (V\(version.rawValue))"
        case let .working(operation):
            operation
        case .failed:
            "Session Error"
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .securing, .working:
            true
        case .idle, .ready, .secured, .failed:
            false
        }
    }
}

/// Owns app-facing session state while BluFiKit retains all packet, crypto and
/// credential handling. Password strings never become controller properties.
@MainActor
@Observable
final class BluFiSessionController {
    private(set) var phase: BluFiSessionPhase = .idle
    private(set) var connectedDevice: BluFiDiscoveredDevice?
    private(set) var deviceVersion: BluFiDeviceVersion?
    private(set) var securityVersion: BluFiProtocol.SecurityVersion?
    private(set) var wifiStatus: BluFiWiFiStatus?
    private(set) var wifiNetworks: [BluFiWiFiScanResult] = []
    private(set) var lastError: String?

    @ObservationIgnored
    private var client: BluFiClient?

    var isConnected: Bool {
        client != nil && connectedDevice != nil
    }

    func connect(to device: BluFiDiscoveredDevice, using scanner: BluFiScanner) async {
        guard !phase.isBusy else {
            return
        }

        phase = .connecting
        lastError = nil
        wifiStatus = nil
        wifiNetworks = []

        do {
            let client = try await scanner.connect(to: device)
            let version = try await client.requestDeviceVersion()
            self.client = client
            connectedDevice = device
            deviceVersion = version
            securityVersion = nil
            phase = .ready
        } catch is CancellationError {
            scanner.disconnectActiveDevice()
            reset()
        } catch {
            scanner.disconnectActiveDevice()
            reset(with: error)
        }
    }

    func negotiateSecurity(override: BluFiSecurityOverride = .automatic) async {
        guard let client, let deviceVersion, !phase.isBusy else {
            return
        }

        phase = .securing
        lastError = nil

        do {
            securityVersion = try await client.negotiateSecurity(
                deviceVersion: deviceVersion,
                override: override
            )
            phase = readyPhase
        } catch is CancellationError {
            phase = readyPhase
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func refreshWiFiStatus() async {
        guard let client, !phase.isBusy else {
            return
        }

        phase = .working("Reading Wi-Fi Status")
        lastError = nil

        do {
            wifiStatus = try await client.requestDeviceStatus()
            phase = readyPhase
        } catch is CancellationError {
            phase = readyPhase
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func scanDeviceWiFi() async {
        guard let client, !phase.isBusy else {
            return
        }

        phase = .working("Scanning Wi-Fi Networks")
        lastError = nil

        do {
            wifiNetworks = try await client.requestDeviceWiFiScan()
            phase = readyPhase
        } catch is CancellationError {
            phase = readyPhase
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func provisionStation(ssid: String, password: String) async -> Bool {
        guard let client, !phase.isBusy else {
            return false
        }

        phase = .working("Provisioning Wi-Fi")
        lastError = nil

        do {
            let configuration = BluFiProvisioningConfiguration(
                mode: .station,
                station: BluFiStationProvisioning(
                    ssid: ssid,
                    password: BluFiSensitiveValue(utf8: password)
                )
            )
            try await client.configure(configuration)
            phase = readyPhase
            return true
        } catch is CancellationError {
            phase = readyPhase
            return false
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            return false
        }
    }

    func disconnect(using scanner: BluFiScanner) async {
        if let client {
            try? await client.closeConnection()
        }
        scanner.disconnectActiveDevice()
        reset()
    }

    private var readyPhase: BluFiSessionPhase {
        if let securityVersion {
            .secured(securityVersion)
        } else {
            .ready
        }
    }

    private func reset(with error: (any Error)? = nil) {
        client = nil
        connectedDevice = nil
        deviceVersion = nil
        securityVersion = nil
        wifiStatus = nil
        wifiNetworks = []
        lastError = error?.localizedDescription
        phase = error.map { .failed($0.localizedDescription) } ?? .idle
    }
}
