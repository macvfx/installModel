import AppKit
import SwiftUI

enum AppTheme: String {
    case system
    case iconContrast

    var title: String {
        switch self {
        case .system: "System"
        case .iconContrast: "Magic theme"
        }
    }

    var accent: Color {
        switch self {
        case .system: .accentColor
        case .iconContrast: Color(red: 1.0, green: 0.70, blue: 0.18)
        }
    }

    var heading: Color {
        switch self {
        case .system: .primary
        case .iconContrast: Color(red: 0.27, green: 0.90, blue: 1.0)
        }
    }

    var primaryText: Color {
        switch self {
        case .system: .primary
        case .iconContrast: Color(red: 0.96, green: 0.98, blue: 1.0)
        }
    }

    var secondaryText: Color {
        switch self {
        case .system: .secondary
        case .iconContrast: Color(red: 0.74, green: 0.82, blue: 0.91)
        }
    }

    var forcedColorScheme: ColorScheme? {
        self == .iconContrast ? .dark : nil
    }
}

struct ThemedSection<Content: View>: View {
    let title: String
    let theme: AppTheme
    @ViewBuilder let content: Content

    init(title: String, theme: AppTheme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if theme == .system {
            GroupBox(title) { content }
        } else {
            GroupBox {
                content
            } label: {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.heading)
                    .padding(.bottom, 2)
            }
            .groupBoxStyle(IconContrastGroupBoxStyle())
        }
    }
}

private struct IconContrastGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
            configuration.content
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.14, blue: 0.29).opacity(0.96),
                    Color(red: 0.025, green: 0.075, blue: 0.18).opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.80, blue: 1.0).opacity(0.60),
                            Color(red: 1.0, green: 0.66, blue: 0.16).opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }
}
