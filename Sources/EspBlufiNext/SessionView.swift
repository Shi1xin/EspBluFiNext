import BluFiKit
import SwiftUI

struct SessionView: View {
    @Environment(BluFiScanner.self) private var scanner
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics
    @Environment(AppSettingsStore.self) private var settings

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
                    SessionUnavailableView(
                        title: "Connection Failed",
                        systemImage: "exclamationmark.triangle",
                        message: lastError,
                        canReconnect: session.canReconnect,
                        reconnect: reconnect
                    )
                } else {
                    SessionUnavailableView(
                        title: "No Active Session",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        message: "Connect to a device to inspect BluFi status and send commands.",
                        canReconnect: session.canReconnect,
                        reconnect: reconnect
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
                } else if session.canReconnect {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reconnect", systemImage: "arrow.clockwise", action: reconnect)
                            .accessibilityLabel("Reconnect")
                    }
                }
            }
        }
    }

    private func disconnect() {
        Task {
            await session.disconnect(using: scanner, diagnostics: diagnostics)
        }
    }

    private func reconnect() {
        Task {
            await session.reconnect(using: scanner, settings: settings, diagnostics: diagnostics)
        }
    }
}

private struct SessionUnavailableView: View {
    let title: String
    let systemImage: String
    let message: String
    let canReconnect: Bool
    let reconnect: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title.appLocalizedKey, systemImage: systemImage)
        } description: {
            Text(message.appLocalizedKey)
        } actions: {
            if canReconnect {
                Button("Reconnect", systemImage: "arrow.clockwise", action: reconnect)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SessionDetailView: View {
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics
    @State private var stationSSID = ""
    @State private var stationPassword = ""
    @State private var isDeviceWiFiPickerPresented = false

    let device: BluFiDiscoveredDevice

    var body: some View {
        Form {
            SessionDashboardHeader(device: device)

            SessionDeviceSection(device: device)
            SessionCommandsSection(
                device: device,
                stationSSID: $stationSSID,
                stationPassword: $stationPassword,
                sendStationConfiguration: sendStationConfiguration,
                scanDeviceWiFi: scanDeviceWiFi
            )

            if let status = session.wifiStatus {
                WiFiStatusSection(status: status)
            }

            if !session.wifiNetworks.isEmpty {
                DeviceWiFiScanSection(networks: session.wifiNetworks)
            }
        }
        .sheet(isPresented: $isDeviceWiFiPickerPresented) {
            DeviceWiFiPicker(
                networks: session.wifiNetworks,
                selectedSSID: stationSSID
            ) { selectedSSID in
                stationSSID = selectedSSID
                isDeviceWiFiPickerPresented = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func sendStationConfiguration() {
        Task {
            let didProvision = await session.provisionStation(
                ssid: stationSSID,
                password: stationPassword,
                diagnostics: diagnostics
            )
            if didProvision {
                stationPassword = ""
            }
        }
    }

    private func scanDeviceWiFi() {
        Task {
            if await session.scanDeviceWiFi(diagnostics: diagnostics) {
                isDeviceWiFiPickerPresented = true
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

            LabeledContent("Security") {
                Text((session.securityVersion.map { "V\($0.rawValue)" } ?? "Not negotiated").appLocalizedKey)
            }
        }
    }
}

private struct SessionCommandsSection: View {
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics

    let device: BluFiDiscoveredDevice
    @Binding var stationSSID: String
    @Binding var stationPassword: String
    let sendStationConfiguration: () -> Void
    let scanDeviceWiFi: () -> Void

    var body: some View {
        Section("Commands") {
            Button("Establish Secure Session", systemImage: "lock.shield", action: establishSecureSession)
                .disabled(!session.phase.acceptsCommands || session.deviceVersion == nil)

            Button("Read Wi-Fi Status", systemImage: "wifi", action: readWiFiStatus)
                .disabled(!session.phase.acceptsCommands)

            Button("Scan Wi-Fi from Device", systemImage: "wifi.magnifyingglass", action: scanDeviceWiFi)
                .disabled(!session.phase.acceptsCommands)

            NavigationLink {
                ProvisioningView(
                    ssid: $stationSSID,
                    password: $stationPassword,
                    device: device,
                    send: sendStationConfiguration
                )
            } label: {
                Label("Provision Station Wi-Fi", systemImage: "paperplane")
            }
            .disabled(!session.phase.acceptsCommands)

            NavigationLink {
                CustomDataConsoleView()
            } label: {
                Label("Send and Receive Custom Data", systemImage: "terminal")
            }
            .disabled(!session.phase.acceptsCommands)
        }
    }

    private func establishSecureSession() {
        Task { await session.negotiateSecurity(diagnostics: diagnostics) }
    }

    private func readWiFiStatus() {
        Task { await session.refreshWiFiStatus(diagnostics: diagnostics) }
    }
}

private struct DeviceWiFiPicker: View {
    @Environment(\.dismiss) private var dismiss

    let networks: [BluFiWiFiScanResult]
    let selectedSSID: String
    let select: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if networks.isEmpty {
                    ContentUnavailableView(
                        "No Wi-Fi Networks Found",
                        systemImage: "wifi.slash",
                        description: Text("The ESP device did not report any nearby Wi-Fi networks.")
                    )
                } else {
                    List(networks) { network in
                        Button {
                            select(network.ssid)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(network.ssid)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(network.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if network.ssid == selectedSSID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Wi-Fi Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WiFiStatusSection: View {
    let status: BluFiWiFiStatus

    var body: some View {
        Section("Wi-Fi Status") {
            LabeledContent("Station") {
                Text(status.stationState.label.appLocalizedKey)
            }
            LabeledContent("IP Address") {
                Text((status.hasIP ? "Available" : "Unavailable").appLocalizedKey)
            }
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
