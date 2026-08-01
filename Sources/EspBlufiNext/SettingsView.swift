import SwiftUI

struct SettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(BluFiDiagnosticsStore.self) private var diagnostics
    @Environment(BluFiScanner.self) private var scanner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Name prefix", text: $settings.namePrefix)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: settings.namePrefix) { _, newValue in
                        scanner.namePrefix = newValue
                    }

                LabeledContent("Bluetooth") {
                    Text(scanner.bluetoothState.title.appLocalizedKey)
                }
            } header: {
                Text("Discovery")
            } footer: {
                Text("Leave the prefix empty to show every device advertising the BluFi service.")
            }

            Section {
                Picker("Command timeout", selection: $settings.commandTimeoutSeconds) {
                    Text("5 seconds").tag(5)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                }

                Picker("Packet length", selection: $settings.packetLengthPolicy) {
                    ForEach(BluFiPacketLengthPolicy.allCases) { policy in
                        Text(policy.title.appLocalizedKey).tag(policy)
                    }
                }
            } header: {
                Text("Session")
            } footer: {
                Text("Automatic packet length uses the negotiated CoreBluetooth write limit. 20 bytes matches the ATT baseline used by the V1 fixtures.")
            }

            Section {
                Picker("Minimum log level", selection: $settings.minimumLogSeverity) {
                    ForEach(BluFiDiagnosticSeverity.allCases, id: \.self) { severity in
                        Text(severity.title.appLocalizedKey).tag(severity)
                    }
                }
                .onChange(of: settings.minimumLogSeverity) { _, newValue in
                    diagnostics.minimumSeverity = newValue
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Persistent diagnostics contain event metadata and redacted details. Custom payload bytes stay in the active session only.")
            }

            Section("Language") {
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title.appLocalizedKey).tag(language)
                    }
                }
            }

            Section {
                LabeledContent("Reduce Motion") {
                    Text((reduceMotion ? "On" : "Off").appLocalizedKey)
                }
                LabeledContent("Reduce Transparency") {
                    Text((reduceTransparency ? "On" : "Off").appLocalizedKey)
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("These values follow the system accessibility settings. Glass surfaces switch to opaque system backgrounds when transparency is reduced.")
            }

            Section("About") {
                LabeledContent("App", value: "EspBluFiNext")
                LabeledContent("Minimum iOS", value: "iOS 26")
                LabeledContent("BluFi service", value: "FFFF")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

private extension BluFiBluetoothState {
    var title: String {
        switch self {
        case .unknown:
            "Checking"
        case .resetting:
            "Resetting"
        case .unsupported:
            "Unsupported"
        case .unauthorized:
            "Permission Required"
        case .poweredOff:
            "Off"
        case .poweredOn:
            "Ready"
        }
    }
}

private extension BluFiDiagnosticSeverity {
    var title: String {
        switch self {
        case .debug:
            "Debug"
        case .info:
            "Info"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .environment(AppSettingsStore())
    .environment(BluFiDiagnosticsStore.preview())
    .environment(BluFiScanner(startCentralManager: false))
}
