import SwiftUI

@main
struct EspBlufiNextApp: App {
    @State private var scanner = BluFiScanner()
    @State private var session = BluFiSessionController()
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 320, minHeight: 460)
                .environment(scanner)
                .environment(session)
                .environment(coordinator)
        }
        .windowResizability(.contentMinSize)
    }
}
