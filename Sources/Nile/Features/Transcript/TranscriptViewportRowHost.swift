import os
import SwiftUI
import UIKit

/// Owns diffable row state, SwiftUI child containment, and reusable-cell
/// installation. Scroll position and anchor state remain in the viewport
/// controller.
@MainActor
final class TranscriptViewportRowHost {
    private static let signposter = OSSignposter(
        subsystem: "com.niles.Nile",
        category: "Transcript"
    )

    private enum Section: Hashable {
        case transcript
    }

    private final class HostedRow {
        let host: UIHostingController<AnyView>
        var item: TranscriptViewportItem

        init(
            host: UIHostingController<AnyView>,
            item: TranscriptViewportItem
        ) {
            self.host = host
            self.item = item
        }
    }

    private static let cellReuseIdentifier = "TranscriptHostingCell"
    private weak var parent: UIViewController?
    private var dataSource:
        UICollectionViewDiffableDataSource<Section, String>!
    private var itemsByID: [String: TranscriptViewportItem] = [:]
    private var orderedItemIDs: [String] = []
    private var hostedRows: [String: HostedRow] = [:]
    private var actions: TranscriptViewportActions?
    private var accessibilityHidden = false

    var usesBottomAlignment: Bool {
        !orderedItemIDs.isEmpty
            && orderedItemIDs != ["transcript-launchpad"]
    }

    func install(
        collectionView: UICollectionView,
        parent: UIViewController
    ) {
        self.parent = parent
        collectionView.register(
            TranscriptHostingCell.self,
            forCellWithReuseIdentifier: Self.cellReuseIdentifier
        )
        dataSource = UICollectionViewDiffableDataSource<Section, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: Self.cellReuseIdentifier,
                    for: indexPath
                  ) as? TranscriptHostingCell else {
                return nil
            }
            self.configure(cell, for: itemID)
            return cell
        }
    }

    @discardableResult
    func update(
        items: [TranscriptViewportItem],
        actions: TranscriptViewportActions,
        resetHostedRows: Bool
    ) -> Bool {
        self.actions = actions
        let changes = TranscriptViewportChangeSet(
            previousItemsByID: itemsByID,
            previousIDs: orderedItemIDs,
            nextItems: items
        )
        if resetHostedRows {
            removeHostedRows(Set(hostedRows.keys))
        } else {
            removeHostedRows(changes.removedIDs)
        }
        itemsByID = changes.nextItemsByID
        orderedItemIDs = changes.nextIDs

        let reconfigurable = changes.changedIDs.intersection(changes.nextIDs)
        if changes.structureChanged {
            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.transcript])
            snapshot.appendItems(changes.nextIDs)
            if !reconfigurable.isEmpty {
                snapshot.reconfigureItems(Array(reconfigurable))
            }
            dataSource.apply(snapshot, animatingDifferences: false)
        } else if !reconfigurable.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(Array(reconfigurable))
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        return changes.structureChanged || !changes.changedIDs.isEmpty
    }

    func setAccessibilityHidden(_ hidden: Bool) {
        accessibilityHidden = hidden
        for hostedRow in hostedRows.values {
            hostedRow.host.view.accessibilityElementsHidden = hidden
        }
    }

    private func configure(
        _ cell: TranscriptHostingCell,
        for itemID: String
    ) {
        let signpostState = Self.signposter.beginInterval(
            "Transcript row configure"
        )
        defer {
            Self.signposter.endInterval(
                "Transcript row configure",
                signpostState
            )
        }
        guard let item = itemsByID[itemID] else {
            return
        }
        let hostedRow: HostedRow
        if let existing = hostedRows[itemID] {
            hostedRow = existing
            if existing.item != item {
                existing.item = item
                existing.host.rootView = TranscriptViewportRowFactory.make(
                    item: item,
                    actions: actions
                )
                existing.host.view.invalidateIntrinsicContentSize()
            }
        } else {
            guard let parent else {
                return
            }
            let host = UIHostingController(
                rootView: TranscriptViewportRowFactory.make(
                    item: item,
                    actions: actions
                )
            )
            host.sizingOptions = [.intrinsicContentSize]
            host.view.backgroundColor = .clear
            host.view.accessibilityElementsHidden = accessibilityHidden
            parent.addChild(host)
            host.didMove(toParent: parent)
            hostedRow = HostedRow(host: host, item: item)
            hostedRows[itemID] = hostedRow
        }
        cell.install(hostedRow.host)
    }

    private func removeHostedRows(_ ids: Set<String>) {
        for id in ids {
            guard let hostedRow = hostedRows.removeValue(forKey: id) else {
                continue
            }
            hostedRow.host.willMove(toParent: nil)
            hostedRow.host.view.removeFromSuperview()
            hostedRow.host.removeFromParent()
        }
    }
}
