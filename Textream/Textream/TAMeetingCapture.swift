import Foundation
import Speech
import ScreenCaptureKit

/// System playback only: the TA's microphone is never connected to this stream.
@MainActor
final class TAMeetingCapture: NSObject, SCStreamOutput, SCStreamDelegate, TACapturing {
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var stream: SCStream?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var rotationTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var segmentID = UUID()
    private var committed = ""
    private var partial = ""
    private var failures = 0

    func start(locale: String) async throws {
        stop()
        let session = sessionID
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard session == sessionID else { throw CancellationError() }
        guard authorization == .authorized else {
            throw TAError.message("Allow Speech Recognition for Textream in System Settings → Privacy & Security, or type your question below.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw TAError.message("Speech recognition is unavailable for this language. Change the language or type a question.")
        }
        self.recognizer = recognizer
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard session == sessionID else { throw CancellationError() }
        guard let display = content.displays.first else {
            throw TAError.message("No display is available for meeting audio capture.")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .audio,
                                      sampleHandlerQueue: DispatchQueue(label: "textream.ta.audio"))
        stream = newStream
        committed = ""
        partial = ""
        failures = 0
        beginSegment()
        do {
            try await newStream.startCapture()
            guard session == sessionID else {
                try? await newStream.stopCapture()
                throw CancellationError()
            }
        } catch {
            if session == sessionID { stop() }
            throw error
        }
    }

    func stop() {
        sessionID = UUID()
        segmentID = UUID()
        rotationTask?.cancel()
        rotationTask = nil
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        if let oldStream = stream {
            stream = nil
            Task { try? await oldStream.stopCapture() }
        }
    }

    /// Start the next question without feeding the previous transcription back to GPT.
    func resetQuestion() {
        committed = ""
        partial = ""
        if stream != nil { beginSegment() }
    }

    private func beginSegment() {
        guard stream != nil, let recognizer else { return }
        segmentID = UUID()
        let segment = segmentID
        rotationTask?.cancel()
        request?.endAudio()
        recognitionTask?.cancel()
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.taskHint = .dictation
        newRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = newRequest
        partial = ""
        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.segmentID == segment, self.stream != nil else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if !self.partial.isEmpty { self.failures = 0 }
                    self.onText?([self.committed, self.partial].filter { !$0.isEmpty }.joined(separator: " "))
                }
                if result?.isFinal == true || error != nil {
                    // A finite budget prevents a permission/service error from creating a restart loop.
                    if error != nil { self.failures += 1 }
                    if self.failures >= 3 {
                        self.stop()
                        self.onError?("Speech recognition stopped. Check permissions and connection, then choose Resume audio.")
                    } else {
                        self.commitSegment()
                    }
                }
            }
        }
        rotationTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 50_000_000_000) } catch { return }
            guard let self, self.segmentID == segment else { return }
            self.commitSegment()
        }
    }

    private func commitSegment() {
        committed = String([committed, partial].filter { !$0.isEmpty }.joined(separator: " ").suffix(8000))
        beginSegment()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        // Retaining the sample buffer through this closure keeps its storage alive.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.request?.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stop()
            self.onError?("Meeting audio stopped. Allow Screen & System Audio Recording for Textream, then choose Resume audio.")
        }
    }
}
