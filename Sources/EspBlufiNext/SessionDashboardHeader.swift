import BluFiKit
import SwiftUI

struct SessionDashboardHeader: View {
    @Environment(BluFiSessionController.self) private var session

    let device: BluFiDiscoveredDevice

    var body: some View {
        cardContent
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phaseSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.phase.title.appLocalizedKey)
                        .font(.headline)
                        .foregroundStyle(phaseColor)
                        .lineLimit(2)

                    Text(verbatim: device.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)
            }

            Divider()

            statusMetricLayout

            if let lastError = session.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .stationConfigurationSent = session.phase {
                Text("The device accepted the Station configuration without a status report. Re-enter provisioning mode and reconnect to query its current Wi-Fi state.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusMetricRow: some View {
        HStack(spacing: 0) {
            DashboardStatusMetric(
                title: "BluFi",
                value: versionTitle,
                valueIsLocalized: versionIsLocalized
            )
            metricDivider
            DashboardStatusMetric(
                title: "Security",
                value: securityTitle,
                valueIsLocalized: securityIsLocalized
            )
            if let status = session.wifiStatus {
                metricDivider
                DashboardStatusMetric(
                    title: "Wi-Fi",
                    value: status.hasIP ? "IP Available" : status.stationState.dashboardTitle,
                    valueIsLocalized: true
                )
            }
        }
    }

    private var statusMetricLayout: some View {
        ViewThatFits(in: .horizontal) {
            statusMetricRow
            ScrollView(.horizontal, showsIndicators: false) {
                statusMetricRow
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 34)
            .padding(.horizontal, 12)
    }

    private var versionTitle: String {
        guard let version = session.deviceVersion else {
            return "Pending"
        }
        return "V\(version.major).\(version.minor)"
    }

    private var versionIsLocalized: Bool {
        session.deviceVersion == nil
    }

    private var securityTitle: String {
        guard let securityVersion = session.securityVersion else {
            return "Not negotiated"
        }
        return "V\(securityVersion.rawValue)"
    }

    private var securityIsLocalized: Bool {
        session.securityVersion == nil
    }

    private var phaseSymbol: String {
        switch session.phase {
        case .failed:
            "exclamationmark.triangle"
        case .connecting, .securing, .working:
            "arrow.triangle.2.circlepath"
        case .secured:
            "lock.shield.fill"
        case .ready, .stationConfigurationSent:
            "checkmark.circle"
        case .idle, .disconnected:
            "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .failed:
            .red
        case .connecting, .securing, .working:
            .orange
        case .secured, .ready, .stationConfigurationSent:
            .green
        case .idle, .disconnected:
            .secondary
        }
    }
}

private struct DashboardStatusMetric: View {
    let title: String
    let value: String
    let valueIsLocalized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.appLocalizedKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if valueIsLocalized {
                Text(value.appLocalizedKey)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(verbatim: value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension BluFiStationConnectionState {
    var dashboardTitle: String {
        switch self {
        case .connected:
            "Connected"
        case .failed:
            "Failed"
        case .connecting:
            "Connecting"
        case .noIP:
            "No IP"
        case let .unknown(value):
            "Unknown (\(value))"
        }
    }
}

#Preview("Session Dashboard Header") {
    Form {
        SessionDashboardHeader(
            device: BluFiDiscoveredDevice(
                id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
                name: "xiaozhi",
                rssi: -48,
                isConnectable: true
            )
        )
        .listRowSeparator(.hidden)
    }
    .environment(BluFiSessionController())
}
