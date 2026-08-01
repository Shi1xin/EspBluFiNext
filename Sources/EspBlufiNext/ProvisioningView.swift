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
    @State private var isWiFiPickerPresented = false
    @State private var isReadingCurrentWiFi = false
    @State private var currentWiFiError: String?

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

                Button("Use Current iPhone Wi-Fi", systemImage: "iphone") {
                    fillCurrentWiFi()
                }
                .disabled(isReadingCurrentWiFi || !session.phase.acceptsCommands)

                Button("Scan Wi-Fi from Device", systemImage: "wifi.magnifyingglass") {
                    scanWiFi()
                }
                .disabled(session.phase.isBusy || !session.phase.acceptsCommands)

                if isReadingCurrentWiFi {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading Current Wi-Fi")
                    }
                }

                if let currentWiFiError {
                    Text(currentWiFiError.appLocalizedKey)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
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
        .sheet(isPresented: $isWiFiPickerPresented) {
            ProvisioningWiFiPicker(networks: session.wifiNetworks) { selectedSSID, selectedPassword in
                ssid = selectedSSID
                password = selectedPassword
                isWiFiPickerPresented = false
                focusedField = .password
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .systemBackground))
            .presentationCornerRadius(18)
        }
    }

    private func scanWiFi() {
        focusedField = nil
        currentWiFiError = nil
        Task { @MainActor in
            if await session.scanDeviceWiFi(diagnostics: diagnostics) {
                isWiFiPickerPresented = true
            }
        }
    }

    private func fillCurrentWiFi() {
        focusedField = nil
        currentWiFiError = nil
        isReadingCurrentWiFi = true
        Task { @MainActor in
            defer { isReadingCurrentWiFi = false }
            do {
                ssid = try await CurrentWiFiSSIDReader.shared.readSSID()
            } catch let error as CurrentWiFiSSIDReader.Error {
                currentWiFiError = error.localizationKey
            } catch {
                currentWiFiError = "Unable to read the current iPhone Wi-Fi network."
            }
        }
    }
}

private struct ProvisioningWiFiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var passwordFocused: Bool

    let networks: [BluFiWiFiScanResult]
    let apply: (String, String) -> Void

    @State private var selectedNetwork: BluFiWiFiScanResult?
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if networks.isEmpty {
                        ContentUnavailableView(
                            "No Wi-Fi Networks Found",
                            systemImage: "wifi.slash",
                            description: Text("The ESP device did not report any nearby Wi-Fi networks.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        Text("Networks")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(networks) { network in
                            Button {
                                selectedNetwork = network
                                passwordFocused = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text(network.ssid)
                                        .lineLimit(1)
                                        .foregroundStyle(network.id == selectedNetwork?.id ? Color.accentColor : .primary)
                                    Spacer(minLength: 8)
                                    Text("\(network.rssi) dBm")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if network.id == selectedNetwork?.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)

                            Divider()
                                .padding(.leading, 20)
                        }
                    }

                    if let selectedNetwork {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Password for \(selectedNetwork.ssid)")
                                .font(.headline)

                            SecureField("Network password", text: $password)
                                .focused($passwordFocused)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)

                            Button("Use This Network", systemImage: "checkmark") {
                                apply(selectedNetwork.ssid, password)
                                dismiss()
                            }
                            .foregroundStyle(.tint)
                        }
                        .padding(20)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Choose Wi-Fi Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
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
