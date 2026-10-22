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
    var autoReply = true
    var fx: [UUID: FX] = [:]
    var ripple: Ripple?
    let translator = Translator()
    private let her = Her()
    private var script = Seed.herScript
    private var interruptions = Seed.interruptions
    private var sentToHer = 0
    private var epoch = 0   // bumped on reset, so replies still on their way are dropped

    // Most recent first, like Messages: whoever texted last goes to the top.
    var visibleConversations: [Conversation] {
        let sorted = conversations.sorted { $0.lastTime > $1.lastTime }
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
        herTyping = true
        let run = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(min(2.6, 1.0 + Double(next.text.count) * 0.012)))
            land(next.text, scripted: next.decode, run: run)
        }
    }

    func sendDraftAsHer() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !herTyping else { return }
        draft = ""
        herTyping = true
        let run = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            land(text, scripted: nil, run: run)
        }
    }

    // She answers his last text straight away: Claude writes it live, or the next scripted line if it can't.
    // A reset always gets a fresh opener (force), even with automatic replies switched off.
    private func herRespond(force: Bool = false) {
        guard autoReply || force, !herTyping else { return }
        herTyping = true
        let run = epoch
        Task { @MainActor in
            let start = Date.now
            if let reply = await her.reply(to: conversation(Seed.herID)?.messages ?? []) {
                try? await Task.sleep(for: .seconds(max(0, 0.8 - Date.now.timeIntervalSince(start))))
                land(reply.text, scripted: reply.decode, run: run)
            } else if run == epoch, !script.isEmpty {
                let next = script.removeFirst()
                try? await Task.sleep(for: .seconds(1.2))
                land(next.text, scripted: next.decode, run: run)
            } else if run == epoch {
                herTyping = false
            }
        }
    }

    private func land(_ text: String, scripted: String?, run: Int) {
        guard run == epoch else { return }
        herTyping = false
        withAnimation(.snappy) { append(Message(fromMe: false, text, at: .now, scripted: scripted), to: Seed.herID) }
        (selectedID == Seed.herID ? Sounds.received : Sounds.notification).play()
    }

    // MARK: Everyone else

    // Every second text he sends her, someone else chimes in. Their chat jumps up; Sophie stays open.
    private func interrupt() {
        guard !interruptions.isEmpty else { return }
        let next = interruptions.removeFirst()
        let run = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard run == epoch else { return }
            withAnimation(.snappy) {
                append(Message(fromMe: false, next.text, at: .now, scripted: next.decode), to: next.convID)
            }
            (selectedID == next.convID ? Sounds.received : Sounds.notification).play()
        }
    }

    // MARK: His side

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let convID = selectedID else { return }
        draft = ""
        let message = Message(fromMe: true, text, at: .now)
        withAnimation(.snappy) { append(message, to: convID) }
        Sounds.sent.play()
        guard convID == Seed.herID else { return }

        sentToHer += 1
        if sentToHer % 2 == 0 { interrupt() }
        let run = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard run == epoch else { return }
            tap(message.id, in: convID)
            while fx[message.id] != nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard run == epoch else { return }
            herRespond()
        }
    }

    // MARK: Decode and cool

    // Tap toggles between the literal text and its translation. Option-tap asks the base model instead.
    func tap(_ id: UUID, in convID: String, useBase: Bool = false, at location: CGPoint? = nil) {
        guard fx[id] == nil, let message = find(id, in: convID) else { return }
        let toAlt = useBase || !message.showingAlt
        if !message.fromMe, toAlt, let location { celebrate(at: location) }
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

    // The decode moment: shockwave through the chat, iMessage's Spotlight sound, a trackpad tap.
    private func celebrate(at location: CGPoint) {
        let start = Date.now
        ripple = Ripple(origin: location, start: start)
        Sounds.reveal.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if ripple?.start == start { ripple = nil }
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

    // Launch with -autoplay to run the opening beat hands-free: she texts; add -reply and he answers twice.
    func autoplayIfAsked() async {
        if CommandLine.arguments.contains("-reset") { reset() }   // start fresh, exactly as the reset button does
        guard CommandLine.arguments.contains("-autoplay") else { return }
        try? await Task.sleep(for: .seconds(1))
        herNext()
        try? await Task.sleep(for: .seconds(4))
        // Decoding stays a click, even in rehearsal, unless -autodecode is passed for testing.
        if CommandLine.arguments.contains("-autodecode"), let last = conversation(Seed.herID)?.messages.last {
            tap(last.id, in: Seed.herID, at: CGPoint(x: 300, y: 500))
        }
        guard CommandLine.arguments.contains("-reply") else { return }
        for text in ["omg yes!!! I would LOVE to meet her, is 2pm ok?? I'll bring snacks for everyone honestly I'm so excited",
                     "Haha that sounds amazing, I'm so lucky, honestly you're the best thing that's happened to me all year"] {
            try? await Task.sleep(for: .seconds(3))
            draft = text
            sendDraft()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    // MARK: Housekeeping

    func reset() {
        epoch += 1
        ripple = nil
        conversations = Seed.conversations()
        // Sophie starts from nothing: her only message will be the fresh one Claude writes.
        if let i = conversations.firstIndex(where: { $0.id == Seed.herID }) {
            conversations[i].messages = []
            conversations[i].openedAt = .now
        }
        script = Seed.herScript
        interruptions = Seed.interruptions
        sentToHer = 0
        fx = [:]
        herTyping = false
        draft = ""
        selectedID = Seed.herID
        // A beat after the reset, Sophie starts a brand new conversation, written live.
        let run = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard run == epoch else { return }
            herRespond(force: true)
        }
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
