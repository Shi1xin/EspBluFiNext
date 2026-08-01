import Foundation
import Observation

enum BluFiDiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case bluetooth
    case connection
    case protocolExchange
    case security
    case command
    case provisioning
    case wiFi
    case system

    var title: String {
        switch self {
        case .bluetooth:
            "Bluetooth"
        case .connection:
            "Connection"
        case .protocolExchange:
            "Protocol"
        case .security:
            "Security"
        case .command:
            "Command"
        case .provisioning:
            "Provisioning"
        case .wiFi:
            "Wi-Fi"
        case .system:
            "System"
        }
    }

    var symbolName: String {
        switch self {
        case .bluetooth:
            "dot.radiowaves.left.and.right"
        case .connection:
            "cable.connector"
        case .protocolExchange:
            "arrow.left.arrow.right"
        case .security:
            "lock.shield"
        case .command:
            "terminal"
        case .provisioning:
            "paperplane"
        case .wiFi:
            "wifi"
        case .system:
            "gearshape"
        }
    }
}

enum BluFiDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error

    var symbolName: String {
        switch self {
        case .debug:
            "ladybug"
        case .info:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }
}

struct BluFiDiagnosticEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let sessionID: UUID?
    let deviceID: UUID?
    let category: BluFiDiagnosticCategory
    let severity: BluFiDiagnosticSeverity
    let title: String
    let detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        sessionID: UUID? = nil,
        deviceID: UUID? = nil,
        category: BluFiDiagnosticCategory,
        severity: BluFiDiagnosticSeverity = .info,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

enum BluFiSessionOutcome: String, Codable, Sendable {
    case active
    case disconnected
    case failed
    case cancelled
}

struct BluFiSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let deviceID: UUID
    let deviceName: String
    let startedAt: Date
    var endedAt: Date?
    var outcome: BluFiSessionOutcome
    var eventCount: Int

    var duration: Duration? {
        guard let endedAt else {
            return nil
        }
        return .seconds(endedAt.timeIntervalSince(startedAt))
    }
}

@MainActor
@Observable
final class BluFiDiagnosticsStore {
    private static let eventsKey = "diagnostics.events.v1"
    private static let sessionsKey = "diagnostics.sessions.v1"
    private static let defaultEventLimit = 500
    private static let defaultSessionLimit = 30

    private(set) var events: [BluFiDiagnosticEvent]
    private(set) var sessions: [BluFiSessionRecord]
    var minimumSeverity: BluFiDiagnosticSeverity

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let eventLimit: Int

    @ObservationIgnored
    private let sessionLimit: Int

    init(
        defaults: UserDefaults = .standard,
        eventLimit: Int = 500,
        sessionLimit: Int = 30
    ) {
        self.defaults = defaults
        self.eventLimit = max(1, eventLimit)
        self.sessionLimit = max(1, sessionLimit)
        events = []
        sessions = []
        minimumSeverity = defaults.string(forKey: AppSettingsStore.minimumLogSeverityKey)
            .flatMap(BluFiDiagnosticSeverity.init(rawValue:)) ?? .debug
        load()
    }

    @discardableResult
    func beginSession(for device: BluFiDiscoveredDevice, at date: Date = .now) -> UUID {
        let id = UUID()
        let record = BluFiSessionRecord(
            id: id,
            deviceID: device.id,
            deviceName: device.name,
            startedAt: date,
            endedAt: nil,
            outcome: .active,
            eventCount: 0
        )
        sessions.insert(record, at: 0)
        trimSessions()
        persist()
        return id
    }

    func record(
        category: BluFiDiagnosticCategory,
        severity: BluFiDiagnosticSeverity = .info,
        title: String,
        detail: String? = nil,
        sessionID: UUID? = nil,
        deviceID: UUID? = nil,
        at date: Date = .now
    ) {
        guard severity.priority >= minimumSeverity.priority else {
            return
        }
        let event = BluFiDiagnosticEvent(
            timestamp: date,
            sessionID: sessionID,
            deviceID: deviceID,
            category: category,
            severity: severity,
            title: title,
            detail: detail
        )
        events.insert(event, at: 0)
        if let sessionID, let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].eventCount += 1
        }
        trimEvents()
        persist()
    }

    func finishSession(
        _ sessionID: UUID,
        outcome: BluFiSessionOutcome,
        at date: Date = .now
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        sessions[index].endedAt = date
        sessions[index].outcome = outcome
        persist()
    }

    func clear() {
        events.removeAll()
        sessions.removeAll()
        defaults.removeObject(forKey: Self.eventsKey)
        defaults.removeObject(forKey: Self.sessionsKey)
    }

    private func trimEvents() {
        guard events.count > eventLimit else {
            return
        }
        events.removeLast(events.count - eventLimit)
    }

    private func trimSessions() {
        guard sessions.count > sessionLimit else {
            return
        }
        sessions.removeLast(sessions.count - sessionLimit)
    }

    private func persist() {
        let encoder = JSONEncoder()
        guard let encodedEvents = try? encoder.encode(events),
              let encodedSessions = try? encoder.encode(sessions) else {
            return
        }
        defaults.set(encodedEvents, forKey: Self.eventsKey)
        defaults.set(encodedSessions, forKey: Self.sessionsKey)
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Self.eventsKey),
           let storedEvents = try? decoder.decode([BluFiDiagnosticEvent].self, from: data) {
            events = Array(storedEvents.prefix(eventLimit))
        }
        if let data = defaults.data(forKey: Self.sessionsKey),
           let storedSessions = try? decoder.decode([BluFiSessionRecord].self, from: data) {
            sessions = Array(storedSessions.prefix(sessionLimit))
        }
    }

    static func preview() -> BluFiDiagnosticsStore {
        let suiteName = "EspBluFiNext.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = BluFiDiagnosticsStore(defaults: defaults)
        let device = BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )
        let sessionID = store.beginSession(for: device, at: .now.addingTimeInterval(-18))
        store.record(
            category: .connection,
            title: "Connected and GATT ready",
            sessionID: sessionID,
            deviceID: device.id,
            at: .now.addingTimeInterval(-15)
        )
        store.record(
            category: .security,
            title: "Secure session established",
            detail: "Security V1",
            sessionID: sessionID,
            deviceID: device.id,
            at: .now.addingTimeInterval(-11)
        )
        store.record(
            category: .wiFi,
            title: "Wi-Fi status received",
            detail: "Station Connected · IP Available",
            sessionID: sessionID,
            deviceID: device.id,
            at: .now.addingTimeInterval(-4)
        )
        store.finishSession(sessionID, outcome: .active)
        return store
    }
}

private extension BluFiDiagnosticSeverity {
    var priority: Int {
        switch self {
        case .debug:
            0
        case .info:
            1
        case .warning:
            2
        case .error:
            3
        }
    }
}
