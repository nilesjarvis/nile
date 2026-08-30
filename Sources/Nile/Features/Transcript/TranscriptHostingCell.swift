import SwiftUI
import UIKit

final class TranscriptHostingCell: UICollectionViewCell {
    private weak var hostedView: UIView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    func install(_ host: UIHostingController<AnyView>) {
        if let previousCell = host.view.superview?.superview
            as? TranscriptHostingCell,
           previousCell !== self {
            previousCell.uninstall(host)
        }
        guard hostedView !== host.view else {
            return
        }
        uninstallHostedView()
        hostedView = host.view
        host.view.removeFromSuperview()
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)
        hostedConstraints = [
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }

    func uninstall(_ host: UIHostingController<AnyView>) {
        guard hostedView === host.view else {
            return
        }
        uninstallHostedView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        uninstallHostedView()
    }

    private func uninstallHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints.removeAll(keepingCapacity: true)
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(
            layoutAttributes
        )
        let targetSize = CGSize(
            width: layoutAttributes.size.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let size = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.height = max(1, ceil(size.height))
        return attributes
    }
}
