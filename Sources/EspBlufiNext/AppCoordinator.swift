import Observation

enum AppTab: Hashable {
    case devices
    case session
    case logs
}

@MainActor
@Observable
final class AppCoordinator {
    var selectedTab: AppTab = .devices

    func showSession() {
        selectedTab = .session
    }
}
