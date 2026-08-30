import SwiftUI

struct SessionLaunchpadQuickStart: Equatable, Identifiable {
    let label: String
    let description: String
    let value: String

    var id: String { value }
}

extension Optional where Wrapped == CommandCatalog {
    var launchpadQuickStarts: [SessionLaunchpadQuickStart] {
        let safeRegistryCommands = Set([
            "/help",
            "/usage",
            "/sessions",
            "/skills",
            "/model",
        ])
        var discovered: [CommandInfo] = []
        if let catalog = self {
            discovered.append(contentsOf: catalog.skillCommands.prefix(2))
            discovered.append(
                contentsOf: catalog.categories
                    .flatMap(\.commands)
                    .filter { safeRegistryCommands.contains($0.name) }
            )
        }
        var seenDiscoveredNames = Set<String>()
        let discoveredStarts = discovered.compactMap {
            info -> SessionLaunchpadQuickStart? in
            guard seenDiscoveredNames.insert(info.name).inserted else {
                return nil
            }
            let words = info.name
                .drop(while: { $0 == "/" })
                .replacingOccurrences(of: "_", with: " ")
            let label =
                words.prefix(1).uppercased() + String(words.dropFirst())
            return SessionLaunchpadQuickStart(
                label: label,
                description: info.description,
                value: info.name
            )
        }
        let fallbacks = [
            SessionLaunchpadQuickStart(
                label: "Plan a task",
                description: "Turn an idea into clear next steps",
                value: "Help me make a clear plan for "
            ),
            SessionLaunchpadQuickStart(
                label: "Inspect something",
                description: "Understand a system, file, or problem",
                value: "Help me inspect "
            ),
            SessionLaunchpadQuickStart(
                label: "Browse commands",
                description: "See what this Hermes agent can do",
                value: "/"
            ),
        ]
        var seenValues = Set<String>()
        return (discoveredStarts + fallbacks).filter {
            seenValues.insert($0.value).inserted
        }
        .prefix(3)
        .map { $0 }
    }
}

struct SessionLaunchpad: View {
    let quickStarts: [SessionLaunchpadQuickStart]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What should we build?")
                .font(NileTypography.titleLarge)
                .fontWeight(.medium)
                .foregroundStyle(NileColors.text)
            Text("Ask Nile to plan, inspect, edit, and verify.")
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
            Spacer()
                .frame(height: 4)
            ForEach(Array(quickStarts.enumerated()), id: \.element.id) {
                index,
                quickStart in
                Button {
                    onSelect(quickStart.value)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(quickStart.label)
                                .font(
                                    NileTypography.bodyMedium.weight(
                                        .medium
                                    )
                                )
                                .foregroundStyle(NileColors.text)
                            Text(quickStart.description)
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("→")
                            .font(NileTypography.titleMedium)
                            .foregroundStyle(NileColors.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(NileColors.surfaceRaised)
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.card)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: NileRadii.card)
                            .stroke(
                                NileColors.border.opacity(0.45),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    NileAccessibilityID.sessionLaunchpadQuickStart(index)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NileAccessibilityID.sessionLaunchpad)
    }
}
