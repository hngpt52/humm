import AVFoundation

/// Records the microphone to a small mono AAC file. Both transcription models accept m4a,
/// and it is roughly a tenth the size of WAV, which keeps upload time down.
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("humm-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw HummError.recordingFailed }
        self.recorder = recorder
        startedAt = Date()
    }

    /// Returns the file and its duration; the caller deletes the file.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder, let startedAt else { return nil }
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil
        return (recorder.url, Date().timeIntervalSince(startedAt))
    }

    /// Input loudness from 0 (silence) to 1 (loud speech), for the level meter.
    func level() -> Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)  // -160...0 dBFS
        return max(0, min(1, (decibels + 50) / 45))
    }

    func cancel() {
        guard let url = stop()?.url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Loudness of the loudest 50 ms of a recording, in dBFS, or nil if it can't be read.
    static func peakLoudness(of url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate / 20))
        else { return nil }
        var loudest: Float = 0
        while (try? file.read(into: buffer)) != nil, buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            loudest = max(loudest, (sum / Float(buffer.frameLength)).squareRoot())
        }
        return loudest > 0 ? 20 * log10(loudest) : -160
    }
}
