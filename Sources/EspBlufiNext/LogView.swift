import SwiftUI
import UIKit

struct LogView: View {
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics

    @State private var filter: BluFiLogFilter = .all
    @State private var isExporting = false
    @State private var exportDocument = BluFiDiagnosticExportDocument()
    @State private var exportError: String?

    private var filteredEvents: [BluFiDiagnosticEvent] {
        switch filter {
        case .all:
            diagnostics.events
        case .errors:
            diagnostics.events.filter { $0.severity == .error }
        case .warnings:
            diagnostics.events.filter { $0.severity == .warning || $0.severity == .error }
        case .info:
            diagnostics.events.filter { $0.severity == .debug || $0.severity == .info }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !diagnostics.sessions.isEmpty {
                    Section("Session History") {
                        ForEach(diagnostics.sessions) { session in
                            SessionHistoryRow(session: session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        diagnostics.removeSession(session.id)
                                    }
                                }
                        }
                    }
                }

                if filteredEvents.isEmpty {
                    Section {
                        ContentUnavailableView(
                            filter == .all ? "No Logs" : "No Matching Logs",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Protocol and device events will appear here.")
                        )
                    }
                } else {
                    Section("Timeline") {
                        ForEach(filteredEvents) { event in
                            NavigationLink {
                                DiagnosticEventDetailView(event: event)
                            } label: {
                                DiagnosticEventRow(event: event)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(BluFiLogFilter.allCases) { filter in
                                Text(filter.title.appLocalizedKey).tag(filter)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button("Copy", systemImage: "doc.on.doc", action: copyFilteredEvents)
                        .disabled(filteredEvents.isEmpty)

                    Button("Export", systemImage: "square.and.arrow.up", action: prepareExport)
                        .disabled(diagnostics.events.isEmpty && diagnostics.sessions.isEmpty)

                    Button("Clear", systemImage: "trash", role: .destructive, action: diagnostics.clear)
                        .disabled(diagnostics.events.isEmpty && diagnostics.sessions.isEmpty)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "espblufi-diagnostics.json"
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Export Error", isPresented: exportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var exportErrorPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func copyFilteredEvents() {
        UIPasteboard.general.string = diagnostics.plainText(events: filteredEvents)
    }

    private func prepareExport() {
        do {
            exportDocument = BluFiDiagnosticExportDocument(data: try diagnostics.exportData())
            isExporting = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private enum BluFiLogFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case warnings
    case info

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "All"
        case .errors:
            "Errors"
        case .warnings:
            "Warnings and Errors"
        case .info:
            "Info and Debug"
        }
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
                    Text(event.title.appLocalizedKey)
                        .font(.body.weight(.medium))
                    Spacer(minLength: 4)
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(event.category.title.appLocalizedKey)
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

private struct DiagnosticEventDetailView: View {
    let event: BluFiDiagnosticEvent

    var body: some View {
        List {
            Section("Parsed Event") {
                LabeledContent("Category") {
                    Text(event.category.title.appLocalizedKey)
                }
                LabeledContent("Severity") {
                    Text(event.severity.rawValue.capitalized.appLocalizedKey)
                }
                LabeledContent("Time", value: event.timestamp.formatted(date: .abbreviated, time: .standard))
                if let sessionID = event.sessionID {
                    LabeledContent("Session", value: sessionID.uuidString.lowercased())
                        .font(.caption.monospaced())
                }
                if let deviceID = event.deviceID {
                    LabeledContent("Device", value: deviceID.uuidString.lowercased())
                        .font(.caption.monospaced())
                }
            }

            Section {
                Text(event.rawRepresentation)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("Raw Event")
            } footer: {
                Text("The raw view contains the persisted event envelope. Protocol payload bytes follow the redaction policy below.")
            }

            Section("Redacted Representation") {
                Text(event.detail ?? "No additional details were captured.")
                    .textSelection(.enabled)
            }

            Section("Persistent Log Policy") {
                Text("Credentials and custom payload bytes are omitted from persistent diagnostics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(event.title.appLocalizedKey)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension BluFiDiagnosticEvent {
    var rawRepresentation: String {
        let detail = detail ?? "<none>"
        return "timestamp=\(timestamp.formatted(.iso8601))\ncategory=\(category.rawValue)\nseverity=\(severity.rawValue)\ntitle=\(title)\ndetail=\(detail)"
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
                Text(session.outcome.title.appLocalizedKey)
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
