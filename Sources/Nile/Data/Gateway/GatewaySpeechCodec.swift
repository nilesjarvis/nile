import Foundation

struct GatewaySpeechCodec: Sendable {
    static let maximumSynthesisResponseBytes: Int64 = 16 * 1_024 * 1_024
    static let maximumTranscriptionResponseBytes: Int64 = 1_024 * 1_024
    static let maximumVoiceConfigResponseBytes: Int64 = 1_024 * 1_024

    func requireSynthesisText(_ text: String) throws {
        guard !text.isBlank else {
            throw HermesError(
                "Speech synthesis requires reply text",
                retryable: false
            )
        }
    }

    func transcriptionMIMEType(
        for audio: RecordedAudio
    ) throws -> String {
        let mimeType = audio.mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard mimeType.hasPrefix("audio/") || mimeType == "video/webm" else {
            throw HermesError(
                "Voice transcription requires an audio recording",
                retryable: false
            )
        }
        guard !audio.bytes.isEmpty,
              audio.bytes.count <= Self.maximumTranscriptionAudioBytes else {
            throw HermesError(
                "Voice recording was empty or too large",
                retryable: false
            )
        }
        return mimeType
    }

    func decodeSynthesis(
        _ result: JSONValue.Object
    ) throws -> SynthesizedSpeech {
        guard result["ok"] == .bool(true) else {
            throw HermesError(
                "Hermes did not generate reply audio",
                retryable: false
            )
        }
        let mimeType = result.string("mime_type")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard mimeType.lowercased().hasPrefix("audio/") else {
            throw HermesError(
                "Hermes returned an invalid speech audio type",
                retryable: false
            )
        }
        let prefix = "data:\(mimeType);base64,"
        let dataURL = result.string("data_url")
        guard dataURL.hasPrefix(prefix) else {
            throw HermesError(
                "Hermes returned invalid speech audio data",
                retryable: false
            )
        }
        let encoded = String(dataURL.dropFirst(prefix.count))
        guard !encoded.isEmpty,
              encoded.count <= Self.maximumSynthesisBase64Characters else {
            throw HermesError(
                "Hermes reply audio was empty or too large",
                retryable: false
            )
        }
        guard let bytes = Data(base64Encoded: encoded, options: []) else {
            throw HermesError(
                "Hermes returned invalid speech audio data",
                retryable: false
            )
        }
        guard !bytes.isEmpty,
              bytes.count <= Self.maximumSynthesisAudioBytes else {
            throw HermesError(
                "Hermes reply audio was empty or too large",
                retryable: false
            )
        }
        return SynthesizedSpeech(
            mimeType: mimeType,
            bytes: bytes,
            provider: result.optionalString("provider")
        )
    }

    func decodeTranscription(
        _ result: JSONValue.Object
    ) throws -> SpeechTranscript {
        guard result["ok"] == .bool(true),
              case let .string(transcript)? = result["transcript"] else {
            throw HermesError(
                "Hermes returned an invalid voice transcript",
                retryable: false
            )
        }
        return SpeechTranscript(
            text: transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    func decodeVoiceConfig(
        _ result: JSONValue.Object
    ) throws -> HermesVoiceConfig {
        HermesVoiceConfig(
            provider: try result.requireNonBlankString(
                method: "GET /api/niles/tts-config",
                name: "provider"
            ),
            voice: try result.requireNonBlankString(
                method: "GET /api/niles/tts-config",
                name: "voice"
            )
        )
    }

    func requireVoiceMutationValue(
        name: String,
        value: String
    ) throws {
        guard !value.isBlank else {
            throw HermesError(
                "Hermes voice settings require a \(name)",
                retryable: false
            )
        }
    }

    private static let maximumSynthesisAudioBytes = 12 * 1_024 * 1_024
    private static let maximumSynthesisBase64Characters =
        ((maximumSynthesisAudioBytes + 2) / 3) * 4
    private static let maximumTranscriptionAudioBytes = 25 * 1_024 * 1_024
}
