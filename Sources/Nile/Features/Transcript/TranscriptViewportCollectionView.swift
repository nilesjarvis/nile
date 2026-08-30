import UIKit

@MainActor enum TranscriptViewportCollectionLayout {
    private static let contentTopPadding: CGFloat = 14
    private static let contentBottomPadding: CGFloat = 10

    static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(72)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: itemSize,
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = NSDirectionalEdgeInsets(
                top: contentTopPadding,
                leading: 14,
                bottom: contentBottomPadding,
                trailing: 14
            )
            return section
        }
    }

    static func makeCollectionView() -> TranscriptLayoutObservingCollectionView {
        let collectionView = TranscriptLayoutObservingCollectionView(
            frame: .zero,
            collectionViewLayout: makeLayout()
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.clipsToBounds = true
        return collectionView
    }
}

final class TranscriptLayoutObservingCollectionView: UICollectionView {
    var onLayout: (() -> Void)?

    func install(in rootView: UIView) {
        rootView.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            topAnchor.constraint(equalTo: rootView.topAnchor),
            bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
