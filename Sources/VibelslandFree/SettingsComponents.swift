import AppKit
import VibelslandFreeCore
import SwiftUI

struct SettingsCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            accessory
        }
        .padding(.vertical, 10)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 36)
    }
}

struct MessageRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct HealthCheckRow: View {
    let item: HealthCheckItem
    let prominent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 15 : 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: prominent ? 13 : 12, weight: .semibold))
                    StatusPill(status: item.status)
                }
                Text(item.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.status == .needsAction {
                    Text(item.suggestedAction)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }

    private var icon: String {
        switch item.status {
        case .normal: "checkmark.circle"
        case .needsAction: "exclamationmark.triangle.fill"
        case .disabled: "minus.circle"
        }
    }

    private var color: Color {
        switch item.status {
        case .normal: .green
        case .needsAction: .orange
        case .disabled: .secondary
        }
    }
}

struct StatusPill: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let status: HealthCheckStatus

    var body: some View {
        Text(status.title(language: configurationStore.config.language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .normal: .secondary
        case .needsAction: .orange
        case .disabled: .secondary
        }
    }
}

struct DiagnosticRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

struct PathRow: View {
    let title: String
    let path: String

    var body: some View {
        DiagnosticRow(title: title, value: path, monospaced: true)
    }
}
