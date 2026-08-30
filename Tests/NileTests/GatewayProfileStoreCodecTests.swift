import Foundation
import XCTest
@testable import Nile

final class GatewayProfileStoreCodecTests: XCTestCase {
    func testLegacyVersionOneMetadataDefaultsTheCleanupLedgerAndEncodesDeterministically() throws {
        let envelope = try GatewayProfileStoreCodec.decode(
            Data(#"{"profiles":[],"version":1}"#.utf8)
        )

        XCTAssertEqual(envelope.version, 1)
        XCTAssertNil(envelope.activeGatewayID)
        XCTAssertEqual(envelope.profiles.count, 0)
        XCTAssertEqual(envelope.pendingCredentialDeletions, [])
        XCTAssertEqual(
            String(
                decoding: try GatewayProfileStoreCodec.encode(envelope),
                as: UTF8.self
            ),
            #"{"pendingCredentialDeletions":[],"profiles":[],"version":1}"#
        )
    }

    func testDecodeRejectsUnsupportedAndConflictingMetadata() throws {
        XCTAssertThrowsError(
            try GatewayProfileStoreCodec.decode(
                Data(#"{"profiles":[],"version":2}"#.utf8)
            )
        ) { error in
            XCTAssertEqual(
                error as? GatewayProfileStoreError,
                .unsupportedVersion(2)
            )
        }

        let collision = Data(
            #"{"pendingCredentialDeletions":["credential-one"],"profiles":[{"baseURL":"https://gateway.example","cleartextPermission":"denied","credentialID":"credential-one","id":"gateway-one","name":"Gateway"}],"version":1}"#.utf8
        )
        XCTAssertThrowsError(
            try GatewayProfileStoreCodec.decode(collision)
        ) { error in
            XCTAssertEqual(
                error as? GatewayProfileStoreError,
                .malformedMetadata
            )
        }
    }

    func testPersistedProfileNormalizesBlankPresentationFields() throws {
        let metadata = PersistedGatewayProfile(
            id: "gateway-one",
            credentialID: "credential-one",
            name: " ",
            baseURL: "https://gateway.example/hermes",
            lastSessionID: "\n",
            cleartextPermission: .denied
        )

        let profile = try metadata.profile(token: "secret")

        XCTAssertEqual(profile.name, "gateway.example/hermes")
        XCTAssertNil(profile.lastSessionID)
        XCTAssertEqual(profile.token, "secret")
        XCTAssertEqual(profile.cleartextPermission, .denied)
    }
}
