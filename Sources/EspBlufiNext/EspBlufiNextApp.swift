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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusCard

                    if scanner.devices.isEmpty {
                        emptyState
                    } else {
                        deviceSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 96)
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
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

    private var statusCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: scanner.bluetoothState.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scanner.bluetoothState.title)
                        .font(.subheadline.weight(.semibold))
                    Text(scanner.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if scanner.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 6) {
                    Text("No BluFi Devices")
                        .font(.headline)
                    Text(scanner.emptyStateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if scanner.bluetoothState.canScan {
                        Button(
                            scanner.isScanning ? "Stop Scanning" : "Start Scanning",
                            systemImage: scanner.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                        ) {
                            scanner.toggleScanning()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .accessibilityIdentifier("empty-device-state")
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby Devices")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(scanner.devices.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            deviceCards
        }
    }

    @ViewBuilder
    private var deviceCards: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                cardsStack
            }
        } else {
            cardsStack
        }
    }

    private var cardsStack: some View {
        LazyVStack(spacing: 12) {
            ForEach(scanner.devices) { device in
                DeviceRow(device: device)
            }
        }
    }
}

private extension BluFiScanner {
    var statusDescription: String {
        switch bluetoothState {
        case .unknown, .resetting:
            "Checking the Bluetooth connection."
        case .unsupported:
            "This device does not support Bluetooth Low Energy."
        case .unauthorized:
            "Allow Bluetooth access in Settings to scan for ESP devices."
        case .poweredOff:
            "Turn on Bluetooth to scan for an ESP BluFi device."
        case .poweredOn:
            isScanning
                ? "Scanning for devices advertising the BluFi service."
                : "Ready to scan for nearby ESP BluFi devices."
        }
    }

    var emptyStateMessage: String {
        switch bluetoothState {
        case .unknown, .resetting:
            "The app is waiting for Bluetooth to become ready."
        case .unsupported:
            "This device does not support Bluetooth Low Energy."
        case .unauthorized:
            "Allow Bluetooth access in Settings, then return to scan."
        case .poweredOff:
            "Turn on Bluetooth, then tap Scan to search nearby."
        case .poweredOn:
            isScanning
                ? "Scanning for the BluFi service."
                : "Tap Start Scanning to search nearby."
        }
    }
}

private struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

private struct DeviceRow: View {
    let device: BluFiDiscoveredDevice

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.tint.opacity(0.14))
                        .frame(width: 44, height: 44)

                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(device.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 4)

                        Text("\(device.rssi) dBm")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Label("BluFi", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(shortIdentifier)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("device-\(device.id.uuidString)")
    }

    private var shortIdentifier: String {
        let identifier = device.id.uuidString.lowercased()
        guard identifier.count > 13 else {
            return identifier
        }
        return "\(identifier.prefix(8))…\(identifier.suffix(4))"
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
