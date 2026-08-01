import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BluFiDiagnosticExport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let redactionPolicy: String
    let sessions: [BluFiSessionRecord]
    let events: [BluFiDiagnosticEvent]
}

struct BluFiDiagnosticExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension BluFiDiagnosticsStore {
    func exportData() throws -> Data {
        let export = BluFiDiagnosticExport(
            schemaVersion: 1,
            generatedAt: .now,
            redactionPolicy: "Persistent events contain metadata only; credentials and custom payload bytes are omitted.",
            sessions: sessions,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func plainText(events: [BluFiDiagnosticEvent]) -> String {
        events.map { event in
            let detail = event.detail.map { " · \($0)" } ?? ""
            return "[\(event.timestamp.formatted(.iso8601))] [\(event.severity.rawValue)] \(event.title)\(detail)"
        }.joined(separator: "\n")
    }
}
