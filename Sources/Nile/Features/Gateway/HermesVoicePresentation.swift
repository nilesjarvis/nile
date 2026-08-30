import Foundation

struct HermesVoicePreset: Identifiable, Equatable {
    let voice: String
    let label: String

    var id: String { voice }
}

enum HermesVoicePresentation {
    private static let presetsByProvider: [String: [HermesVoicePreset]] = [
        "edge": [
            HermesVoicePreset(
                voice: "en-US-AriaNeural",
                label: "Aria · US"
            ),
            HermesVoicePreset(
                voice: "en-US-GuyNeural",
                label: "Guy · US"
            ),
            HermesVoicePreset(
                voice: "en-US-AvaNeural",
                label: "Ava · US"
            ),
            HermesVoicePreset(
                voice: "en-US-AndrewNeural",
                label: "Andrew · US"
            ),
            HermesVoicePreset(
                voice: "en-US-EmmaNeural",
                label: "Emma · US"
            ),
            HermesVoicePreset(
                voice: "en-US-BrianNeural",
                label: "Brian · US"
            ),
            HermesVoicePreset(
                voice: "en-GB-SoniaNeural",
                label: "Sonia · UK"
            ),
            HermesVoicePreset(
                voice: "en-GB-RyanNeural",
                label: "Ryan · UK"
            ),
        ],
        "openai": [
            HermesVoicePreset(voice: "alloy", label: "Alloy"),
            HermesVoicePreset(voice: "echo", label: "Echo"),
            HermesVoicePreset(voice: "fable", label: "Fable"),
            HermesVoicePreset(voice: "onyx", label: "Onyx"),
            HermesVoicePreset(voice: "nova", label: "Nova"),
            HermesVoicePreset(voice: "shimmer", label: "Shimmer"),
        ],
        "kittentts": [
            HermesVoicePreset(voice: "Jasper", label: "Jasper"),
            HermesVoicePreset(voice: "Bella", label: "Bella"),
            HermesVoicePreset(voice: "Luna", label: "Luna"),
            HermesVoicePreset(voice: "Bruno", label: "Bruno"),
            HermesVoicePreset(voice: "Rosie", label: "Rosie"),
            HermesVoicePreset(voice: "Hugo", label: "Hugo"),
            HermesVoicePreset(voice: "Kiki", label: "Kiki"),
            HermesVoicePreset(voice: "Leo", label: "Leo"),
        ],
    ]

    static func presets(_ provider: String) -> [HermesVoicePreset] {
        presetsByProvider[
            provider.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        ] ?? []
    }

    static func providerLabel(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return switch normalized.lowercased() {
        case "edge": "Edge TTS"
        case "openai": "OpenAI"
        case "elevenlabs": "ElevenLabs"
        case "xai": "xAI"
        case "minimax": "MiniMax"
        case "mistral": "Mistral"
        case "gemini": "Gemini"
        case "neutts": "NeuTTS"
        case "kittentts": "KittenTTS"
        case "piper": "Piper"
        default: normalized.isEmpty ? "Unknown" : normalized
        }
    }

    static func normalizedVoice(_ voice: String) -> String {
        voice.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canApply(
        draftVoice: String,
        currentVoice: String,
        controlsEnabled: Bool
    ) -> Bool {
        let normalized = normalizedVoice(draftVoice)
        return controlsEnabled
            && !normalized.isEmpty
            && normalized != currentVoice
    }
}
