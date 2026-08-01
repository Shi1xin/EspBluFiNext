import BluFiKit
import SwiftUI

struct SessionView: View {
    @Environment(BluFiScanner.self) private var scanner
    @Environment(BluFiSessionController.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.isConnected, let device = session.connectedDevice {
                    SessionDetailView(device: device)
                } else if session.phase.isBusy {
                    ContentUnavailableView(
                        "Connecting to Device",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Discovering the BluFi service and requesting the device version.")
                    )
                } else if let lastError = session.lastError {
                    ContentUnavailableView(
                        "Connection Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(lastError)
                    )
                } else {
                    ContentUnavailableView(
                        "No Active Session",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Connect to a device to inspect BluFi status and send commands.")
                    )
                }
            }
            .navigationTitle("Session")
            .toolbar {
                if session.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Disconnect", systemImage: "xmark.circle", action: disconnect)
                            .disabled(session.phase.isBusy)
                    }
                }
            }
        }
    }

    private func disconnect() {
        Task {
            await session.disconnect(using: scanner)
        }
    }
}

private struct SessionDetailView: View {
    @Environment(BluFiSessionController.self) private var session
    @State private var stationSSID = ""
    @State private var stationPassword = ""

    let device: BluFiDiscoveredDevice

    var body: some View {
        Form {
            SessionStatusSection()
            SessionDeviceSection(device: device)
            SessionCommandsSection()

            if let status = session.wifiStatus {
                WiFiStatusSection(status: status)
            }

            StationProvisioningSection(
                ssid: $stationSSID,
                password: $stationPassword,
                send: sendStationConfiguration
            )

            if !session.wifiNetworks.isEmpty {
                DeviceWiFiScanSection(networks: session.wifiNetworks)
            }
        }
    }

    private func sendStationConfiguration() {
        Task {
            let didProvision = await session.provisionStation(
                ssid: stationSSID,
                password: stationPassword
            )
            if didProvision {
                stationPassword = ""
            }
        }
    }
}

private struct SessionStatusSection: View {
    @Environment(BluFiSessionController.self) private var session

    var body: some View {
        Section {
            HStack(spacing: 10) {
                if session.phase.isBusy {
                    ProgressView()
                }
                Text(session.phase.title)
                    .font(.headline)
            }

            if let lastError = session.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if case .stationConfigurationSent = session.phase {
                Text("The device accepted the Station configuration without a status report. Re-enter provisioning mode and reconnect to query its current Wi-Fi state.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SessionDeviceSection: View {
    @Environment(BluFiSessionController.self) private var session
    let device: BluFiDiscoveredDevice

    var body: some View {
        Section("Device") {
            LabeledContent("Name", value: device.name)
            LabeledContent("Identifier", value: device.id.uuidString.lowercased())
                .font(.caption.monospaced())
            LabeledContent("RSSI", value: "\(device.rssi) dBm")

            if let version = session.deviceVersion {
                LabeledContent("BluFi Version", value: "\(version.major).\(version.minor)")
            }

            LabeledContent(
                "Security",
                value: session.securityVersion.map { "V\($0.rawValue)" } ?? "Not negotiated"
            )
        }
    }
}

private struct SessionCommandsSection: View {
    @Environment(BluFiSessionController.self) private var session

    var body: some View {
        Section("Commands") {
            Button("Establish Secure Session", systemImage: "lock.shield", action: establishSecureSession)
                .disabled(!session.phase.acceptsCommands || session.deviceVersion == nil)

            Button("Read Wi-Fi Status", systemImage: "wifi", action: readWiFiStatus)
                .disabled(!session.phase.acceptsCommands)

            Button("Scan Wi-Fi from Device", systemImage: "wifi.magnifyingglass", action: scanWiFi)
                .disabled(!session.phase.acceptsCommands)
        }
    }

    private func establishSecureSession() {
        Task { await session.negotiateSecurity() }
    }

    private func readWiFiStatus() {
        Task { await session.refreshWiFiStatus() }
    }

    private func scanWiFi() {
        Task { await session.scanDeviceWiFi() }
    }
}

private struct WiFiStatusSection: View {
    let status: BluFiWiFiStatus

    var body: some View {
        Section("Wi-Fi Status") {
            LabeledContent("Station", value: status.stationState.label)
            LabeledContent("IP Address", value: status.hasIP ? "Available" : "Unavailable")
            if let ssid = status.stationSSID {
                LabeledContent("SSID", value: ssid)
            }
            if let bssid = status.stationBSSID {
                LabeledContent("BSSID", value: bssid)
                    .font(.caption.monospaced())
            }
            if let rssi = status.stationRSSI {
                LabeledContent("RSSI", value: "\(rssi) dBm")
            }
            if let retryCount = status.stationMaximumRetry {
                LabeledContent("Maximum Retries", value: String(retryCount))
            }
            if let reason = status.failureReason {
                LabeledContent("Failure Reason", value: String(reason))
            }
        }
    }
}

private struct StationProvisioningSection: View {
    @Binding var ssid: String
    @Binding var password: String
    let send: () -> Void

    var body: some View {
        Section {
            TextField("SSID", text: $ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Send Station Configuration", systemImage: "paperplane", action: send)
                .disabled(ssid.isEmpty)
        } header: {
            Text("Provision Station Wi-Fi")
        } footer: {
            Text("The password is sent once and is never retained in session state or logs.")
        }
    }
}

private struct DeviceWiFiScanSection: View {
    let networks: [BluFiWiFiScanResult]

    var body: some View {
        Section("Device Wi-Fi Scan") {
            ForEach(networks) { network in
                LabeledContent(network.ssid, value: "\(network.rssi) dBm")
            }
        }
    }
}

private extension BluFiStationConnectionState {
    var label: String {
        switch self {
        case .connected:
            "Connected"
        case .failed:
            "Failed"
        case .connecting:
            "Connecting"
        case .noIP:
            "No IP Address"
        case let .unknown(value):
            "Unknown (\(value))"
        }
    }
}
