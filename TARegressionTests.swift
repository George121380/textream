import Foundation

@MainActor
final class FakeCapture: TACapturing {
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var starts = 0
    var stops = 0
    var resets = 0
    func start(locale: String) async throws { starts += 1 }
    func stop() { stops += 1 }
    func resetQuestion() { resets += 1 }
}

@MainActor
final class FakeResponses: TAResponding {
    struct Call {
        let question: String
        let history: [TATurn]
        let delta: (String) -> Void
        let finish: CheckedContinuation<Void, Error>
    }
    var calls: [Call] = []
    func stream(key: String, model: String, question: String, context: String,
                language: String, history: [TATurn], onDelta: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(question: question, history: history, delta: onDelta, finish: continuation))
        }
    }
}

@main
struct TARegressionTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        func settle() async { try? await Task.sleep(nanoseconds: 30_000_000) }

        var decoder = TASSEDecoder()
        check(decoder.append(": keepalive") == nil, "SSE comment")
        check(decoder.append("event: response.output_text.delta") == nil, "SSE event field")
        check(decoder.append("data: {\"type\":\"response.output_text.delta\",") == nil, "SSE multiline first")
        check(decoder.append("data: \"delta\":\"你好 🌟\"}") == nil, "SSE multiline second")
        let payload = decoder.append("")!
        let event = try TAResponseEvent.decode(payload)
        check(event == .delta("你好 🌟"), "Unicode streaming")
        check(decoder.append("") == nil, "Empty SSE frame")
        let completed = try TAResponseEvent.decode(Data("{\"type\":\"response.completed\"}".utf8))
        check(completed == .completed, "Completion recognition")
        for kind in ["response.failed", "response.incomplete", "error"] {
            let event = try TAResponseEvent.decode(Data("{\"type\":\"\(kind)\"}".utf8))
            if case .failed = event { checks += 1 } else { fatalError("Failure event ignored") }
        }
        do { _ = try TAResponseEvent.decode(Data("bad json".utf8)); fatalError("Malformed event accepted") }
        catch { checks += 1 }

        // Exercise one byte at a time, including split Unicode and every SSE line ending.
        var lineDecoder = TALineDecoder()
        var lines: [String] = []
        for byte in "\u{FEFF}data: 你好 🌟\r\n\r\ndata: second\n\ndata: third\r\r".utf8 {
            if let line = try lineDecoder.append(byte) { lines.append(line) }
        }
        check(lines == ["data: 你好 🌟", "", "data: second", "", "data: third", ""], "Preserve SSE delimiters, Unicode and CRLF")

        let turns = (0..<6).map { TATurn(question: "q\($0)", answer: "a\($0)") }
        let request = try TAResponseClient.request(key: "test-placeholder", model: "test-model",
            question: String(repeating: "q", count: 9000), context: String(repeating: "c", count: 17000),
            language: "English", history: turns)
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        check(request.url?.absoluteString == "https://api.openai.com/v1/responses", "Credential destination")
        check(request.httpMethod == "POST", "HTTP method")
        check(json["store"] as? Bool == false, "Do not store responses")
        check(json["stream"] as? Bool == true, "Streaming enabled")
        let input = json["input"] as! [[String: String]]
        check(input.count == 8, "Context + bounded history + question")
        check(input[1]["content"] == "q3", "Only last three turns")
        check(input.last?["content"]?.count == 8000, "Question bound")
        check(input[0]["content"]!.hasSuffix(String(repeating: "c", count: 16000)), "Notes bound")
        check(!String(data: request.httpBody!, encoding: .utf8)!.contains("test-placeholder"), "Key excluded from prompt")

        let capture = FakeCapture()
        let client = FakeResponses()
        let model = TAAssistantModel(capture: capture, client: client,
            loadKey: { "test-placeholder" }, writeKey: { _ in })
        check(!model.enabled && capture.starts == 0 && client.calls.isEmpty, "Off by default")
        model.question = "Should never send"
        model.generate()
        check(client.calls.isEmpty, "Disabled generation")
        model.setEnabled(true)
        await settle()
        check(model.listening, "Capture starts only when enabled")
        model.editQuestion("First question")
        check(!model.listening, "Editing pauses capture")
        model.generate()
        await settle()
        check(client.calls.count == 1, "Manual request")
        client.calls[0].delta("First answer")
        check(model.answer == "First answer", "Stream reaches UI")
        model.newStudent()
        client.calls[0].delta("late stale text")
        client.calls[0].finish.resume()
        await settle()
        check(model.answer.isEmpty && model.question.isEmpty, "New student cancels stale output")
        for index in 1...5 {
            model.editQuestion("Question \(index)")
            model.generate()
            await settle()
            client.calls[index].delta("Answer \(index)")
            client.calls[index].finish.resume()
            await settle()
        }
        check(client.calls[1].history.isEmpty, "New student clears history")
        check(client.calls[5].history.count == 3, "History bounded to three turns")
        model.editQuestion("Cancelled question")
        model.generate()
        await settle()
        model.setEnabled(false)
        client.calls[6].delta("must not display")
        client.calls[6].finish.resume()
        await settle()
        check(model.answer.isEmpty && !model.generating && !model.listening, "Disable invalidates active response")

        model.pauseSeconds = 1
        model.setEnabled(true)
        await settle()
        capture.onText?("What is a policy")
        try await Task.sleep(nanoseconds: 650_000_000)
        capture.onText?("What is a policy gradient?")
        try await Task.sleep(nanoseconds: 500_000_000)
        check(client.calls.count == 7, "Wait for a full pause after revisions")
        try await Task.sleep(nanoseconds: 650_000_000)
        check(client.calls.count == 8 && client.calls[7].question == "What is a policy gradient?", "Automatic pause trigger")
        client.calls[7].delta("A policy gradient is…")
        client.calls[7].finish.resume()
        await settle()
        capture.onText?("Another question")
        model.setEnabled(false)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        check(client.calls.count == 8, "Disable cancels pending debounce")
        model.setEnabled(true)
        await settle()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        check(client.calls.count == 8, "Resume does not send stale transcript")
        model.setEnabled(false)

        let missingKey = TAAssistantModel(capture: FakeCapture(), client: FakeResponses(), loadKey: { "" }, writeKey: { _ in })
        missingKey.setEnabled(true)
        check(!missingKey.enabled && missingKey.error != nil, "Key required before capture")
        print("PASS: \(checks) TA regression checks (mock services; no network, audio or Keychain access).")
    }
}
