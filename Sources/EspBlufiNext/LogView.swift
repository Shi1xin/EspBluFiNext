import SwiftUI

struct LogView: View {
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics

    var body: some View {
        NavigationStack {
            if diagnostics.events.isEmpty, diagnostics.sessions.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "text.alignleft",
                    description: Text("Protocol and device events will appear here.")
                )
            } else {
                List {
                    if !diagnostics.sessions.isEmpty {
                        Section("Session History") {
                            ForEach(diagnostics.sessions) { session in
                                SessionHistoryRow(session: session)
                            }
                        }
                    }

                    if !diagnostics.events.isEmpty {
                        Section("Timeline") {
                            ForEach(diagnostics.events) { event in
                                DiagnosticEventRow(event: event)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", systemImage: "trash", role: .destructive) {
                    diagnostics.clear()
                }
                .disabled(diagnostics.events.isEmpty && diagnostics.sessions.isEmpty)
            }
        }
        .navigationTitle("Logs")
    }
}

private struct DiagnosticEventRow: View {
    let event: BluFiDiagnosticEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.severity.symbolName)
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                    Spacer(minLength: 4)
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(event.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let detail = event.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(event.severity == .error ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch event.severity {
        case .debug:
            .secondary
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct SessionHistoryRow: View {
    let session: BluFiSessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.deviceName)
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text(session.outcome.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.outcome.color)
            }

            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(session.eventCount) event(s) · \(session.durationLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension BluFiSessionOutcome {
    var title: String {
        switch self {
        case .active:
            "Active"
        case .disconnected:
            "Disconnected"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .active:
            .blue
        case .disconnected:
            .secondary
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }
}

private extension BluFiSessionRecord {
    var durationLabel: String {
        guard let duration else {
            return "in progress"
        }
        let seconds = max(0, Int(duration.components.seconds))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

#Preview("Logs") {
    LogView()
        .environment(BluFiDiagnosticsStore.preview())
}
