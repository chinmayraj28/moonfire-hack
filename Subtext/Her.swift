import Foundation

// Sophie's side of the chat, written live by Gemini. She plays the girlfriend for the demo;
// the product itself (decode and play it cool) stays on the local fine-tuned model.
//
// Key:   defaults write com.owenbarnes.subtext GeminiAPIKey 'YOUR_KEY'   (or GEMINI_API_KEY)
// Model: defaults write com.owenbarnes.subtext SubtextHerModel 'gemini-3.5-flash-lite'
@MainActor
final class Her {
    private var agendas = Agenda.all.shuffled()

    private var key: String? {
        let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "GeminiAPIKey")
        return key?.isEmpty == false ? key : nil
    }

    private var model: String {
        ProcessInfo.processInfo.environment["SUBTEXT_HER_MODEL"]
            ?? UserDefaults.standard.string(forKey: "SubtextHerModel")
            ?? "gemini-3.5-flash-lite"
    }

    // Her next text, plus the line Subtext falls back to if the local model is offline.
    func reply(to history: [Message]) async -> (text: String, decode: String)? {
        guard let key else { return nil }
        if agendas.isEmpty { agendas = Agenda.all.shuffled() }
        let agenda = agendas.removeFirst()

        let transcript = history.suffix(16)
            .map { "\($0.fromMe ? "Him" : "You"): \($0.sentText)" }
            .joined(separator: "\n")
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": HerPrompt.system(hiding: agenda.hide)]]],
            "contents": [["role": "user", "parts": [["text": "The chat so far:\n\(transcript)\n\nWrite your next text."]]]],
            "generationConfig": ["temperature": 1.0, "maxOutputTokens": 600],
        ]
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                 timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("Gemini:", String(data: data, encoding: .utf8) ?? "")
                return nil
            }
            struct Reply: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String?; let thought: Bool? }
                        let parts: [Part]?
                    }
                    let content: Content?
                }
                let candidates: [Candidate]?
            }
            let parts = try JSONDecoder().decode(Reply.self, from: data).candidates?.first?.content?.parts ?? []
            var text = parts.filter { $0.thought != true }.compactMap(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("You:") { text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            return text.isEmpty ? nil : (text, agenda.decode)
        } catch {
            print("Gemini:", error)
            return nil
        }
    }
}

enum HerPrompt {
    static func system(hiding agenda: String) -> String {
        """
        You are Sophie, 26, from south London. You're texting a guy you've been seeing for a couple of weeks. Last night was a great date; today you went to the beach together and he got badly sunburnt. You like him a lot. You would never say that plainly.

        Write your next text message to him.

        How you text:
        - You over-explain. Every reply is one long message of 70 to 130 words that narrates far more than anyone asked: what you're doing right now, what just happened at work, what your flatmate Priya said, what your cat Biscuit knocked over, what your mum thinks, the show you're halfway through.
        - You go off on tangents, correct yourself mid-sentence ("well not annoyed, more like mildly betrayed"), add little disclaimers ("not that it matters", "random but", "no pressure obviously") and circle back.
        - Mostly lowercase, casual punctuation, "haha", "lol", "omg", "honestly", the odd typo. British spelling. Up to three emojis. No line breaks, no hashtags.
        - React to what he actually sent. If his text was short or a bit too cool, notice it, but only sideways.

        The hidden message:
        - Every text buries one thing you really mean deep in the middle, inside the noise, never stated directly. This time, bury this: \(agenda)
        - Hide it in a throwaway clause, a "no pressure", an "anyway it's fine", or a question tucked into a tangent. Someone skimming should miss it; someone reading closely should get it.

        Never be mean, sexual or explicit. Never mention AI, subtext, hidden messages or decoding. Reply with the text message only.
        """
    }
}

// What she buries in each reply, and the blunt read Subtext gives if the local model is offline.
struct Agenda {
    let hide: String
    let decode: String

    static let all = [
        Agenda(hide: "you want him to ask you out properly for Saturday night. Only mention that you're 'free-ish' on Saturday, in the middle of a tangent.",
               decode: "She's free Saturday and wants you to ask her out properly. She buried it mid-essay to see if you actually read it. Ask her."),
        Agenda(hide: "you're a bit hurt his last reply was so short. Say in passing that you 'love a short and sweet text', in a way that clearly means the opposite.",
               decode: "'Love a short and sweet text' means your reply was dry and she noticed. Put some effort in, bro."),
        Agenda(hide: "you want to meet his friends. Mention that your friend's boyfriend's mates all hang out together and it's 'so cute', then move on fast.",
               decode: "She wants to meet the lads. Yes, those lads. Hide the traffic cone photos."),
        Agenda(hide: "you want to know he's deleted the dating apps. Mention your friend saw 'someone who looked exactly like him' on one, then laugh it off.",
               decode: "She's checking you've deleted the apps. Delete the apps. Then casually mention you deleted the apps."),
        Agenda(hide: "your big work presentation is on Thursday and you told him about it on your first date. Say Thursday is 'a big day lol' without saying why.",
               decode: "Thursday is her big work presentation. She told you on date one. Text her good luck Thursday morning or it's over."),
        Agenda(hide: "you want him to come to your friend's birthday drinks on Friday. Mention the drinks, and that 'people are bringing plus ones apparently, idk'.",
               decode: "That's an invite. You're her plus one on Friday. 'idk' means she very much knows. Say you're coming."),
        Agenda(hide: "you'd rather he called than texted. Mention your thumbs are tired and you 'much prefer actually talking to people tbh'.",
               decode: "She wants you to call her. Tonight. Stop typing and press the green button, king."),
        Agenda(hide: "you want to know if he's told his family about you. Ask very casually whether his family are 'nosy' like yours.",
               decode: "She's asking if you've told your mum about her. You have. Tell her, it's adorable."),
    ]
}
