import BluFiKit
import SwiftUI

struct ProvisioningView: View {
    @Environment(BluFiSessionController.self) private var session
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics

    @Binding var ssid: String
    @Binding var password: String

    let device: BluFiDiscoveredDevice
    let send: () -> Void

    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case ssid
        case password
    }

    var body: some View {
        Form {
            Section("Target") {
                LabeledContent("Device", value: device.name)
                LabeledContent("Mode") {
                    Text("Station".appLocalizedKey)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Text("SSID")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 88, alignment: .leading)

                    TextField("Network name", text: $ssid)
                        .focused($focusedField, equals: .ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focusedField = .ssid })

                HStack(spacing: 12) {
                    Text("Password")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 88, alignment: .leading)

                    SecureField("Network password", text: $password)
                        .focused($focusedField, equals: .password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focusedField = .password })
            } header: {
                Text("Station Wi-Fi")
            } footer: {
                Text("The password is sent once and is never retained in session state or logs.")
            }

            Section {
                Button("Scan Wi-Fi Networks", systemImage: "wifi.magnifyingglass", action: scanWiFi)
                    .disabled(!session.phase.acceptsCommands || session.phase.isBusy)

                if session.phase.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(session.phase.title.appLocalizedKey)
                    }
                }

                if session.wifiNetworks.isEmpty {
                    Text("Scan from the device to choose a nearby network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.wifiNetworks) { network in
                        Button {
                            ssid = network.ssid
                            focusedField = .password
                        } label: {
                            HStack(spacing: 12) {
                                Text(network.ssid)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(network.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if ssid == network.ssid {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Nearby Wi-Fi")
            } footer: {
                Text("Networks are scanned by the ESP device over BluFi.")
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

    private func scanWiFi() {
        focusedField = nil
        Task {
            await session.scanDeviceWiFi(diagnostics: diagnostics)
        }
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
    .environment(BluFiDiagnosticsStore.preview())
}
