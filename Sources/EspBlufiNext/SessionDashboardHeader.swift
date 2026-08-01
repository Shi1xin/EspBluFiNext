import BluFiKit
import SwiftUI

struct SessionDashboardHeader: View {
    @Environment(BluFiSessionController.self) private var session

    let device: BluFiDiscoveredDevice

    var body: some View {
        cardContent
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if #available(iOS 26, *) {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(session.phase.title, systemImage: phaseSymbol)
                    .font(.headline)
                    .foregroundStyle(phaseColor)

                Spacer(minLength: 8)

                Text(device.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 10) {
                    statusPills
                }
            } else {
                statusPills
            }
        }
    }

    private var statusPills: some View {
        HStack(spacing: 10) {
            DashboardStatusPill(
                title: "BluFi",
                value: versionTitle,
                systemImage: "antenna.radiowaves.left.and.right"
            )
            DashboardStatusPill(
                title: "Security",
                value: securityTitle,
                systemImage: "lock.shield"
            )
            if let status = session.wifiStatus {
                DashboardStatusPill(
                    title: "Wi-Fi",
                    value: status.hasIP ? "IP Available" : status.stationState.dashboardTitle,
                    systemImage: "wifi"
                )
            }
        }
    }

    private var versionTitle: String {
        guard let version = session.deviceVersion else {
            return "Pending"
        }
        return "V\(version.major).\(version.minor)"
    }

    private var securityTitle: String {
        guard let securityVersion = session.securityVersion else {
            return "Not negotiated"
        }
        return "V\(securityVersion.rawValue)"
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
        case .idle:
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
        case .idle:
            .secondary
        }
    }
}

private struct DashboardStatusPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.regular, in: .capsule)
            } else {
                Capsule()
                    .fill(.quaternary)
            }
        }
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
    SessionDashboardHeader(
        device: BluFiDiscoveredDevice(
            id: UUID(uuidString: "98A316CD-05AC-4F00-8000-000000000001")!,
            name: "xiaozhi",
            rssi: -48,
            isConnectable: true
        )
    )
    .padding()
    .environment(BluFiSessionController())
}
