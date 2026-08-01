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
                if (session.isConnected || session.hasSessionSnapshot), let device = session.connectedDevice {
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
    @State private var isCopyToastPresented = false
    @State private var copyToastID = UUID()

    let device: BluFiDiscoveredDevice

    var body: some View {
        Form {
            SessionDashboardHeader()

            SessionDeviceSection(device: device, onCopy: showCopyToast)
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
        .overlay(alignment: .bottom) {
            if isCopyToastPresented {
                CopyToast {
                    withAnimation(.snappy) {
                        isCopyToastPresented = false
                    }
                }
                .id(copyToastID)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isCopyToastPresented)
        .onDisappear {
            isCopyToastPresented = false
        }
    }

    private func showCopyToast() {
        copyToastID = UUID()
        withAnimation(.snappy) {
            isCopyToastPresented = true
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
            await session.scanDeviceWiFi(diagnostics: diagnostics)
        }
    }
}

private struct SessionDeviceSection: View {
    let device: BluFiDiscoveredDevice
    let onCopy: () -> Void

    var body: some View {
        Section("Device") {
            DeviceNameView(name: device.name, onCopy: onCopy)
            DeviceIdentifierView(identifier: device.id, onCopy: onCopy)
            LabeledContent("RSSI", value: "\(device.rssi) dBm")
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
            Button(action: establishSecureSession) {
                Label("Establish Secure Session", systemImage: "lock.shield")
                    .foregroundStyle(secureSessionTint)
            }
            .tint(secureSessionTint)
            .disabled(!canEstablishSecureSession)

            Button(action: readWiFiStatus) {
                Label("Read Wi-Fi Status", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(commandTint)
            }
            .tint(commandTint)
            .disabled(!canExecuteCommand)

            Button(action: scanDeviceWiFi) {
                Label("Scan Wi-Fi from Device", systemImage: "wifi")
                    .foregroundStyle(commandTint)
            }
            .tint(commandTint)
            .disabled(!canExecuteCommand)

            NavigationLink {
                ProvisioningView(
                    ssid: $stationSSID,
                    password: $stationPassword,
                    device: device,
                    send: sendStationConfiguration
                )
            } label: {
                Label("Provision Station Wi-Fi", systemImage: "paperplane")
                    .foregroundStyle(commandTint)
            }
            .tint(commandTint)
            .disabled(!canExecuteCommand)

            NavigationLink {
                CustomDataConsoleView()
            } label: {
                Label("Send and Receive Custom Data", systemImage: "terminal")
                    .foregroundStyle(commandTint)
            }
            .tint(commandTint)
            .disabled(!canExecuteCommand)
        }
    }

    private var canExecuteCommand: Bool {
        session.phase.acceptsCommands
    }

    private var canEstablishSecureSession: Bool {
        canExecuteCommand && session.deviceVersion != nil
    }

    private var commandTint: Color {
        canExecuteCommand ? .accentColor : .accentColor.opacity(0.45)
    }

    private var secureSessionTint: Color {
        canEstablishSecureSession ? .accentColor : .accentColor.opacity(0.45)
    }

    private func establishSecureSession() {
        Task { await session.negotiateSecurity(diagnostics: diagnostics) }
    }

    private func readWiFiStatus() {
        Task { await session.refreshWiFiStatus(diagnostics: diagnostics) }
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

private struct CopyToast: View {
    let dismiss: () -> Void

    var body: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else {
                    return
                }
                dismiss()
            }
    }
}
