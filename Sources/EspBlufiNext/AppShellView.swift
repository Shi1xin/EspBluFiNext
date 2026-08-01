import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        TabView(selection: $coordinator.selectedTab) {
            DeviceListView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.devices)

            SessionView()
                .tabItem { Label("Session", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.session)

            LogView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
                .tag(AppTab.logs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
