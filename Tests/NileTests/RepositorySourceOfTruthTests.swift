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

    func testRepositoryDocumentsCurrentProductContracts() throws {
        let agents = try source(at: "AGENTS.md")
        let readme = try source(at: "README.md")
        let architecture = try source(at: "docs/ARCHITECTURE.md")
        let productDesign = try source(at: "docs/PRODUCT_DESIGN.md")
        let testLab = try source(at: "docs/TEST_LAB.md")

        XCTAssertTrue(
            agents.contains(
                "Nile is a standalone native iOS client for Hermes."
            )
        )
        XCTAssertTrue(
            readme.contains(
                "Nile is a native iOS client for Hermes"
            )
        )
        XCTAssertTrue(
            architecture.contains(
                "Nile is a standalone native iOS client"
            )
        )
        XCTAssertTrue(
            productDesign.contains(
                "Nile is designed as a native iPhone application"
            )
        )
        XCTAssertTrue(
            testLab.contains(
                "The `full` lane is the final repository gate"
            )
        )
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

}
