import SwiftUI

struct SlashCommandPalette: View {
    @Bindable var model: SessionListModel

    private var browsing: Bool {
        model.composer.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) == "/"
    }

    private var hasRows: Bool {
        browsing
            ? model.commandCatalog != nil
            : !model.slashCompletions.isEmpty
    }

    private var skillNames: Set<String> {
        Set(
            model.commandCatalog?.skillCommands.map {
                $0.name.trimmingPrefix("/")
            } ?? []
        )
    }

    var body: some View {
        if model.composer.hasPrefix("/"),
           !model.composer.contains("\n"),
           hasRows {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if browsing, let catalog = model.commandCatalog {
                        ForEach(
                            Array(catalog.categories.enumerated()),
                            id: \.offset
                        ) { _, category in
                            if !category.commands.isEmpty {
                                categoryLabel(category.name)
                                ForEach(category.commands, id: \.name) { info in
                                    row(
                                        display: info.name,
                                        meta: info.description,
                                        skill: false
                                    ) {
                                        model.pickCatalogCommand(info.name)
                                    }
                                }
                            }
                        }
                        if !catalog.skillCommands.isEmpty {
                            categoryLabel(
                                "Skills · \(catalog.skillCommands.count)"
                            )
                            ForEach(catalog.skillCommands, id: \.name) { info in
                                row(
                                    display: info.name,
                                    meta: info.description,
                                    skill: true
                                ) {
                                    model.pickCatalogCommand(info.name)
                                }
                            }
                        }
                    } else {
                        ForEach(
                            model.slashCompletions,
                            id: \.completionID
                        ) { item in
                            row(
                                display: item.display,
                                meta: item.meta,
                                skill: skillNames.contains(
                                    item.text.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                )
                            ) {
                                model.applySlashCompletion(item.text)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(NileColors.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .accessibilityIdentifier(NileAccessibilityID.commandPalette)
        }
    }

    private func categoryLabel(_ name: String) -> some View {
        Text(name.uppercased())
            .font(NileTypography.labelMedium)
            .foregroundStyle(NileColors.muted)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(
        display: String,
        meta: String,
        skill: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(display)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NileColors.agent)
                    .lineLimit(1)
                if skill {
                    Text("skill")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.agent)
                        .padding(.horizontal, 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    NileColors.agent.opacity(0.45),
                                    lineWidth: 1
                                )
                        }
                }
                Text(meta)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            NileAccessibilityID.commandPaletteItem(display)
        )
    }
}

private extension SlashCompletion {
    var completionID: String {
        "\(display)|\(text)"
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        String(drop(while: { $0 == prefix }))
    }
}
