import CoreBluetooth
import SwiftUI
import UIKit

struct DeviceListView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BluFiScanner.self) private var scanner
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics
    @Environment(AppSettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Devices")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            scanner.isScanning ? "Stop" : "Scan",
                            systemImage: scanner.isScanning ? "stop.fill" : "arrow.clockwise",
                            action: toggleScanning
                        )
                        .disabled(!scanner.bluetoothState.canScan)
                        .buttonStyle(.glassProminent)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
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
                    Text(scanner.emptyStateMessage.appLocalizedKey)
                    if scanner.isScanning {
                        ProgressView("Scanning")
                    }
                }
            } actions: {
                if scanner.bluetoothState.canScan {
                    Button(
                        scanner.isScanning ? "Stop Scanning" : "Start Scanning",
                        systemImage: scanner.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right",
                        action: toggleScanning
                    )
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
                            connect(to: device)
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

    private func toggleScanning() {
        scanner.namePrefix = settings.namePrefix
        scanner.toggleScanning(diagnostics: diagnostics)
    }

    private func connect(to device: BluFiDiscoveredDevice) {
        coordinator.showSession()
        Task {
            await session.connect(
                to: device,
                using: scanner,
                settings: settings,
                diagnostics: diagnostics
            )
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
    DeviceListView()
        .environment(BluFiScanner.preview())
        .environment(BluFiSessionController())
        .environment(AppCoordinator())
        .environment(BluFiDiagnosticsStore.preview())
        .environment(AppSettingsStore())
}
