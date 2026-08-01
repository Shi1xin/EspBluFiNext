import SwiftUI

@main
struct EspBlufiNextApp: App {
    @State private var scanner = BluFiScanner()
    @State private var session = BluFiSessionController()
    @State private var coordinator = AppCoordinator()
    @State private var diagnostics = BluFiDiagnosticsStore()
    @State private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 320, minHeight: 460)
                .environment(scanner)
                .environment(session)
                .environment(coordinator)
                .environment(diagnostics)
                .environment(settings)
                .environment(\.locale, settings.language.locale)
        }
        .windowResizability(.contentMinSize)
    }
}
