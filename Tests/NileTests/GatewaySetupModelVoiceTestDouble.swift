import Foundation
import XCTest
@testable import Nile

actor ModelHermesVoiceService: HermesVoiceServing {
    struct UpdateCall: Equatable, Sendable {
        let expectedProvider: String
        let voice: String
    }

    private var loadResult: Result<HermesVoiceConfig, any Error>
    private let suspendsLoad: Bool
    private let suspendsUpdate: Bool
    private var loadContinuation:
        CheckedContinuation<HermesVoiceConfig, any Error>?
    private var updateContinuation:
        CheckedContinuation<HermesVoiceConfig, any Error>?
    private(set) var loadCount = 0
    private(set) var updateCalls: [UpdateCall] = []

    init(
        loadResult: Result<HermesVoiceConfig, any Error>,
        suspendsLoad: Bool = false,
        suspendsUpdate: Bool = false
    ) {
        self.loadResult = loadResult
        self.suspendsLoad = suspendsLoad
        self.suspendsUpdate = suspendsUpdate
    }

    func getHermesVoiceConfig() async throws -> HermesVoiceConfig {
        loadCount += 1
        if suspendsLoad {
            return try await withCheckedThrowingContinuation {
                loadContinuation = $0
            }
        }
        return try loadResult.get()
    }

    func setHermesVoice(
        expectedProvider: String,
        voice: String
    ) async throws -> HermesVoiceConfig {
        updateCalls.append(
            UpdateCall(
                expectedProvider: expectedProvider,
                voice: voice
            )
        )
        if suspendsUpdate {
            return try await withCheckedThrowingContinuation {
                updateContinuation = $0
            }
        }
        return HermesVoiceConfig(
            provider: expectedProvider,
            voice: voice
        )
    }

    func setLoadResult(
        _ result: Result<HermesVoiceConfig, any Error>
    ) {
        loadResult = result
    }

    func finishLoad(
        with result: Result<HermesVoiceConfig, any Error>
    ) {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume(with: result)
    }

    func finishUpdate(
        with result: Result<HermesVoiceConfig, any Error>
    ) {
        let continuation = updateContinuation
        updateContinuation = nil
        continuation?.resume(with: result)
    }
}
