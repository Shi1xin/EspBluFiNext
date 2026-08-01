import BluFiKit
import SwiftUI

struct ProvisioningView: View {
    @Environment(BluFiSessionController.self) private var session

    @Binding var ssid: String
    @Binding var password: String

    let device: BluFiDiscoveredDevice
    let send: () -> Void

    var body: some View {
        Form {
            Section("Target") {
                LabeledContent("Device", value: device.name)
                LabeledContent("Mode") {
                    Text("Station".appLocalizedKey)
                }
            }

            Section {
                TextField("SSID", text: $ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Station Wi-Fi")
            } footer: {
                Text("The password is sent once and is never retained in session state or logs.")
            }

            Section {
                Button("Send Station Configuration", systemImage: "paperplane", action: send)
                    .disabled(!session.phase.acceptsCommands || ssid.isEmpty)
            }

            if session.phase.isBusy {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(session.phase.title.appLocalizedKey)
                    }
                }
            }

            if case .stationConfigurationSent = session.phase {
                Section {
                    Label(
                        "The device accepted the Station configuration. Re-enter provisioning mode and reconnect to query its current Wi-Fi state.",
                        systemImage: "checkmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .navigationTitle("Provisioning")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Provisioning") {
    @Previewable @State var ssid = "Test Network"
    @Previewable @State var password = ""

    NavigationStack {
        ProvisioningView(
            ssid: $ssid,
            password: $password,
            device: BluFiDiscoveredDevice(
                id: UUID(uuidString: "98A316CD-05AC-4F00-0000-000000000001")!,
                name: "xiaozhi",
                rssi: -48,
                isConnectable: true
            ),
            send: {}
        )
    }
    .environment(BluFiSessionController())
}
