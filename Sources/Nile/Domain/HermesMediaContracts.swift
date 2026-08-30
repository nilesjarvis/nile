import Foundation

struct AttachedImage: Equatable, Sendable {
    let path: String
    let filename: String
}

struct DownloadedAttachment: Equatable, Sendable {
    let path: String
    let filename: String
    let mimeType: String
    let bytes: Data
}

struct RecordedAudio: Equatable, Sendable {
    let mimeType: String
    let bytes: Data
}

struct SpeechTranscript: Equatable, Sendable {
    let text: String
}

struct SynthesizedSpeech: Equatable, Sendable {
    let mimeType: String
    let bytes: Data
    let provider: String?
}

struct HermesVoiceConfig: Equatable, Sendable {
    let provider: String
    let voice: String
}

struct SpeechSynthesisUnavailableError: LocalizedError, Sendable {
    var errorDescription: String? {
        "This Hermes server does not support spoken replies"
    }
}

struct SpeechTranscriptionUnavailableError: LocalizedError, Sendable {
    var errorDescription: String? {
        "This Hermes server does not support voice transcription"
    }
}

protocol HermesAttachmentReading: Sendable {
    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async throws -> DownloadedAttachment
}

protocol HermesAttachmentMutating: Sendable {
    func attachImage(
        liveSessionID: String,
        base64: String,
        fileExtension: String,
        filename: String
    ) async throws -> AttachedImage
    func detachImage(liveSessionID: String, path: String) async throws -> Bool
}

protocol HermesAttachmentServing:
    HermesAttachmentReading,
    HermesAttachmentMutating,
    Sendable
{}

protocol HermesTranscriptionServing: Sendable {
    func transcribeSpeech(audio: RecordedAudio) async throws -> SpeechTranscript
}

protocol HermesSpeechSynthesisServing: Sendable {
    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech
}

protocol HermesSpeechServing:
    HermesTranscriptionServing,
    HermesSpeechSynthesisServing,
    Sendable
{}

protocol HermesVoiceServing: Sendable {
    func getHermesVoiceConfig() async throws -> HermesVoiceConfig
    func setHermesVoice(
        expectedProvider: String,
        voice: String
    ) async throws -> HermesVoiceConfig
}

extension HermesAttachmentMutating {
    func attachImage(
        liveSessionID: String,
        base64: String,
        fileExtension: String,
        filename: String
    ) async throws -> AttachedImage {
        throw HermesError(
            "Photo attachments are unavailable for this repository",
            retryable: false
        )
    }

    func detachImage(
        liveSessionID: String,
        path: String
    ) async throws -> Bool {
        throw HermesError(
            "Photo attachments are unavailable for this repository",
            retryable: false
        )
    }
}

extension HermesAttachmentReading {
    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async throws -> DownloadedAttachment {
        throw HermesError(
            "Attachment downloads are unavailable for this repository",
            retryable: false
        )
    }
}

extension HermesTranscriptionServing {
    func transcribeSpeech(
        audio: RecordedAudio
    ) async throws -> SpeechTranscript {
        throw HermesError(
            "Speech transcription is unavailable for this repository",
            retryable: false
        )
    }
}

extension HermesSpeechSynthesisServing {
    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech {
        throw HermesError(
            "Speech synthesis is unavailable for this repository",
            retryable: false
        )
    }
}

extension HermesVoiceServing {
    func getHermesVoiceConfig() async throws -> HermesVoiceConfig {
        throw HermesError(
            "Hermes voice settings are unavailable for this repository",
            retryable: false
        )
    }

    func setHermesVoice(
        expectedProvider: String,
        voice: String
    ) async throws -> HermesVoiceConfig {
        throw HermesError(
            "Hermes voice settings are unavailable for this repository",
            retryable: false
        )
    }
}
