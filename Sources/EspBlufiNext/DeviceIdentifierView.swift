import SwiftUI
import UIKit

struct DeviceIdentifierView: View {
    let identifier: UUID
    let showsLabel: Bool

    @State private var isDetailPresented = false

    init(identifier: UUID, showsLabel: Bool = true) {
        self.identifier = identifier
        self.showsLabel = showsLabel
    }

    private var fullValue: String {
        identifier.uuidString.lowercased()
    }

    private var compactValue: String {
        "\(fullValue.prefix(8))…\(fullValue.suffix(6))"
    }

    var body: some View {
        identifierContent
            .sheet(isPresented: $isDetailPresented) {
                DeviceIdentifierDetailView(identifier: fullValue, copy: copyIdentifier)
            }
    }

    @ViewBuilder
    private var identifierContent: some View {
        if showsLabel {
            LabeledContent("Identifier") {
                identifierValue
            }
        } else {
            identifierValue
        }
    }

    private var identifierValue: some View {
        HStack(spacing: 10) {
            Button {
                isDetailPresented = true
            } label: {
                Text(verbatim: compactValue)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(
                        maxWidth: .infinity,
                        alignment: showsLabel ? .trailing : .leading
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Full Identifier")

            Button("Copy", systemImage: "doc.on.doc", action: copyIdentifier)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Copy Identifier")
        }
    }

    private func copyIdentifier() {
        UIPasteboard.general.string = fullValue
    }
}

private struct DeviceIdentifierDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let identifier: String
    let copy: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Identifier") {
                    Text(verbatim: identifier)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Copy", systemImage: "doc.on.doc", action: copy)
                }
            }
            .navigationTitle("Identifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
