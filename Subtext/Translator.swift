import Foundation
import Observation

// The fine-tuned model was trained with these two prompts, word for word (data/PROMPT.md and
// Models/subtext/run_local.py). Whatever model sits in Models/subtext, send it the prompts it learned.
enum Prompts {
    static let decode = "You are Subtext. She sent him this text. Tell him what she really means in one or two short, funny lines of blunt Gen Z advice."
    static let cool = "You are Play It Cool. Rewrite his over-eager text as a short, relaxed reply. Keep every fact, time, place and answer. Max 12 words."
}

enum Mode {
    case decode, cool

    var system: String { self == .decode ? Prompts.decode : Prompts.cool }
    var temperature: Double { self == .decode ? 0.8 : 0.3 }
}

struct Translation {
    var text: String
    var note: String?
}

// Talks to any OpenAI-compatible local server: llama-server or mlx_lm.server.
// Fine-tuned model on SUBTEXT_URL, base model on SUBTEXT_BASE_URL (option-click compares).
@MainActor @Observable
final class Translator {
    var preferScript = false
    private let tuned: URL
    private let base: URL
    private let model: String?
    private let label: String

    init() {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        tuned = URL(string: env["SUBTEXT_URL"] ?? defaults.string(forKey: "SubtextURL")
                    ?? "http://127.0.0.1:8080/v1/chat/completions")!
        base = URL(string: env["SUBTEXT_BASE_URL"] ?? defaults.string(forKey: "SubtextBaseURL")
                   ?? "http://127.0.0.1:8081/v1/chat/completions")!
        model = env["SUBTEXT_MODEL"] ?? defaults.string(forKey: "SubtextModel")
        label = env["SUBTEXT_LABEL"] ?? defaults.string(forKey: "SubtextLabel") ?? "fine-tuned LFM2.5"
    }

    func run(_ mode: Mode, text: String, scripted: String?, useBase: Bool) async -> Translation {
        if preferScript, !useBase, let scripted { return Translation(text: scripted) }
        let start = Date()
        do {
            let out = try await complete(url: useBase ? base : tuned, mode: mode, user: text)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return Translation(text: out, note: "\(useBase ? "base LFM2.5" : label) on this Mac, \(ms) ms")
        } catch {
            if useBase { return Translation(text: "(the base model isn't running)", note: "start it on SUBTEXT_BASE_URL") }
            return Translation(text: scripted ?? Fallback.line(mode, text))
        }
    }

    private func complete(url: URL, mode: Mode, user: String) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "messages": [["role": "system", "content": mode.system], ["role": "user", "content": user]],
            "temperature": mode.temperature,
            "max_tokens": 90,
            "stream": false,
        ]
        if let model { body["model"] = model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        let text = try JSONDecoder().decode(Reply.self, from: data).choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw URLError(.cannotParseResponse) }
        return text
    }
}

// Used only when no model is running and the message has no scripted line.
enum Fallback {
    static func line(_ mode: Mode, _ text: String) -> String {
        switch mode {
        case .decode:
            return decodes.randomElement()!
        case .cool:
            if let time = firstTime(in: text) { return "sounds good, see you at \(time)?" }
            return cools.randomElement()!
        }
    }

    static let decodes = [
        "She's into you. Act normal. Normal normal, not weird normal.",
        "This is a test and you are currently passing. Barely.",
        "She means exactly what she said. Rare, but it happens. Reply like a functioning adult.",
    ]
    static let cools = ["sounds good 👍", "haha go on then", "down", "nice, let's do it"]

    static func firstTime(in text: String) -> String? {
        let pattern = #"\b\d{1,2}(:\d{2})?\s?(am|pm)\b|\b\d{1,2}:\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}
