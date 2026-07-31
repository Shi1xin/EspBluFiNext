import BluFiKit
import SwiftUI
import UIKit

@main
struct EspBlufiNextApp: App {
    @State private var scanner = BluFiScanner()
    @State private var session = BluFiSessionController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 320, minHeight: 460)
                .environment(scanner)
                .environment(session)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct RootView: View {
    @State private var selection: Tab = .devices

    var body: some View {
        TabView(selection: $selection) {
            DeviceListView {
                selection = .session
            }
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.devices)

            SessionView()
                .tabItem { Label("Session", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(Tab.session)

            LogView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
                .tag(Tab.logs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum Tab: Hashable {
    case devices
    case session
    case logs
}

private struct DeviceListView: View {
    @Environment(BluFiScanner.self) private var scanner
    @Environment(BluFiSessionController.self) private var session
    let showSession: () -> Void

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        scanner.isScanning ? "Stop" : "Scan",
                        systemImage: scanner.isScanning ? "stop.fill" : "arrow.clockwise"
                    ) {
                        scanner.toggleScanning()
                    }
                    .disabled(!scanner.bluetoothState.canScan)
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if scanner.devices.isEmpty {
            ContentUnavailableView {
                Label("No BluFi Devices", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                VStack(spacing: 8) {
                    Text(scanner.emptyStateMessage)
                    if scanner.isScanning {
                        ProgressView("Scanning")
                    }
                }
            } actions: {
                if scanner.bluetoothState.canScan {
                    Button(
                        scanner.isScanning ? "Stop Scanning" : "Start Scanning",
                        systemImage: scanner.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                    ) {
                        scanner.toggleScanning()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .accessibilityIdentifier("empty-device-state")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Nearby Devices")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(scanner.devices) { device in
                        Button {
                            showSession()
                            Task {
                                await session.connect(to: device, using: scanner)
                            }
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                        .disabled(!device.isConnectable || session.phase.isBusy)
                    }

                    Divider()
                        .padding(.vertical, 4)

                if scanner.isScanning {
                        Label("Scanning for BluFi devices", systemImage: "dot.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
        }
    }
}

private extension BluFiScanner {
    var emptyStateMessage: String {
        switch bluetoothState {
        case .unknown, .resetting:
            "Checking Bluetooth status."
        case .unsupported:
            "This device does not support Bluetooth Low Energy."
        case .unauthorized:
            "Allow Bluetooth access in Settings to scan for ESP devices."
        case .poweredOff:
            "Turn on Bluetooth to scan for an ESP BluFi device."
        case .poweredOn:
            isScanning
                ? "Looking for devices advertising the BluFi service."
                : "Start scanning to find an ESP BluFi device nearby."
        }
    }
}

private struct DeviceRow: View {
    let device: BluFiDiscoveredDevice

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(2)
                    .layoutPriority(1)
                Text(device.id.uuidString.lowercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("\(device.rssi) dBm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("device-\(device.id.uuidString)")
    }
}

#Preview("Devices") {
    DeviceListView(showSession: {})
        .environment(BluFiScanner.preview())
        .environment(BluFiSessionController())
}

private struct SessionView: View {
    @Environment(BluFiScanner.self) private var scanner
    @Environment(BluFiSessionController.self) private var session
    @State private var stationSSID = ""
    @State private var stationPassword = ""

    var body: some View {
        NavigationStack {
            Group {
                if session.isConnected, let device = session.connectedDevice {
                    sessionContent(for: device)
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
                        Button("Disconnect", systemImage: "xmark.circle") {
                            Task {
                                await session.disconnect(using: scanner)
                            }
                        }
                        .disabled(session.phase.isBusy)
                    }
                }
            }
        }
    }

    private func sessionContent(for device: BluFiDiscoveredDevice) -> some View {
        Form {
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

            Section("Commands") {
                Button("Establish Secure Session", systemImage: "lock.shield") {
                    Task {
                        await session.negotiateSecurity()
                    }
                }
                .disabled(!session.phase.acceptsCommands || session.deviceVersion == nil)

                Button("Read Wi-Fi Status", systemImage: "wifi") {
                    Task {
                        await session.refreshWiFiStatus()
                    }
                }
                .disabled(!session.phase.acceptsCommands)

                Button("Scan Wi-Fi from Device", systemImage: "wifi.magnifyingglass") {
                    Task {
                        await session.scanDeviceWiFi()
                    }
                }
                .disabled(!session.phase.acceptsCommands)
            }

            if let status = session.wifiStatus {
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

            Section {
                TextField("SSID", text: $stationSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $stationPassword)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Send Station Configuration", systemImage: "paperplane") {
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
                .disabled(!session.phase.acceptsCommands || stationSSID.isEmpty)
            } header: {
                Text("Provision Station Wi-Fi")
            } footer: {
                Text("The password is sent once and is never retained in session state or logs.")
            }

            if !session.wifiNetworks.isEmpty {
                Section("Device Wi-Fi Scan") {
                    ForEach(session.wifiNetworks) { network in
                        LabeledContent(network.ssid, value: "\(network.rssi) dBm")
                    }
                }
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

private struct LogView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Logs",
                systemImage: "text.alignleft",
                description: Text("Protocol and device events will appear here.")
            )
            .navigationTitle("Logs")
        }
    }
}
