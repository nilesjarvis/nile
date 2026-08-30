import XCTest
@testable import Nile

final class GatewayModelArgumentPolicyTests: XCTestCase {
    func testAcceptsSafeModelAndProviderArguments() {
        for model in ["claude", "Claude Sonnet 4", "openai/gpt-5.4", "vendor:model"] {
            XCTAssertNoThrow(
                try GatewayModelArgumentPolicy.requireSafeModelName(model)
            )
        }
        for provider in ["anthropic", "openrouter.ai", "azure-openai"] {
            XCTAssertNoThrow(
                try GatewayModelArgumentPolicy.requireSafeProviderIdentifier(
                    provider
                )
            )
        }
    }

    func testRejectsUnsafeModelSpacingAndControls() {
        for model in [
            "", " claude", "claude ", "claude  sonnet", "claude\tsonnet",
            "claude\nsonnet", "claude\u{0000}sonnet",
        ] {
            assertRejected(
                model,
                message: "config.set model cannot encode that model name safely",
                using: GatewayModelArgumentPolicy.requireSafeModelName
            )
        }
    }

    func testRejectsReservedModelFlagsAndUnicodeDashVariants() {
        for model in [
            "claude --global", "claude --session", "claude --refresh",
            "claude --provider anthropic", "claude –global",
            "claude —provider anthropic",
        ] {
            assertRejected(
                model,
                message: "config.set model cannot encode that model name safely",
                using: GatewayModelArgumentPolicy.requireSafeModelName
            )
        }
    }

    func testRejectsUnsafeProviderIdentifiers() {
        for provider in [
            "", " anthropic", "anthropic ", "anthropic team",
            "anthropic\tteam", "anthropic\nteam", "--provider",
            "anthropic --global", "anthropic–refresh", "anthropic\u{0000}",
        ] {
            assertRejected(
                provider,
                message:
                    "config.set model requires a one-token provider identifier",
                using: GatewayModelArgumentPolicy.requireSafeProviderIdentifier
            )
        }
    }

    private func assertRejected(
        _ value: String,
        message: String,
        using validate: (String) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try validate(value), file: file, line: line) {
            error in
            guard let hermes = error as? HermesError else {
                return XCTFail("Expected HermesError", file: file, line: line)
            }
            XCTAssertEqual(hermes.message, message, file: file, line: line)
            XCTAssertFalse(hermes.retryable, file: file, line: line)
            XCTAssertFalse(
                hermes.requestMayHaveSucceeded,
                file: file,
                line: line
            )
        }
    }
}
