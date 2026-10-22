import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ChatStore {
    var conversations = Seed.conversations()
    var selectedID: String? = Seed.herID
    var draft = ""
    var search = ""
    var herTyping = false
    var fx: [UUID: FX] = [:]
    let translator = Translator()
    private var script = Seed.herScript

    // Her chat stays pinned at the top; everyone else by most recent.
    var visibleConversations: [Conversation] {
        let sorted = conversations.sorted { a, b in
            if a.id == Seed.herID { return true }
            if b.id == Seed.herID { return false }
            return a.lastTime > b.lastTime
        }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.preview.localizedCaseInsensitiveContains(search) }
    }

    func conversation(_ id: String) -> Conversation? { conversations.first { $0.id == id } }

    func markRead() {
        guard let id = selectedID, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].unread = false
    }

    // MARK: Her side

    func herNext() {
        guard !herTyping, !script.isEmpty else { return }
        let next = script.removeFirst()
        deliverFromHer(next.text, scripted: next.decode)
    }

    func sendDraftAsHer() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !herTyping else { return }
        draft = ""
        deliverFromHer(text, scripted: nil)
    }

    private func deliverFromHer(_ text: String, scripted: String?) {
        herTyping = true
        let delay = min(2.6, 1.0 + Double(text.count) * 0.012)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            herTyping = false
            append(Message(fromMe: false, text, at: .now, scripted: scripted), to: Seed.herID)
            NSSound(named: "Pop")?.play()
        }
    }

    // MARK: His side

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let convID = selectedID else { return }
        draft = ""
        let message = Message(fromMe: true, text, at: .now)
        append(message, to: convID)
        guard convID == Seed.herID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            tap(message.id, in: convID)
        }
    }

    // MARK: Decode and cool

    // Tap toggles between the literal text and its translation. Option-tap asks the base model instead.
    func tap(_ id: UUID, in convID: String, useBase: Bool = false) {
        guard fx[id] == nil, let message = find(id, in: convID) else { return }
        let toAlt = useBase || !message.showingAlt
        let needsModel = toAlt && (message.alt == nil || useBase || message.altIsBase)
        fx[id] = FX(start: .now, toAlt: toAlt, tint: message.fromMe ? Theme.coolTint : Theme.decodeTint)

        Task { @MainActor in
            if needsModel {
                let result = await translator.run(message.fromMe ? .cool : .decode, text: message.text,
                                                  scripted: message.scripted, useBase: useBase)
                update(id, in: convID) {
                    $0.alt = result.text
                    $0.altNote = result.note
                    $0.altIsBase = useBase
                }
            }
            swap(id, in: convID)
        }
    }

    private func swap(_ id: UUID, in convID: String) {
        guard var effect = fx[id] else { return }
        let swapAt = max(Date.now, effect.start.addingTimeInterval(FX.rampIn))
        effect.swapAt = swapAt
        fx[id] = effect
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(swapAt.timeIntervalSinceNow + FX.rampOut))
            update(id, in: convID) { $0.showingAlt = effect.toAlt }
            fx[id] = nil
        }
    }

    // MARK: Rehearsal

    // Launch with -autoplay to run the opening beat hands-free: she texts, then it decodes.
    func autoplayIfAsked() async {
        guard CommandLine.arguments.contains("-autoplay") else { return }
        try? await Task.sleep(for: .seconds(1))
        herNext()
        try? await Task.sleep(for: .seconds(4))
        if let last = conversation(Seed.herID)?.messages.last { tap(last.id, in: Seed.herID) }
    }

    // MARK: Housekeeping

    func reset() {
        conversations = Seed.conversations()
        script = Seed.herScript
        fx = [:]
        herTyping = false
        draft = ""
        selectedID = Seed.herID
    }

    private func append(_ message: Message, to convID: String) {
        guard let i = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[i].messages.append(message)
        if selectedID != convID { conversations[i].unread = true }
    }

    private func find(_ id: UUID, in convID: String) -> Message? {
        conversation(convID)?.messages.first { $0.id == id }
    }

    private func update(_ id: UUID, in convID: String, _ change: (inout Message) -> Void) {
        guard let c = conversations.firstIndex(where: { $0.id == convID }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[c].messages[m])
    }
}
