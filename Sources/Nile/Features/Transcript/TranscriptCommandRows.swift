import SwiftUI

struct CommandRow: View {
    let command: TranscriptCommand
    @State private var expanded = false

    private var output: String {
        command.output?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var lines: [Substring] {
        output.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private var visibleOutput: String {
        expanded || lines.count <= 10
            ? output
            : lines.prefix(10).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                Text(command.command)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if command.status == .running, output.isEmpty {
                    Text("running…")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.muted)
                }
                if lines.count > 10 {
                    Text(expanded ? "collapse" : "\(lines.count) lines")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.muted)
                }
            }
            .foregroundStyle(
                command.status == .error
                    ? NileColors.error
                    : NileColors.agent
            )

            if !visibleOutput.isEmpty {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visibleOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(
                                command.status == .error
                                    ? NileColors.error
                                    : NileColors.muted
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        if !expanded, lines.count > 10 {
                            Text("… \(lines.count - 10) more lines")
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                        }
                    }
                    .padding(8)
                }
                .background(NileColors.panelAlt)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 22)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nilePanel()
        .contentShape(Rectangle())
        .onTapGesture {
            if lines.count > 10 {
                expanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            NileAccessibilityID.commandCard(command.id)
        )
    }
}
