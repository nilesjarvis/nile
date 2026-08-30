@preconcurrency import AVFoundation

enum SpeechAudioSession {
    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP]
        )
        try session.setPreferredSampleRate(
            Double(speechSampleRateHz)
        )
        try session.setPreferredIOBufferDuration(0.1)
        try session.setActive(true)
    }

    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}
