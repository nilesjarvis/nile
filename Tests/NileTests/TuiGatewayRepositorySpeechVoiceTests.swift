import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testSpeechAndVoiceConfigurationUseExactDashboardContracts() async throws {
        let dashboard = RecordingVoiceDashboard(
            getResponse: [
                "provider": .string("edge"),
                "voice": .string("en-US-AriaNeural"),
            ],
            sendResponses: [
                [
                    "ok": .bool(true),
                    "mime_type": .string("audio/mpeg"),
                    "data_url": .string("data:audio/mpeg;base64,AQID"),
                    "provider": .string("edge"),
                ],
                [
                    "ok": .bool(true),
                    "transcript": .string("  provider-neutral text  "),
                    "provider": .string("future-provider"),
                ],
                [
                    "provider": .string("edge"),
                    "voice": .string("en-US-GuyNeural"),
                ],
            ]
        )
        let repository = TuiGatewayRepository(
            rpc: RecordingRPC(responses: [:]),
            connectionClient: NoopConnectionClient(),
            signals: AsyncStream { $0.finish() },
            dashboard: dashboard
        )
        try await repository.connect(connection())
        let capabilities = repository.sessionCapabilities
        let voice = repository.voiceService

        let speech = try await capabilities.speechSynthesis.synthesizeSpeech(
            text: "Hello Hermes"
        )
        let transcript = try await capabilities.transcription.transcribeSpeech(
            audio: RecordedAudio(
                mimeType: " AUDIO/WAV; codecs=pcm ",
                bytes: Data([1, 2, 3])
            )
        )
        let original = try await voice.getHermesVoiceConfig()
        let updated = try await voice.setHermesVoice(
            expectedProvider: "edge",
            voice: "en-US-GuyNeural"
        )

        XCTAssertEqual(
            speech,
            SynthesizedSpeech(
                mimeType: "audio/mpeg",
                bytes: Data([1, 2, 3]),
                provider: "edge"
            )
        )
        XCTAssertEqual(transcript.text, "provider-neutral text")
        XCTAssertEqual(
            original,
            HermesVoiceConfig(
                provider: "edge",
                voice: "en-US-AriaNeural"
            )
        )
        XCTAssertEqual(
            updated,
            HermesVoiceConfig(
                provider: "edge",
                voice: "en-US-GuyNeural"
            )
        )

        let calls = await dashboard.calls
        XCTAssertEqual(
            calls,
            [
                VoiceDashboardCall(
                    method: "POST",
                    pathSegments: ["audio", "speak"],
                    body: ["text": .string("Hello Hermes")],
                    maximumBytes: 16 * 1_024 * 1_024
                ),
                VoiceDashboardCall(
                    method: "POST",
                    pathSegments: ["audio", "transcribe"],
                    body: [
                        "data_url": .string(
                            "data:audio/wav;base64,AQID"
                        ),
                        "mime_type": .string("audio/wav"),
                    ],
                    maximumBytes: 1_024 * 1_024
                ),
                VoiceDashboardCall(
                    method: "GET",
                    pathSegments: ["niles", "tts-config"],
                    body: nil,
                    maximumBytes: 1_024 * 1_024
                ),
                VoiceDashboardCall(
                    method: "PUT",
                    pathSegments: ["niles", "tts-config"],
                    body: [
                        "provider": .string("edge"),
                        "voice": .string("en-US-GuyNeural"),
                    ],
                    maximumBytes: 1_024 * 1_024
                ),
            ]
        )
    }

    func testSpeechCodecsAndUnsupportedEndpointsFailClosed() async {
        let malformedSpeech: [JSONValue.Object] = [
            [
                "ok": .bool(false),
                "mime_type": .string("audio/mpeg"),
                "data_url": .string("data:audio/mpeg;base64,AQID"),
            ],
            [
                "ok": .bool(true),
                "mime_type": .string("text/plain"),
                "data_url": .string("data:text/plain;base64,AQID"),
            ],
            [
                "ok": .bool(true),
                "mime_type": .string("audio/mpeg"),
                "data_url": .string("data:audio/wav;base64,AQID"),
            ],
            [
                "ok": .bool(true),
                "mime_type": .string("audio/mpeg"),
                "data_url": .string("data:audio/mpeg;base64,not base64"),
            ],
            [
                "ok": .bool(true),
                "mime_type": .string("audio/mpeg"),
                "data_url": .string("data:audio/mpeg;base64,"),
            ],
        ]
        for payload in malformedSpeech {
            let dashboard = RecordingVoiceDashboard(
                getResponse: [:],
                sendResponses: [payload]
            )
            let repository = TuiGatewayRepository(
                rpc: RecordingRPC(responses: [:]),
                connectionClient: NoopConnectionClient(),
                signals: AsyncStream { $0.finish() },
                dashboard: dashboard
            )
            try? await repository.connect(connection())
            let synthesis = repository.sessionCapabilities.speechSynthesis
            await XCTAssertThrowsErrorAsync(
                try await synthesis.synthesizeSpeech(text: "reply")
            ) { error in
                XCTAssertEqual((error as? HermesError)?.retryable, false)
            }
        }

        for operation in ["synthesis", "transcription"] {
            let dashboard = RecordingVoiceDashboard(
                getResponse: [:],
                sendResponses: [],
                sendFailure: HermesError(
                    "Could not write dashboard data (HTTP 404): not found",
                    retryable: false
                )
            )
            let repository = TuiGatewayRepository(
                rpc: RecordingRPC(responses: [:]),
                connectionClient: NoopConnectionClient(),
                signals: AsyncStream { $0.finish() },
                dashboard: dashboard
            )
            try? await repository.connect(connection())
            let capabilities = repository.sessionCapabilities
            if operation == "synthesis" {
                await XCTAssertThrowsErrorAsync(
                    try await capabilities.speechSynthesis.synthesizeSpeech(
                        text: "reply"
                    )
                ) { error in
                    XCTAssertTrue(
                        error is SpeechSynthesisUnavailableError
                    )
                }
            } else {
                await XCTAssertThrowsErrorAsync(
                    try await capabilities.transcription.transcribeSpeech(
                        audio: RecordedAudio(
                            mimeType: "audio/wav",
                            bytes: Data([1])
                        )
                    )
                ) { error in
                    XCTAssertTrue(
                        error is SpeechTranscriptionUnavailableError
                    )
                }
            }
        }
    }

    func testSpeechAndVoicePreflightValidationNeverTouchesNetwork() async {
        let dashboard = RecordingVoiceDashboard(
            getResponse: [:],
            sendResponses: []
        )
        let repository = TuiGatewayRepository(
            rpc: RecordingRPC(responses: [:]),
            connectionClient: NoopConnectionClient(),
            signals: AsyncStream { $0.finish() },
            dashboard: dashboard
        )
        let capabilities = repository.sessionCapabilities
        let voice = repository.voiceService

        await XCTAssertThrowsErrorAsync(
            try await capabilities.speechSynthesis.synthesizeSpeech(
                text: " \n"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Speech synthesis requires reply text"
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await capabilities.transcription.transcribeSpeech(
                audio: RecordedAudio(
                    mimeType: "text/plain",
                    bytes: Data([1])
                )
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Voice transcription requires an audio recording"
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await capabilities.transcription.transcribeSpeech(
                audio: RecordedAudio(
                    mimeType: "audio/wav",
                    bytes: Data()
                )
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Voice recording was empty or too large"
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await voice.setHermesVoice(
                expectedProvider: "",
                voice: "en-US-AriaNeural"
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await voice.setHermesVoice(
                expectedProvider: "edge",
                voice: " "
            )
        )
        let calls = await dashboard.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testVoiceConfigurationRequiresStrictNonBlankStrings() async {
        for response: JSONValue.Object in [
            ["voice": .string("en-US-AriaNeural")],
            ["provider": .string("edge")],
            [
                "provider": .string("edge"),
                "voice": .string(" "),
            ],
            [
                "provider": .number(7),
                "voice": .string("en-US-AriaNeural"),
            ],
        ] {
            let dashboard = RecordingVoiceDashboard(
                getResponse: response,
                sendResponses: []
            )
            let repository = TuiGatewayRepository(
                rpc: RecordingRPC(responses: [:]),
                connectionClient: NoopConnectionClient(),
                signals: AsyncStream { $0.finish() },
                dashboard: dashboard
            )
            try? await repository.connect(connection())
            let voice = repository.voiceService
            await XCTAssertThrowsErrorAsync(
                try await voice.getHermesVoiceConfig()
            ) { error in
                XCTAssertEqual((error as? HermesError)?.retryable, false)
            }
        }
    }

}
