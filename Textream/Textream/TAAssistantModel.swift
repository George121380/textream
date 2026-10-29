import Foundation
import Combine

@MainActor
protocol TACapturing: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start(locale: String) async throws
    func stop()
    func resetQuestion()
}

@MainActor
protocol TAResponding {
    func stream(key: String, model: String, question: String, context: String,
                language: String, history: [TATurn], onDelta: @escaping (String) -> Void) async throws
}

@MainActor
final class TAAssistantModel: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var listening = false
    @Published private(set) var starting = false
    @Published private(set) var generating = false
    @Published private(set) var hasKey = false
    @Published var question = ""
    @Published private(set) var answeredQuestion = ""
    @Published private(set) var answer = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var courseContext = ""
    @Published var autoShowReplies = UserDefaults.standard.object(forKey: "ta.autoShowReplies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoShowReplies, forKey: "ta.autoShowReplies") }
    }
    /// Called only for a completed, current response, never failed or cancelled text.
    var onReplyReady: ((String) -> Void)?
    @Published var model = UserDefaults.standard.string(forKey: "ta.model") ?? "gpt-6.1-terra" {
        didSet { UserDefaults.standard.set(model, forKey: "ta.model") }
    }
    @Published var locale = UserDefaults.standard.string(forKey: "ta.locale") ?? "en-US" {
        didSet { UserDefaults.standard.set(locale, forKey: "ta.locale") }
    }
    @Published var language = UserDefaults.standard.string(forKey: "ta.language") ?? "English" {
        didSet { UserDefaults.standard.set(language, forKey: "ta.language") }
    }
    @Published var automatic = true {
        didSet {
            debounceTask?.cancel()
            if automatic { scheduleReply() }
        }
    }
    @Published var pauseSeconds: Double = 1.8 {
        didSet { scheduleReply() }
    }

    private let capture: TACapturing
    private let client: TAResponding
    private let loadKey: () throws -> String
    private let writeKey: (String) throws -> Void
    private var captureTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var captureID = UUID()
    private var responseID = UUID()
    private var questionFromAudio = false
    private var history: [TATurn] = []

    convenience init() {
        self.init(capture: TAMeetingCapture(), client: TAResponseClient(),
                  loadKey: TAKeychain.read, writeKey: TAKeychain.save)
    }

    init(capture: TACapturing, client: TAResponding,
         loadKey: @escaping () throws -> String, writeKey: @escaping (String) throws -> Void) {
        self.capture = capture
        self.client = client
        self.loadKey = loadKey
        self.writeKey = writeKey
        do { hasKey = try !loadKey().isEmpty }
        catch { self.error = error.localizedDescription }
        capture.onText = { [weak self] text in
            guard let self, self.enabled, self.listening || self.starting, text != self.question else { return }
            self.question = String(text.suffix(8000))
            self.questionFromAudio = true
            self.scheduleReply()
        }
        capture.onError = { [weak self] message in
            guard let self else { return }
            self.pauseAudio()
            self.error = message
        }
    }

    func saveKey(_ key: String) {
        do {
            try writeKey(key)
            hasKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            notice = hasKey ? "API key saved in this Mac’s Keychain." : "API key removed."
            error = nil
            if !hasKey { setEnabled(false) }
        } catch { self.error = error.localizedDescription }
    }

    func setEnabled(_ value: Bool) {
        if value && !hasKey {
            error = "Save your OpenAI API key in Setup first."
            return
        }
        enabled = value
        if value {
            error = nil
            resumeAudio()
        } else {
            pauseAudio()
            cancelResponse()
        }
    }

    func resumeAudio() {
        guard enabled, !starting, !listening else { return }
        questionFromAudio = false
        captureID = UUID()
        let id = captureID
        starting = true
        error = nil
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capture.start(locale: self.locale)
                guard self.captureID == id, self.enabled else { return }
                self.starting = false
                self.listening = true
                self.scheduleReply()
            } catch {
                guard self.captureID == id else { return }
                self.starting = false
                self.listening = false
                self.error = "Meeting audio unavailable. Allow Textream in System Settings → Privacy & Security → Screen & System Audio Recording and Speech Recognition. You can also type a question."
            }
        }
    }

    func pauseAudio() {
        captureID = UUID()
        captureTask?.cancel()
        captureTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        capture.stop()
        listening = false
        starting = false
    }

    func editQuestion(_ text: String) {
        // Editing takes ownership of the question until audio is resumed explicitly.
        if listening || starting { pauseAudio() }
        questionFromAudio = false
        question = String(text.prefix(8000))
        debounceTask?.cancel()
    }

    private func scheduleReply() {
        debounceTask?.cancel()
        guard enabled, automatic, listening, questionFromAudio, !generating,
              question.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
        let expected = question
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: UInt64(max(1, self.pauseSeconds) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, self.enabled, self.automatic, self.listening,
                  self.question == expected, !self.generating else { return }
            self.generate()
        }
    }

    func generate() {
        guard enabled else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let key: String
        do {
            key = try loadKey()
            guard !key.isEmpty else { throw TAError.message("Add an API key in Setup first.") }
        } catch {
            self.error = error.localizedDescription
            return
        }
        cancelResponse()
        debounceTask?.cancel()
        let id = UUID()
        responseID = id
        answeredQuestion = text
        answer = ""
        error = nil
        question = ""
        questionFromAudio = false
        capture.resetQuestion()
        generating = true
        let selectedModel = model
        let notes = courseContext
        let outputLanguage = language
        let recentTurns = history
        let startedAt = Date()
        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.stream(key: key, model: selectedModel, question: text,
                                             context: notes, language: outputLanguage, history: recentTurns) { [weak self] delta in
                    guard let self, self.responseID == id, self.enabled else { return }
                    self.answer += delta
                }
                guard self.responseID == id, self.enabled else { return }
                self.history.append(TATurn(question: text, answer: self.answer))
                self.history = Array(self.history.suffix(3))
                self.generating = false
                self.responseTask = nil
                self.notice = String(format: "Reply ready in %.1f s.", Date().timeIntervalSince(startedAt))
                if self.autoShowReplies && !self.answer.isEmpty { self.onReplyReady?(self.answer) }
                self.scheduleReply()
            } catch {
                guard self.responseID == id, self.enabled else { return }
                self.generating = false
                self.responseTask = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
                // Never retry paid calls automatically. Preserve the question for manual retry.
                if self.question.isEmpty { self.question = text; self.questionFromAudio = false }
            }
        }
    }

    func cancelResponse() {
        responseID = UUID()
        responseTask?.cancel()
        responseTask = nil
        generating = false
    }

    func newStudent() {
        debounceTask?.cancel()
        cancelResponse()
        capture.resetQuestion()
        history.removeAll()
        question = ""
        answeredQuestion = ""
        answer = ""
        questionFromAudio = false
        error = nil
        notice = "Conversation cleared. Course notes are kept for this session."
    }
}
