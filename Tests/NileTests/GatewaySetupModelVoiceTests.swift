import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testOpeningHermesVoiceLoadsCurrentGlobalConfig() async throws {
        let voice = ModelHermesVoiceService(
            loadResult: .success(
                HermesVoiceConfig(
                    provider: "edge",
                    voice: "en-US-AriaNeural"
                )
            )
        )
        let model = try connectedModel(voice: voice)

        model.setHermesVoiceSheetVisible(true)

        try await waitUntil { !model.isLoadingHermesVoice }
        XCTAssertTrue(model.isHermesVoiceSheetVisible)
        XCTAssertEqual(
            model.hermesVoiceConfig,
            HermesVoiceConfig(
                provider: "edge",
                voice: "en-US-AriaNeural"
            )
        )
        XCTAssertNil(model.hermesVoiceError)
        let loadCount = await voice.loadCount
        XCTAssertEqual(loadCount, 1)
    }

    func testHermesVoiceRejectsInvalidIdentifierWithoutWriting() async throws {
        let voice = ModelHermesVoiceService(
            loadResult: .success(
                HermesVoiceConfig(provider: "openai", voice: "alloy")
            )
        )
        let model = try connectedModel(voice: voice)
        model.setHermesVoiceSheetVisible(true)
        try await waitUntil { !model.isLoadingHermesVoice }

        model.applyHermesVoice(
            expectedProvider: "openai",
            voice: "not a voice"
        )

        XCTAssertEqual(
            model.hermesVoiceError,
            "Voice IDs may use letters, numbers, periods, underscores, and hyphens."
        )
        let invalidUpdateCalls = await voice.updateCalls
        XCTAssertEqual(invalidUpdateCalls, [])
    }

    func testHermesVoiceApplyTrimsAndPreventsDismissUntilCommitted() async throws {
        let voice = ModelHermesVoiceService(
            loadResult: .success(
                HermesVoiceConfig(provider: "openai", voice: "alloy")
            ),
            suspendsUpdate: true
        )
        let model = try connectedModel(voice: voice)
        model.setHermesVoiceSheetVisible(true)
        try await waitUntil { !model.isLoadingHermesVoice }

        model.applyHermesVoice(
            expectedProvider: "openai",
            voice: "  nova \n"
        )

        XCTAssertTrue(model.isUpdatingHermesVoice)
        model.setHermesVoiceSheetVisible(false)
        model.dismissSettings()
        XCTAssertTrue(model.isHermesVoiceSheetVisible)
        XCTAssertTrue(model.isSettingsVisible)
        try await waitUntil { await voice.updateCalls.count == 1 }
        let updateCalls = await voice.updateCalls
        XCTAssertEqual(
            updateCalls,
            [
                ModelHermesVoiceService.UpdateCall(
                    expectedProvider: "openai",
                    voice: "nova"
                ),
            ]
        )

        await voice.finishUpdate(
            with: .success(
                HermesVoiceConfig(provider: "openai", voice: "nova")
            )
        )
        try await waitUntil { !model.isUpdatingHermesVoice }
        XCTAssertEqual(
            model.hermesVoiceConfig,
            HermesVoiceConfig(provider: "openai", voice: "nova")
        )
        model.setHermesVoiceSheetVisible(false)
        XCTAssertFalse(model.isHermesVoiceSheetVisible)
    }

    func testClosingHermesVoiceInvalidatesLateLoad() async throws {
        let voice = ModelHermesVoiceService(
            loadResult: .success(
                HermesVoiceConfig(provider: "edge", voice: "old")
            ),
            suspendsLoad: true
        )
        let model = try connectedModel(voice: voice)
        model.setHermesVoiceSheetVisible(true)
        try await waitUntil { await voice.loadCount == 1 }

        model.setHermesVoiceSheetVisible(false)
        await voice.finishLoad(
            with: .success(
                HermesVoiceConfig(provider: "edge", voice: "late")
            )
        )
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertFalse(model.isHermesVoiceSheetVisible)
        XCTAssertFalse(model.isLoadingHermesVoice)
        XCTAssertNil(model.hermesVoiceConfig)
        XCTAssertNil(model.hermesVoiceError)
    }

    func testHermesVoiceFormatsDashboardAndUnavailableFailures() async throws {
        let voice = ModelHermesVoiceService(
            loadResult: .failure(
                HermesError(
                    "Could not read dashboard data (HTTP 500): Provider is offline"
                )
            )
        )
        let model = try connectedModel(voice: voice)
        model.setHermesVoiceSheetVisible(true)
        try await waitUntil { !model.isLoadingHermesVoice }
        XCTAssertEqual(model.hermesVoiceError, "Provider is offline")

        await voice.setLoadResult(
            .failure(
                HermesError(
                    "Could not read dashboard data (HTTP 404): Not found"
                )
            )
        )
        model.refreshHermesVoice()
        try await waitUntil { !model.isLoadingHermesVoice }
        XCTAssertEqual(
            model.hermesVoiceError,
            "This gateway does not expose app-managed Hermes voice settings."
        )
    }

    func testHermesVoicePresentationUsesExpectedPolicyCatalog() {
        XCTAssertEqual(
            [
                "edge",
                "openai",
                "elevenlabs",
                "xai",
                "minimax",
                "mistral",
                "gemini",
                "neutts",
                "kittentts",
                "piper",
                "",
            ].map(HermesVoicePresentation.providerLabel),
            [
                "Edge TTS",
                "OpenAI",
                "ElevenLabs",
                "xAI",
                "MiniMax",
                "Mistral",
                "Gemini",
                "NeuTTS",
                "KittenTTS",
                "Piper",
                "Unknown",
            ]
        )
        XCTAssertEqual(
            HermesVoicePresentation.presets(" edge ").map(\.voice),
            [
                "en-US-AriaNeural",
                "en-US-GuyNeural",
                "en-US-AvaNeural",
                "en-US-AndrewNeural",
                "en-US-EmmaNeural",
                "en-US-BrianNeural",
                "en-GB-SoniaNeural",
                "en-GB-RyanNeural",
            ]
        )
        XCTAssertEqual(
            HermesVoicePresentation.presets("openai").map(\.voice),
            ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
        )
        XCTAssertEqual(
            HermesVoicePresentation.presets("kittentts").map(\.voice),
            [
                "Jasper",
                "Bella",
                "Luna",
                "Bruno",
                "Rosie",
                "Hugo",
                "Kiki",
                "Leo",
            ]
        )
        XCTAssertTrue(
            HermesVoicePresentation.presets("custom").isEmpty
        )
    }

    func testHermesVoicePresentationNormalizesAndGatesDraftApplication() {
        XCTAssertEqual(
            HermesVoicePresentation.normalizedVoice("  nova\n"),
            "nova"
        )
        for (draft, current, enabled) in [
            ("nova", "alloy", false),
            (" \n", "alloy", true),
            (" alloy ", "alloy", true),
        ] {
            XCTAssertFalse(
                HermesVoicePresentation.canApply(
                    draftVoice: draft,
                    currentVoice: current,
                    controlsEnabled: enabled
                )
            )
        }
        XCTAssertTrue(
            HermesVoicePresentation.canApply(
                draftVoice: " nova ",
                currentVoice: "alloy",
                controlsEnabled: true
            )
        )
    }

}
