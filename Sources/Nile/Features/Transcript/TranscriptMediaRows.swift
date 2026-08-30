import SwiftUI
import UIKit

struct MessageImageView: View {
    let image: MessageImage
    let maxHeight: CGFloat

    var body: some View {
        if let base64 = image.base64,
           let decoded = TranscriptImageCache.shared.image(
            forBase64: base64
           ) {
            Image(uiImage: decoded)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
                .accessibilityLabel(image.label)
        } else {
            Text("🖼  \(image.label)")
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(NileColors.panelAlt)
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        }
    }
}

struct MessageAttachmentCard: View {
    let attachment: MessageAttachment
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                if attachment.kind == .image,
                   let preview = attachment.previewBase64,
                   let image = TranscriptImageCache.shared.image(
                    forBase64: preview
                   ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .accessibilityLabel(attachment.filename)
                }
                HStack(spacing: 0) {
                    Text(kindLabel)
                        .font(
                            .system(
                                size: 10,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(NileColors.accent)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.filename)
                            .font(
                                NileTypography.bodyMedium.weight(.semibold)
                            )
                            .foregroundStyle(NileColors.text)
                            .lineLimit(1)
                        Text(
                            attachment.kind == .image
                                && attachment.previewBase64 == nil
                                ? "Preview unavailable · tap to open"
                                : "Tap to open"
                        )
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NileColors.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .nilePanel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open \(attachment.filename)"
        )
        .accessibilityIdentifier(
            NileAccessibilityID.messageAttachment(attachment.path)
        )
    }

    private var kindLabel: String {
        switch attachment.kind {
        case .image:
            "IMG"
        case .audio:
            "AUD"
        case .video:
            "VID"
        case .file:
            "FILE"
        }
    }
}
