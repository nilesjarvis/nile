import Foundation
import XCTest

final class RepositorySourceOfTruthTests: XCTestCase {
    func testBuildConfigurationsConfineCleartextSupportToLocalBuilds() throws {
        let localConfigurations = ["Debug", "LocalRelease"]

        for configuration in localConfigurations {
            let plistURL = repositoryRoot
                .appendingPathComponent("Config", isDirectory: true)
                .appendingPathComponent("Info-\(configuration).plist")
            let data = try Data(contentsOf: plistURL)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any]
            )
            let transportSecurity = try XCTUnwrap(
                plist["NSAppTransportSecurity"] as? [String: Any]
            )
            XCTAssertEqual(
                transportSecurity["NSAllowsArbitraryLoads"] as? Bool,
                true,
                "\(configuration) must preserve operator-entered HTTP gateways"
            )

            let configurationSource = try source(
                at: "Config/\(configuration).xcconfig"
            )
            XCTAssertTrue(
                configurationSource.contains(
                    "NILE_CLEARTEXT_GATEWAYS_SUPPORTED"
                ),
                "\(configuration) must compile the explicit approval workflow"
            )
        }

        let releaseData = try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("Config", isDirectory: true)
                .appendingPathComponent("Info-Release.plist")
        )
        let releasePlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: releaseData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertNil(
            releasePlist["NSAppTransportSecurity"],
            "Release must not ship an arbitrary-load ATS exception"
        )
        let releaseConfiguration = try source(
            at: "Config/Release.xcconfig"
        )
        XCTAssertFalse(
            releaseConfiguration.contains(
                "NILE_CLEARTEXT_GATEWAYS_SUPPORTED"
            ),
            "Release must compile out cleartext approval support"
        )

        let project = try source(at: "project.yml")
        for configuration in localConfigurations + ["Release"] {
            XCTAssertTrue(
                project.contains(
                    "\(configuration):\n          INFOPLIST_FILE: Config/Info-\(configuration).plist"
                ),
                "\(configuration) must use its verified source plist"
            )
        }
    }

    func testAcceptanceDocumentsHaveOneVisualSourceOfTruth() throws {
        let agents = try source(at: "AGENTS.md")
        let goal = try source(at: "IOS_PORT_GOAL.md")
        let readme = try source(at: "README.md")
        let architecture = try source(at: "docs/ARCHITECTURE.md")
        let nativeDesign = try source(at: "docs/IOS_NATIVE_DESIGN.md")
        let progress = try source(at: "docs/IOS_PORT_PROGRESS.md")
        let parity = try source(at: "docs/PARITY_MATRIX.md")
        let visual = try source(at: "docs/VISUAL_PARITY.md")

        let pins = [
            "bd5451da891f2d886b9bc35f8ea67d6920df1d98",
            "3b954e5844f05276d34aaee34a7d3f69169ef9f5",
            "7441e3395f9db0d8319f43bfe07dfb222777101e",
        ]
        for pin in pins {
            XCTAssertTrue(agents.contains(pin))
            XCTAssertTrue(goal.contains(pin))
            XCTAssertTrue(progress.contains(pin))
        }

        XCTAssertTrue(
            normalized(agents).contains(
                "app-owned visual parity is measured against the private Android repository"
            )
        )
        XCTAssertTrue(
            normalized(goal).contains(
                "The iOS app must preserve the Android app’s complete functionality, behavior, state handling, security guarantees, and app-owned visual design."
            )
        )
        XCTAssertTrue(
            normalized(readme).contains(
                "The governing acceptance contract remains AGENTS.md and IOS_PORT_GOAL.md"
            )
        )
        XCTAssertTrue(
            normalized(architecture).contains(
                "`AGENTS.md` and `IOS_PORT_GOAL.md` are the governing repository and acceptance contracts."
            )
        )
        XCTAssertTrue(
            normalized(nativeDesign).contains(
                "This is a historical implementation record, not an acceptance-contract override."
            )
        )
        XCTAssertTrue(
            normalized(progress).contains(
                "follows the governing Android parity contract"
            )
        )
        XCTAssertTrue(
            normalized(parity).contains(
                "Acceptance source of truth: AGENTS.md and IOS_PORT_GOAL.md"
            )
        )
        XCTAssertTrue(
            normalized(visual).contains(
                "The pinned Android N-mark remains the acceptance target"
            )
        )

        let combined = normalized(
            [readme, architecture, nativeDesign, progress, parity, visual]
                .joined(separator: "\n")
        )
        for conflictingClaim in [
            "intentionally replaces Android visual parity",
            "intentionally supersedes exact Android visual parity",
            "no longer the visual acceptance target",
            "expected to fail by design",
            "branding intentionally supersedes the pinned Android",
        ] {
            XCTAssertFalse(
                combined.contains(conflictingClaim),
                "Remove conflicting visual authority claim: \(conflictingClaim)"
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func normalized(_ source: String) -> String {
        source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
