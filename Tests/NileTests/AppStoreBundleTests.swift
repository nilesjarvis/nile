import Foundation
import XCTest

final class AppStoreBundleTests: XCTestCase {
    func testAppBundlesItsRequiredReasonAPIDeclarations() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "The app must ship its privacy manifest, including in generated projects"
        )
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let accessedAPIs = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        var reasonsByCategory: [String: [String]] = [:]
        for declaration in accessedAPIs {
            let category = try XCTUnwrap(
                declaration["NSPrivacyAccessedAPIType"] as? String
            )
            XCTAssertNil(
                reasonsByCategory[category],
                "A required API category must not have duplicate declarations"
            )
            reasonsByCategory[category] = try XCTUnwrap(
                declaration["NSPrivacyAccessedAPITypeReasons"] as? [String]
            )
        }

        // App-owned settings/consent, private cache pruning, and monotonic
        // blocking-prompt expiry are the only covered uses.
        XCTAssertEqual(reasonsByCategory, [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        ])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
    }

    func testAppDeclaresItsOperatingSystemEncryptionExemption() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool,
            false,
            "Nile currently uses only operating-system transport and storage encryption"
        )
    }

    func testAppPackagesCompleteThirdPartyLicenses() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vendorNotices = "Vendor/TextRenderer/NileTextRenderer.xcframework/"
            + "ios-arm64/NileTextRenderer.framework/Resources/ThirdPartyNotices/"
        for (name, sourcePath) in [
            ("FreeType-FTL", vendorNotices + "FreeType-FTL.txt"),
            ("HarfBuzz-COPYING", vendorNotices + "HarfBuzz-COPYING.txt"),
            ("Roboto-LICENSE", "Resources/Fonts/Roboto-LICENSE.txt"),
        ] {
            let packagedURL = try XCTUnwrap(
                Bundle.main.url(forResource: name, withExtension: "txt"),
                "Statically linked libraries must retain their licenses in the app bundle"
            )
            XCTAssertEqual(
                try Data(contentsOf: packagedURL),
                try Data(contentsOf: repositoryRoot.appendingPathComponent(sourcePath))
            )
        }
        let acknowledgementURL = try XCTUnwrap(
            Bundle.main.url(forResource: "Nile-Attributions", withExtension: "txt")
        )
        XCTAssertTrue(
            try String(contentsOf: acknowledgementURL, encoding: .utf8)
                .contains("based in part on the work of the FreeType Team")
        )
    }

    func testAppExplainsSensitivePermissionsBeforeSystemPrompts() throws {
        for key in [
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSPhotoLibraryUsageDescription",
        ] {
            let description = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: key) as? String
            )
            XCTAssertTrue(
                description.contains("Hermes gateway"),
                "\(key) must explain where the chosen content is sent"
            )
        }
        for key in ["NSFaceIDUsageDescription", "NSLocalNetworkUsageDescription"] {
            let description = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: key) as? String
            )
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
