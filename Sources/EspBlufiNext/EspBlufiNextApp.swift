import SwiftUI

@main
struct EspBlufiNextApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No BluFi Devices",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Start scanning to find an ESP BluFi device nearby.")
            )
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scan", systemImage: "arrow.clockwise") {}
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
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
