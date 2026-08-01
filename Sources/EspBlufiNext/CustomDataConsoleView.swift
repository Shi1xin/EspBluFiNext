import SwiftUI
import UIKit

struct CustomDataConsoleView: View {
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics

    @State private var format: BluFiPayloadFormat = .utf8
    @State private var outgoingText = ""
    @State private var payloadError: String?

    var body: some View {
        Form {
            Section("Format") {
                Picker("Payload format", selection: $format) {
                    ForEach(BluFiPayloadFormat.allCases) { format in
                        Text(format.title.appLocalizedKey).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $outgoingText)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)

                    if outgoingText.isEmpty {
                        Text(format.placeholder.appLocalizedKey)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }

                Button("Send Custom Data", systemImage: "arrow.up.circle", action: send)
                    .buttonStyle(.glassProminent)
                    .disabled(!session.phase.acceptsCommands || outgoingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Send")
            } footer: {
                Text("Data is sent using the selected format. Persistent diagnostics retain byte counts only.")
            }

            Section {
                Button("Wait for Custom Data", systemImage: "arrow.down.circle", action: receive)
                    .disabled(!session.phase.acceptsCommands)

                if session.phase.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(session.phase.title.appLocalizedKey)
                    }
                }
            } header: {
                Text("Receive")
            } footer: {
                Text("The app waits for one custom-data notification from the device.")
            }

            if !session.customMessages.isEmpty {
                Section {
                    ForEach(session.customMessages) { message in
                        ConsoleMessageRow(message: message, copy: copy)
                    }
                } header: {
                    HStack {
                        Text("History")
                        Spacer()
                        Button("Clear", action: session.clearCustomMessages)
                            .font(.caption)
                    }
                }
            }

            if let lastError = session.lastError {
                Section("Error") {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Custom Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Payload Error", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((payloadError ?? "").appLocalizedKey)
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { payloadError != nil },
            set: { if !$0 { payloadError = nil } }
        )
    }

    private func send() {
        do {
            let data = try BluFiPayloadCodec.decode(outgoingText, format: format)
            Task {
                let didSend = await session.sendCustomData(
                    data,
                    format: format,
                    diagnostics: diagnostics
                )
                if didSend {
                    outgoingText = ""
                }
            }
        } catch {
            if let codecError = error as? BluFiPayloadCodecError {
                payloadError = codecError.localizationKey
            } else {
                payloadError = error.localizedDescription
            }
        }
    }

    private func receive() {
        Task {
            _ = await session.receiveCustomData(format: format, diagnostics: diagnostics)
        }
    }

    private func copy(_ message: BluFiConsoleMessage) {
        UIPasteboard.general.string = message.payload
    }
}

private struct ConsoleMessageRow: View {
    let message: BluFiConsoleMessage
    let copy: (BluFiConsoleMessage) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.direction.symbolName)
                .foregroundStyle(message.direction == .sent ? Color.blue : Color.green)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.direction.title.appLocalizedKey)
                        .font(.subheadline.weight(.semibold))
                    Text(message.format.title.appLocalizedKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(message.byteCount) B")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text((message.payload.isEmpty ? "<empty>" : message.payload).appLocalizedKey)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            Button("Copy", systemImage: "doc.on.doc") {
                copy(message)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Copy payload")
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Custom Data Console") {
    NavigationStack {
        CustomDataConsoleView()
    }
    .environment(BluFiSessionController())
    .environment(BluFiDiagnosticsStore.preview())
}
