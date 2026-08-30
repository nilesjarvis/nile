import Foundation

/// Speech and global Hermes voice transport sharing the active connection.
struct GatewaySpeechService:
    HermesSpeechServing,
    HermesVoiceServing,
    Sendable
{
    private let connectionState: GatewayConnectionState
    private let dashboard: (any GatewayDashboardReading)?
    private let codec = GatewaySpeechCodec()

    init(
        connectionState: GatewayConnectionState,
        dashboard: (any GatewayDashboardReading)?
    ) {
        self.connectionState = connectionState
        self.dashboard = dashboard
    }

    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech {
        try codec.requireSynthesisText(text)
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Speech synthesis is unavailable for this connection",
                retryable: false
            )
        }
        let result: JSONValue.Object
        do {
            result = try await dashboard.sendJSON(
                connection: connection,
                method: "POST",
                pathSegments: ["audio", "speak"],
                body: ["text": .string(text)],
                maximumBytes: GatewaySpeechCodec.maximumSynthesisResponseBytes
            )
        } catch let error as HermesError
            where error.message.contains("HTTP 404") {
            throw SpeechSynthesisUnavailableError()
        }
        return try codec.decodeSynthesis(result)
    }

    func transcribeSpeech(
        audio: RecordedAudio
    ) async throws -> SpeechTranscript {
        let mimeType = try codec.transcriptionMIMEType(for: audio)
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Speech transcription is unavailable for this connection",
                retryable: false
            )
        }
        let encoded = audio.bytes.base64EncodedString()
        let result: JSONValue.Object
        do {
            result = try await dashboard.sendJSON(
                connection: connection,
                method: "POST",
                pathSegments: ["audio", "transcribe"],
                body: [
                    "data_url": .string(
                        "data:\(mimeType);base64,\(encoded)"
                    ),
                    "mime_type": .string(mimeType),
                ],
                maximumBytes:
                    GatewaySpeechCodec.maximumTranscriptionResponseBytes
            )
        } catch let error as HermesError
            where error.message.contains("HTTP 404") {
            throw SpeechTranscriptionUnavailableError()
        }
        return try codec.decodeTranscription(result)
    }

    func getHermesVoiceConfig() async throws -> HermesVoiceConfig {
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Hermes voice settings are unavailable for this connection",
                retryable: false
            )
        }
        let result = try await dashboard.getJSONWithErrorDetail(
            connection: connection,
            pathSegments: ["niles", "tts-config"],
            maximumBytes: GatewaySpeechCodec.maximumVoiceConfigResponseBytes
        )
        return try codec.decodeVoiceConfig(result)
    }

    func setHermesVoice(
        expectedProvider: String,
        voice: String
    ) async throws -> HermesVoiceConfig {
        try codec.requireVoiceMutationValue(
            name: "provider",
            value: expectedProvider
        )
        try codec.requireVoiceMutationValue(name: "voice", value: voice)
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Hermes voice settings are unavailable for this connection",
                retryable: false
            )
        }
        let result = try await dashboard.sendJSON(
            connection: connection,
            method: "PUT",
            pathSegments: ["niles", "tts-config"],
            body: [
                "provider": .string(expectedProvider),
                "voice": .string(voice),
            ],
            maximumBytes: GatewaySpeechCodec.maximumVoiceConfigResponseBytes
        )
        return try codec.decodeVoiceConfig(result)
    }
}
