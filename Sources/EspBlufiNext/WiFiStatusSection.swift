import BluFiKit
import SwiftUI

struct WiFiStatusSection: View {
    let status: BluFiWiFiStatus

    var body: some View {
        Section("Wi-Fi Status") {
            LabeledContent("Station") {
                Text(status.stationState.label.appLocalizedKey)
            }
            LabeledContent("IP Address") {
                Text((status.hasIP ? "Available" : "Unavailable").appLocalizedKey)
            }
            if let ssid = status.stationSSID {
                LabeledContent("SSID", value: ssid)
            }
            if let bssid = status.stationBSSID {
                LabeledContent("BSSID", value: bssid)
                    .font(.caption.monospaced())
            }
            if let rssi = status.stationRSSI {
                LabeledContent("RSSI", value: "\(rssi) dBm")
            }
            if let retryCount = status.stationMaximumRetry {
                LabeledContent("Maximum Retries", value: String(retryCount))
            }
            if let reason = status.failureReason {
                LabeledContent("Failure Reason", value: String(reason))
            }
        }
    }
}

private extension BluFiStationConnectionState {
    var label: String {
        switch self {
        case .connected:
            "Connected"
        case .failed:
            "Failed"
        case .connecting:
            "Connecting"
        case .noIP:
            "No IP Address"
        case let .unknown(value):
            "Unknown (\(value))"
        }
    }
}
