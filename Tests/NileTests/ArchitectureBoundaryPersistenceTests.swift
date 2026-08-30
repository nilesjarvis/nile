import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testUsageStatsHasBoundedUIAndProjectionSources() throws {
        let sessionsDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Features/Sessions", isDirectory: true
        )
        let contextSource = try source(in: sessionsDirectory, named: "ContextBreakdownSheet.swift")
        let projectionSource = try source(in: sessionsDirectory, named: "GatewayStatsProjection.swift")
        let surfaceBoundaries: [(file: String, markers: [String], limit: Int)] = [
            ("GatewayStatsSheet.swift", ["struct GatewayStatsSheet"], 165),
            ("GatewayStatsContent.swift", ["struct StatsContent"], 90),
            ("GatewayStatsSummaryCards.swift", ["struct MomentumCard", "struct SummaryGrid"], 130),
            ("GatewayStatsRows.swift", ["struct StatsSection", "struct DailyUsageRow", "struct RankedUsageSection", "struct NamedStatRow"], 130),
            ("GatewayStatsHeatmap.swift", ["struct ContributionHeatmap", "private func heatmapColor("], 140),
            ("GatewayStatsFormatting.swift", ["func formatCompact(", "func formatWhole(", "func formatStatsDate(", "func formatHeatmapDate("], 55),
        ]
        let surfaceSources = try surfaceBoundaries.map {
            try source(in: sessionsDirectory, named: $0.file)
        }
        for (index, boundary) in surfaceBoundaries.enumerated() {
            boundary.markers.forEach { marker in
                XCTAssertEqual(surfaceSources.filter { $0.contains(marker) }.count, 1)
            }
            XCTAssertLessThan(surfaceSources[index].components(separatedBy: .newlines).count, boundary.limit)
        }
        let surfaceSource = surfaceSources.joined()
        for marker in ["struct ContextBreakdownSheet", "struct ActivityMomentum", "func parseStatsDay(", "func utcCalendar("] {
            XCTAssertFalse(surfaceSource.contains(marker))
        }

        for marker in ["struct ContextBreakdownSheet", "struct StackedContextBar", "func categoryColor(", "func formatContextTokens("] {
            XCTAssertTrue(contextSource.contains(marker))
        }
        XCTAssertFalse(contextSource.contains("struct ActivityMomentum"))

        for marker in ["struct ActivityMomentum", "extension GatewayStats", "struct HeatmapProjection", "func parseStatsDay(", "func utcCalendar("] {
            XCTAssertTrue(projectionSource.contains(marker))
        }
        XCTAssertFalse(projectionSource.contains("import SwiftUI"))
        XCTAssertFalse(projectionSource.contains("SessionListModel"))
        XCTAssertFalse(projectionSource.contains(": View"))

        let contextLines = contextSource.components(separatedBy: .newlines).count
        let surfaceLines = surfaceSources.map {
            $0.components(separatedBy: .newlines).count
        }.reduce(0, +)
        let projectionLines = projectionSource.components(separatedBy: .newlines).count
        XCTAssertLessThan(contextLines, 210, "Keep context composition reviewable")
        XCTAssertLessThan(surfaceLines, 650, "Keep statistics presentation bounded")
        XCTAssertLessThan(projectionLines, 190, "Keep UTC projection UI-independent")
        XCTAssertLessThan(
            contextLines + surfaceLines + projectionLines,
            1_000,
            "Do not let the split grow beyond the former mixed source"
        )
    }

    func testProtectedPersistenceMechanicsAndWriteOrderingHaveOneBoundary() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Core/Persistence", isDirectory: true)
        let sharedSource = try source(in: directory, named: "ProtectedFileStorage.swift")
        let attachmentContracts = try source(in: directory, named: "AttachmentDraftContracts.swift")
        let attachmentSources = try ["AttachmentDraftStore.swift", "AttachmentDraftStoreTransactions.swift"].map { try source(in: directory, named: $0) }
        let attachmentCore = attachmentSources[0]
        let transactionSource = attachmentSources[1]
        let profileContracts = try source(in: directory, named: "GatewayProfileContracts.swift")
        let profileStore = try source(in: directory, named: "GatewayProfileStore.swift")
        let profileCodec = try source(in: directory, named: "GatewayProfileStoreCodec.swift")
        let profileStorage = try source(in: directory, named: "GatewayProfileSecureStorage.swift")
        let storeSources = [attachmentCore] + (try ["ComposerDraftStore.swift", "GatewayProfileSecureStorage.swift", "ModelPinStore.swift", "SessionPinStore.swift"].map { try source(in: directory, named: $0) })
        for marker in ["struct ProtectedFileStorage", "static func applicationSupportURL", ".completeFileProtectionUntilFirstUserAuthentication", "isExcludedFromBackup = true", "final class OrderedPersistenceQueue", "private var tail: Task<Void, Never>?"] {
            XCTAssertTrue(sharedSource.contains(marker))
        }
        for marker in ["struct PendingAttachment:", "struct AttachmentMutationMarker:", "protocol AttachmentDraftStoring:", "enum AttachmentDraftStoreError:"] {
            XCTAssertTrue(attachmentContracts.contains(marker))
            attachmentSources.forEach { XCTAssertFalse($0.contains(marker)) }
        }
        XCTAssertFalse(attachmentContracts.contains("ProtectedFileStorage"))
        XCTAssertFalse(attachmentContracts.contains("actor ProtectedAttachmentDraftStore"))
        for marker in ["actor ProtectedAttachmentDraftStore", "private let storage: ProtectedFileStorage", "private var removedGatewayIDs", "struct AttachmentDraftEnvelope", "func loadEnvelope(", "static func validate(_ envelope:"] {
            XCTAssertTrue(attachmentCore.contains(marker)); XCTAssertFalse(transactionSource.contains(marker))
        }
        for marker in ["extension ProtectedAttachmentDraftStore", "func updateDraft(", "func beginMutation(", "func advanceMutation(", "func recoverMutation(", "func migrateRecoveredDraft(", "func clearMutation(", "func removeGateway("] {
            XCTAssertTrue(transactionSource.contains(marker)); XCTAssertFalse(attachmentCore.contains(marker))
        }
        for forbidden in ["ProtectedFileStorage", "removedGatewayIDs", "AttachmentDraftEnvelope", "maximumAttachmentBytes", "AttachmentDraftStoring", ".completeFileProtectionUntilFirstUserAuthentication", "isExcludedFromBackup = true"] {
            XCTAssertFalse(transactionSource.contains(forbidden))
        }
        let attachmentLines = attachmentSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(attachmentContracts.components(separatedBy: .newlines).count, 200)
        XCTAssertTrue(zip(attachmentLines, [185, 235]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(attachmentLines.reduce(0, +), 410)
        XCTAssertLessThan(attachmentContracts.components(separatedBy: .newlines).count + attachmentLines.reduce(0, +), 600)
        for marker in ["struct GatewayProfileSnapshot:", "protocol GatewayProfileStoring:", "protocol GatewayCredentialStoring:", "protocol GatewayProfileMetadataStoring:", "enum GatewayProfileStoreError:"] { XCTAssertTrue(profileContracts.contains(marker)); XCTAssertFalse(profileStore.contains(marker)); XCTAssertFalse(profileCodec.contains(marker)) }
        for marker in ["ProtectedFileStorage", "import Security"] { XCTAssertFalse(profileContracts.contains(marker)) }
        for marker in ["actor SecureGatewayProfileStore", "private let metadataStorage:", "private let credentialStorage:", "GatewayProfileStoreCodec.decode", "GatewayProfileStoreCodec.encode"] { XCTAssertTrue(profileStore.contains(marker)); XCTAssertFalse(profileCodec.contains(marker)) }
        for marker in ["enum GatewayProfileStoreCodec", "struct GatewayProfilesEnvelope:", "struct PersistedGatewayProfile:", "JSONDecoder()", "JSONEncoder()", "func validate()", "static func defaultName("] { XCTAssertTrue(profileCodec.contains(marker)); XCTAssertFalse(profileStore.contains(marker)) }
        for marker in ["actor SecureGatewayProfileStore", "GatewayProfileStoring", "GatewayProfileMetadataStoring", "GatewayCredentialStoring", "metadataStorage", "credentialStorage", "ProtectedFileStorage", "import Security", "Keychain"] { XCTAssertFalse(profileCodec.contains(marker)) }
        for marker in ["import Security", "actor KeychainGatewayCredentialStore", "JSONEncoder", "JSONDecoder"] { XCTAssertFalse(profileStore.contains(marker)) }
        for marker in ["actor ProtectedFileGatewayProfileMetadataStorage", "actor KeychainGatewayCredentialStore", "import Security"] { XCTAssertTrue(profileStorage.contains(marker)) }
        XCTAssertFalse(profileStorage.contains("actor SecureGatewayProfileStore"))
        let profileSources = [profileContracts, profileStore, profileCodec, profileStorage]
        XCTAssertTrue(zip(profileSources, [75, 225, 160, 125]).allSatisfy { $0.0.components(separatedBy: .newlines).count < $0.1 })
        XCTAssertLessThan(profileSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 530)
        for storeSource in storeSources {
            XCTAssertTrue(storeSource.contains("ProtectedFileStorage(")); XCTAssertFalse(storeSource.contains(".completeFileProtectionUntilFirstUserAuthentication")); XCTAssertFalse(storeSource.contains("isExcludedFromBackup = true"))
        }
        for queueSource in storeSources.suffix(2) {
            XCTAssertTrue(queueSource.contains("OrderedPersistenceQueue()")); XCTAssertFalse(queueSource.contains("private var tail: Task<Void, Never>?"))
        }
    }
}
