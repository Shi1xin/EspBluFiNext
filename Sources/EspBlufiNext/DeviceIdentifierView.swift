import SwiftUI
import UIKit

struct DeviceIdentifierView: View {
    let identifier: UUID
    let onCopy: () -> Void

    init(identifier: UUID, onCopy: @escaping () -> Void = {}) {
        self.identifier = identifier
        self.onCopy = onCopy
    }

    private var fullValue: String {
        identifier.uuidString.lowercased()
    }

    private var compactValue: String {
        "\(fullValue.prefix(8))…\(fullValue.suffix(6))"
    }

    var body: some View {
        DeviceCopyableValueView(
            title: "Identifier",
            value: fullValue,
            displayValue: compactValue,
            valueFont: .body.monospaced(),
            lineLimit: 1,
            copyAccessibilityLabel: "Copy Identifier",
            onCopy: onCopy
        )
    }
}

struct DeviceNameView: View {
    let name: String
    let onCopy: () -> Void

    var body: some View {
        DeviceCopyableValueView(
            title: "Name",
            value: name,
            displayValue: name,
            valueFont: .body,
            lineLimit: 2,
            copyAccessibilityLabel: "Copy Name",
            onCopy: onCopy
        )
    }
}

private struct DeviceCopyableValueView: View {
    let title: LocalizedStringKey
    let value: String
    let displayValue: String
    let valueFont: Font
    let lineLimit: Int
    let copyAccessibilityLabel: LocalizedStringKey
    let onCopy: () -> Void

    @State private var isDetailPresented = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Button {
                    isDetailPresented = true
                } label: {
                    Text(verbatim: displayValue)
                        .font(valueFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)

                Button("Copy", systemImage: "doc.on.doc") {
                    copyValue()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(copyAccessibilityLabel)
            }
        }
        .sheet(isPresented: $isDetailPresented) {
            DeviceCopyableValueDetailView(
                title: title,
                value: value,
                copyAccessibilityLabel: copyAccessibilityLabel,
                copy: copyValue
            )
        }
    }

    private func copyValue() {
        UIPasteboard.general.string = value
        onCopy()
    }
}

private struct DeviceCopyableValueDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    let value: String
    let copyAccessibilityLabel: LocalizedStringKey
    let copy: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    Text(verbatim: value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Copy", systemImage: "doc.on.doc") {
                        copy()
                        dismiss()
                    }
                    .accessibilityLabel(copyAccessibilityLabel)
                }
            }
            .navigationTitle(title)
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
