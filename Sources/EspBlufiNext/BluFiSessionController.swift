import BluFiKit
import Foundation
import Observation

enum BluFiSessionPhase: Equatable {
    case idle
    case connecting
    case ready
    case securing
    case secured(BluFiProtocol.SecurityVersion)
    case stationConfigurationSent
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
        case .stationConfigurationSent:
            "Station Configuration Sent"
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
        case .idle, .ready, .secured, .stationConfigurationSent, .failed:
            false
        }
    }

    var acceptsCommands: Bool {
        switch self {
        case .ready, .secured:
            true
        case .idle, .connecting, .securing, .stationConfigurationSent, .working, .failed:
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
    private(set) var customMessages: [BluFiConsoleMessage] = []
    private(set) var lastError: String?
    private(set) var reconnectableDevice: BluFiDiscoveredDevice?

    @ObservationIgnored
    private var client: BluFiClient?

    @ObservationIgnored
    private var currentSessionID: UUID?

    var isConnected: Bool {
        client != nil && connectedDevice != nil && deviceVersion != nil
    }

    var canReconnect: Bool {
        reconnectableDevice != nil && !isConnected && !phase.isBusy
    }

    func connect(
        to device: BluFiDiscoveredDevice,
        using scanner: BluFiScanner,
        settings: AppSettingsStore,
        diagnostics: BluFiDiagnosticsStore
    ) async {
        guard !phase.isBusy else {
            return
        }

        scanner.onActiveDeviceDisconnected = nil
        if let client {
            try? await client.closeConnection()
            scanner.disconnectActiveDevice()
        }
        if let currentSessionID {
            diagnostics.finishSession(currentSessionID, outcome: .disconnected)
        }
        reset()

        let sessionID = diagnostics.beginSession(for: device)
        currentSessionID = sessionID
        reconnectableDevice = device
        scanner.onActiveDeviceDisconnected = { [weak self] deviceID, error in
            self?.handleUnexpectedDisconnect(
                deviceID: deviceID,
                error: error,
                scanner: scanner,
                diagnostics: diagnostics
            )
        }
        record(
            diagnostics,
            category: .connection,
            title: "Connection requested",
            detail: device.name,
            sessionID: sessionID,
            deviceID: device.id
        )
        phase = .connecting
        lastError = nil
        wifiStatus = nil
        wifiNetworks = []
        customMessages = []

        do {
            let client = try await scanner.connect(
                to: device,
                commandTimeout: settings.commandTimeout,
                packetLength: settings.packetLength
            )
            self.client = client
            connectedDevice = device
            record(
                diagnostics,
                category: .connection,
                title: "Bluetooth link and GATT ready",
                sessionID: sessionID,
                deviceID: device.id
            )
            let version = try await client.requestDeviceVersion()
            deviceVersion = version
            securityVersion = nil
            phase = .ready
            record(
                diagnostics,
                category: .protocolExchange,
                title: "Device version received",
                detail: "BluFi \(version.major).\(version.minor)",
                sessionID: sessionID,
                deviceID: device.id
            )
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return
            }
            scanner.onActiveDeviceDisconnected = nil
            record(
                diagnostics,
                category: .connection,
                severity: .warning,
                title: "Connection cancelled",
                sessionID: sessionID,
                deviceID: device.id
            )
            diagnostics.finishSession(sessionID, outcome: .cancelled)
            scanner.disconnectActiveDevice()
            reset()
        } catch {
            guard currentSessionID == sessionID else {
                return
            }
            scanner.onActiveDeviceDisconnected = nil
            record(
                diagnostics,
                category: .connection,
                severity: .error,
                title: "Connection failed",
                detail: error.localizedDescription,
                sessionID: sessionID,
                deviceID: device.id
            )
            diagnostics.finishSession(sessionID, outcome: .failed)
            scanner.disconnectActiveDevice()
            reset(with: error)
        }
    }

    func reconnect(
        using scanner: BluFiScanner,
        settings: AppSettingsStore,
        diagnostics: BluFiDiagnosticsStore
    ) async {
        guard let reconnectableDevice, canReconnect else {
            return
        }
        await connect(
            to: reconnectableDevice,
            using: scanner,
            settings: settings,
            diagnostics: diagnostics
        )
    }

    func negotiateSecurity(
        override: BluFiSecurityOverride = .automatic,
        diagnostics: BluFiDiagnosticsStore
    ) async {
        guard let client, let deviceVersion, let sessionID = currentSessionID, !phase.isBusy else {
            return
        }

        record(
            diagnostics,
            category: .security,
            title: "Secure session negotiation started"
        )
        phase = .securing
        lastError = nil

        do {
            let negotiatedVersion = try await client.negotiateSecurity(
                deviceVersion: deviceVersion,
                override: override
            )
            guard currentSessionID == sessionID else {
                return
            }
            securityVersion = negotiatedVersion
            phase = readyPhase
            record(
                diagnostics,
                category: .security,
                title: "Secure session established",
                detail: "Security V\(securityVersion?.rawValue ?? 0)"
            )
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .security,
                severity: .warning,
                title: "Secure session negotiation cancelled"
            )
            phase = readyPhase
        } catch {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .security,
                severity: .error,
                title: "Secure session negotiation failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func refreshWiFiStatus(diagnostics: BluFiDiagnosticsStore) async {
        guard let client, let sessionID = currentSessionID, !phase.isBusy else {
            return
        }

        record(diagnostics, category: .command, title: "Read Wi-Fi Status started")
        phase = .working("Reading Wi-Fi Status")
        lastError = nil

        do {
            let status = try await client.requestDeviceStatus()
            guard currentSessionID == sessionID else {
                return
            }
            wifiStatus = status
            phase = readyPhase
            if let wifiStatus {
                record(
                    diagnostics,
                    category: .wiFi,
                    title: "Wi-Fi status received",
                    detail: statusSummary(wifiStatus)
                )
            }
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .command,
                severity: .warning,
                title: "Read Wi-Fi Status cancelled"
            )
            phase = readyPhase
        } catch {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .command,
                severity: .error,
                title: "Read Wi-Fi Status failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func scanDeviceWiFi(diagnostics: BluFiDiagnosticsStore) async {
        guard let client, let sessionID = currentSessionID, !phase.isBusy else {
            return
        }

        record(diagnostics, category: .command, title: "Device Wi-Fi scan started")
        phase = .working("Scanning Wi-Fi Networks")
        lastError = nil

        do {
            let networks = try await client.requestDeviceWiFiScan()
            guard currentSessionID == sessionID else {
                return
            }
            wifiNetworks = networks
            phase = readyPhase
            record(
                diagnostics,
                category: .wiFi,
                title: "Device Wi-Fi scan received",
                detail: "\(wifiNetworks.count) network(s)"
            )
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .command,
                severity: .warning,
                title: "Device Wi-Fi scan cancelled"
            )
            phase = readyPhase
        } catch {
            guard currentSessionID == sessionID else {
                return
            }
            record(
                diagnostics,
                category: .command,
                severity: .error,
                title: "Device Wi-Fi scan failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func provisionStation(
        ssid: String,
        password: String,
        diagnostics: BluFiDiagnosticsStore
    ) async -> Bool {
        guard let client, let sessionID = currentSessionID, !phase.isBusy else {
            return false
        }
        let deviceID = connectedDevice?.id

        record(
            diagnostics,
            category: .provisioning,
            title: "Station provisioning started",
            detail: "SSID provided; password omitted"
        )
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
            let status = try await client.configure(
                configuration,
                waitForStationStatus: true
            )
            guard currentSessionID == sessionID else {
                diagnostics.record(
                    category: .provisioning,
                    title: "Station configuration accepted",
                    detail: "No station status report before the device closed BluFi",
                    sessionID: sessionID,
                    deviceID: deviceID
                )
                return true
            }
            wifiStatus = status
            phase = wifiStatus == nil ? .stationConfigurationSent : readyPhase
            record(
                diagnostics,
                category: .provisioning,
                title: "Station configuration accepted",
                detail: wifiStatus.map(statusSummary) ?? "No station status report before the device closed BluFi"
            )
            return true
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .provisioning,
                severity: .warning,
                title: "Station provisioning cancelled"
            )
            phase = readyPhase
            return false
        } catch {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .provisioning,
                severity: .error,
                title: "Station provisioning failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func sendCustomData(
        _ data: [UInt8],
        format: BluFiPayloadFormat,
        diagnostics: BluFiDiagnosticsStore
    ) async -> Bool {
        guard let client, let sessionID = currentSessionID, !phase.isBusy else {
            return false
        }

        record(
            diagnostics,
            category: .command,
            title: "Custom data send started",
            detail: "\(format.title) · \(data.count) byte(s)"
        )
        phase = .working("Sending Custom Data")
        lastError = nil

        do {
            try await client.postCustomData(data)
            guard currentSessionID == sessionID else {
                return false
            }
            customMessages.insert(
                BluFiConsoleMessage(direction: .sent, format: format, bytes: data),
                at: 0
            )
            phase = readyPhase
            record(
                diagnostics,
                category: .protocolExchange,
                title: "Custom data sent",
                detail: "\(format.title) · \(data.count) byte(s)"
            )
            return true
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .command,
                severity: .warning,
                title: "Custom data send cancelled"
            )
            phase = readyPhase
            return false
        } catch {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .command,
                severity: .error,
                title: "Custom data send failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func receiveCustomData(
        format: BluFiPayloadFormat,
        diagnostics: BluFiDiagnosticsStore
    ) async -> Bool {
        guard let client, let sessionID = currentSessionID, !phase.isBusy else {
            return false
        }

        record(
            diagnostics,
            category: .command,
            title: "Waiting for custom data",
            detail: "\(format.title) decoder selected"
        )
        phase = .working("Waiting for Custom Data")
        lastError = nil

        do {
            let data = try await client.receiveCustomData()
            guard currentSessionID == sessionID else {
                return false
            }
            customMessages.insert(
                BluFiConsoleMessage(direction: .received, format: format, bytes: data),
                at: 0
            )
            phase = readyPhase
            record(
                diagnostics,
                category: .protocolExchange,
                title: "Custom data received",
                detail: "\(format.title) · \(data.count) byte(s)"
            )
            return true
        } catch is CancellationError {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .command,
                severity: .warning,
                title: "Custom data receive cancelled"
            )
            phase = readyPhase
            return false
        } catch {
            guard currentSessionID == sessionID else {
                return false
            }
            record(
                diagnostics,
                category: .command,
                severity: .error,
                title: "Custom data receive failed",
                detail: error.localizedDescription
            )
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            return false
        }
    }

    func clearCustomMessages() {
        customMessages.removeAll()
    }

    func disconnect(using scanner: BluFiScanner, diagnostics: BluFiDiagnosticsStore) async {
        scanner.onActiveDeviceDisconnected = nil
        record(diagnostics, category: .connection, title: "Disconnect requested")
        if let client {
            try? await client.closeConnection()
        }
        if let currentSessionID {
            diagnostics.finishSession(currentSessionID, outcome: .disconnected)
        }
        scanner.disconnectActiveDevice()
        reset()
    }

    private func handleUnexpectedDisconnect(
        deviceID: UUID,
        error: (any Error)?,
        scanner: BluFiScanner,
        diagnostics: BluFiDiagnosticsStore
    ) {
        guard connectedDevice?.id == deviceID else {
            return
        }

        scanner.onActiveDeviceDisconnected = nil
        record(
            diagnostics,
            category: .bluetooth,
            severity: .warning,
            title: "Bluetooth device disconnected",
            detail: error?.localizedDescription
        )
        if let currentSessionID {
            diagnostics.finishSession(currentSessionID, outcome: .disconnected)
        }
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
        currentSessionID = nil
        connectedDevice = nil
        deviceVersion = nil
        securityVersion = nil
        wifiStatus = nil
        wifiNetworks = []
        customMessages = []
        lastError = error?.localizedDescription
        phase = error.map { .failed($0.localizedDescription) } ?? .idle
    }

    private func record(
        _ diagnostics: BluFiDiagnosticsStore,
        category: BluFiDiagnosticCategory,
        severity: BluFiDiagnosticSeverity = .info,
        title: String,
        detail: String? = nil,
        sessionID: UUID? = nil,
        deviceID: UUID? = nil
    ) {
        diagnostics.record(
            category: category,
            severity: severity,
            title: title,
            detail: detail,
            sessionID: sessionID ?? currentSessionID,
            deviceID: deviceID ?? connectedDevice?.id
        )
    }

    private func statusSummary(_ status: BluFiWiFiStatus) -> String {
        let stationState: String = switch status.stationState {
        case .connected:
            "Station Connected"
        case .failed:
            "Station Failed"
        case .connecting:
            "Station Connecting"
        case .noIP:
            "Station No IP"
        case let .unknown(value):
            "Station Unknown (\(value))"
        }
        return "\(stationState) · IP \(status.hasIP ? "Available" : "Unavailable")"
    }
}
