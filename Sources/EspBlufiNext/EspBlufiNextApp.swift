import SwiftUI

@main
struct EspBlufiNextApp: App {
    @State private var scanner = BluFiScanner()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(scanner)
        }
    }
}

private struct RootView: View {
    @State private var selection: Tab = .devices

    var body: some View {
        TabView(selection: $selection) {
            DeviceListView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.devices)

            SessionView()
                .tabItem { Label("Session", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(Tab.session)

            LogView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
                .tag(Tab.logs)
        }
    }
}

private enum Tab: Hashable {
    case devices
    case session
    case logs
}

private struct DeviceListView: View {
    @Environment(BluFiScanner.self) private var scanner

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
            List {
                Section("Nearby Devices") {
                    ForEach(scanner.devices) { device in
                        DeviceRow(device: device)
                    }
                }

                if scanner.isScanning {
                    Section {
                        Label("Scanning for BluFi devices", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        HStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.id.uuidString.lowercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Text("\(device.rssi) dBm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("device-\(device.id.uuidString)")
    }
}

#Preview("Devices") {
    DeviceListView()
        .environment(BluFiScanner.preview())
}

private struct SessionView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Active Session",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: Text("Connect to a device to inspect BluFi status and send commands.")
            )
            .navigationTitle("Session")
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
