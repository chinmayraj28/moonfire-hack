import SwiftUI

struct Message: Identifiable {
    let id = UUID()
    let fromMe: Bool
    var text: String            // what she literally sent, or what he literally typed
    var scripted: String?       // demo line used when no model is running
    var alt: String?            // her decoded meaning, or his played-it-cool version
    var showingAlt = false
    var altNote: String?
    var altIsBase = false
    var time: Date

    init(fromMe: Bool, _ text: String, at time: Date, scripted: String? = nil, alt: String? = nil, showingAlt: Bool = false) {
        self.fromMe = fromMe
        self.text = text
        self.time = time
        self.scripted = scripted
        self.alt = alt
        self.showingAlt = showingAlt
    }

    // What the other person sees: his cool version once it has been played cool.
    var sentText: String { fromMe && showingAlt ? (alt ?? text) : text }
}

struct Conversation: Identifiable {
    let id: String
    var name: String
    var initials: String
    var emoji: String? = nil
    var photo: String? = nil     // image name in the app bundle
    var avatar: [Color]
    var messages: [Message]
    var unread = false
    var openedAt = Date.distantPast   // keeps an empty, just-reset chat at the top of the list

    var lastTime: Date { messages.last?.time ?? openedAt }
    var preview: String { messages.last?.sentText ?? "" }
    var timeLabel: String { Fmt.listTime(lastTime) }
}

struct Scripted {
    let text: String
    let decode: String
}

// A text from someone else that lands while he's busy with Sophie.
struct Interruption {
    let convID: String
    let text: String
    let decode: String
}

// One running decode or cool transition: a 3D flip with the text swapped edge-on.
struct FX {
    var start: Date
    var swapAt: Date?
    var toAlt: Bool
    var tint: Color

    static let rampIn = 0.42   // turn away to edge-on, melting into the new colour
    static let rampOut = 0.85  // swing back round with an overshoot while the text decrypts
}

// The shockwave that rolls through the chat from a decode click.
struct Ripple {
    var origin: CGPoint
    var start: Date
}

struct FXState {
    var angle = 0.0    // degrees around the vertical axis
    var wobble = 0.0   // jelly morph and glow, strongest edge-on
    var morph = 0.0    // colour blend towards the new bubble, first half only
    var time = 0.0
    var reveal = 1.0
    var showAlt: Bool

    init(_ fx: FX?, now: Date, showingAlt: Bool) {
        guard let fx else { showAlt = showingAlt; return }
        time = now.timeIntervalSince(fx.start)
        if let swap = fx.swapAt, now >= swap {
            showAlt = fx.toAlt
            let t = min(1, now.timeIntervalSince(swap) / FX.rampOut)
            angle = -90 * (1 - Self.easeOutBack(t))
            wobble = (1 - t) * (1 - t)
            reveal = min(1, t * 1.5)
        } else {
            showAlt = showingAlt
            let t = min(1, time / FX.rampIn)
            angle = time < FX.rampIn ? 90 * t * t : 82 + 6 * sin((time - FX.rampIn) * 9)  // hover while the model thinks
            wobble = t
            morph = t
        }
    }

    static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

// Hacker-film decryption: unrevealed characters flicker through random glyphs.
enum Scramble {
    static let glyphs = Array("!<>_/[]{}=+*^?#%&@$ABCDEFGHJKLMNPQRSTUVWXYZ0123456789")

    static func text(_ target: String, revealed: Double, seed: Int) -> String {
        let chars = Array(target)
        let shown = Int(Double(chars.count) * revealed)
        return String(chars.enumerated().map { i, c in
            i < shown || c.isWhitespace ? c : glyphs[abs((i &* 7919) ^ (seed &* 104_729)) % glyphs.count]
        })
    }
}

enum Fmt {
    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let weekday: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE"; return f }()
    static let header: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM 'at' HH:mm"; return f }()

    static func listTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return clock.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return weekday.string(from: date)
    }

    static func headerTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today " + clock.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday " + clock.string(from: date) }
        return header.string(from: date)
    }
}

enum Seed {
    static let herID = "sophie"

    static func ago(minutes: Double) -> Date { Date.now.addingTimeInterval(-minutes * 60) }
    static func day(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    static let grey: [Color] = [Color(red: 0.66, green: 0.67, blue: 0.71), Color(red: 0.52, green: 0.54, blue: 0.57)]

    // Her next messages, in order. Cmd+Right Arrow sends the next one.
    static let herScript: [Scripted] = [
        Scripted(text: "Hey great day at the beach today. I was wondering if you'd like to meet my best friend tomorrow 🙂",
                 decode: "She likes you and trusts you enough to meet her best friend. The best friend is HR and this is your final interview. Don't fuck this up."),
        Scripted(text: "also fair warning she can be a bit protective so don't take it personally if she asks a lot of questions lol",
                 decode: "Her best friend has already deep-dived your entire Instagram, 2016 posts included. You're being vetted, bro. Deleting things now is too late."),
        Scripted(text: "btw what are you doing saturday? no pressure if you're busy!",
                 decode: "'No pressure' is a LOT of pressure. You're free Saturday. You were always free Saturday."),
        Scripted(text: "I made a playlist for the drive tomorrow, no big deal 🎶",
                 decode: "She spent three hours on this. Every song is a coded message. Track 4 is about you. Act normal."),
        Scripted(text: "haha it's fine honestly, do whatever you want",
                 decode: "It is not fine. Do NOT do whatever you want. Stop what you're doing and call her."),
        Scripted(text: "k",
                 decode: "Oh no. What did you do."),
    ]

    // Fired after every second text he sends Sophie, in this order.
    static let interruptions: [Interruption] = [
        Interruption(convID: "lads", text: "lads it's jake's birthday saturday. mandatory. no girlfriends. sorry not sorry 🍻",
                     decode: "Saturday is now a war between the lads and Sophie. Choose wisely. Choose Sophie."),
        Interruption(convID: "grandma", text: "IS SOPHIE COMING TO SUNDAY LUNCH. I HAVE MADE A TRIFLE. DO NOT TELL YOUR MOTHER",
                     decode: "Grandma has already planned the wedding. The trifle is a power move."),
        Interruption(convID: "ex", text: "u up? 👀",
                     decode: "Absolutely not. Put the phone face down. Sophie is RIGHT THERE."),
        Interruption(convID: "mum", text: "Your grandma says Sophie's coming for Sunday lunch?? Nobody tells me anything x",
                     decode: "Mum is hurt that Grandma knew first. Call her before this becomes a family feud."),
        Interruption(convID: "landlord", text: "Rent's due Friday mate. Also the boiler's now making a noise like a goose. Don't touch it.",
                     decode: "Do not invite Sophie round until the goose situation is resolved."),
        Interruption(convID: "bank", text: "Payment declined: £34.99 at a florist. Love is expensive, mate.",
                     decode: "The flowers didn't go through. Neither will your rent. Pick one."),
        Interruption(convID: "lads", text: "bro has she let you out yet or are we sending a search party 💀",
                     decode: "The lads feel abandoned. Send one voice note to keep them alive."),
        Interruption(convID: "gym", text: "Saw you walk past today. We waved. You didn't wave back 💔",
                     decode: "The gym is grieving. Ignore it, you've got a date to get ready for."),
        Interruption(convID: "grandma", text: "SOPHIE ADDED ME ON FACEBOOK. LOVELY GIRL. WHY DO YOU NEVER ADD ME",
                     decode: "Sophie is now closer to your grandma than you are. This is a green flag."),
        Interruption(convID: "app", text: "Someone new liked you! Just kidding. You're taken, delete us 💀",
                     decode: "Even the app knows. Delete it while Sophie's watching."),
    ]

    static func conversations() -> [Conversation] {
        [
            Conversation(id: herID, name: "Sophie", initials: "S", photo: "sophie",
                         avatar: [Color(red: 1.0, green: 0.55, blue: 0.7), Color(red: 0.72, green: 0.35, blue: 0.95)],
                         messages: [
                            Message(fromMe: false, "had such a nice time tonight!! you're actually really easy to talk to haha", at: day(1, 21, 14),
                                    scripted: "She's into you. 'Actually' means she expected you to be weird and you weren't. Keep it that way, king."),
                            Message(fromMe: true, "Same!!! Honestly best night I've had in years. I already told my mum about you and I've been smiling at my phone like an idiot 😭", at: day(1, 21, 16),
                                    alt: "same, had a really good time 😊", showingAlt: true),
                            Message(fromMe: false, "omg today was so fun. also you got SO sunburnt 😂 hope you put aloe on it", at: ago(minutes: 24),
                                    scripted: "She's flirting via light bullying. The aloe thing means she thinks about you when you're not around. Green flag."),
                            Message(fromMe: true, "Haha yes I put aloe on, thank you so much for caring!! Honestly today was perfect and the sunburn was 100% worth it. When can I see you again? Tomorrow? Tonight?", at: ago(minutes: 21),
                                    alt: "worth it tbh 🌊", showingAlt: true),
                         ]),
            Conversation(id: "mum", name: "Mum", initials: "M", photo: "mum", avatar: grey, messages: [
                Message(fromMe: false, "Did you eat today?", at: day(1, 8, 12)),
                Message(fromMe: false, "Also who is Sophie?? Your sister showed me her Instagram. She looks lovely. Bring her to Sunday lunch x", at: ago(minutes: 75)),
            ]),
            Conversation(id: "ex", name: "DO NOT TEXT", initials: "", emoji: "🚩", photo: "ex",
                         avatar: [Color(red: 1.0, green: 0.42, blue: 0.4), Color(red: 0.85, green: 0.2, blue: 0.25)], messages: [
                Message(fromMe: false, "hey stranger 👀 saw you at the beach today", at: ago(minutes: 140)),
            ]),
            Conversation(id: "lads", name: "The Lads", initials: "", emoji: "🍻", photo: "lads",
                         avatar: [Color(red: 0.98, green: 0.8, blue: 0.35), Color(red: 0.95, green: 0.6, blue: 0.2)], messages: [
                Message(fromMe: false, "who's in for five-a-side thursday", at: day(1, 18, 2)),
                Message(fromMe: false, "bro you've gone quiet since you met this girl 💀", at: ago(minutes: 220)),
            ]),
            Conversation(id: "landlord", name: "Gary (Landlord)", initials: "G", photo: "landlord", avatar: grey, messages: [
                Message(fromMe: false, "Hi mate, boiler's out again. Cold showers till Tuesday, character building 👍", at: day(1, 11, 40)),
            ]),
            Conversation(id: "bank", name: "Bank", initials: "B", photo: "bank", avatar: grey, messages: [
                Message(fromMe: false, "Your balance is £4.20. Have you considered a meal deal?", at: day(2, 9, 30)),
            ]),
            Conversation(id: "gym", name: "Gym", initials: "G", photo: "gym", avatar: grey, messages: [
                Message(fromMe: false, "We miss you! It's been 47 days 🥺 Come back, the treadmill asks about you.", at: day(2, 7, 0)),
            ]),
            Conversation(id: "app", name: "Dating App", initials: "D", photo: "app", avatar: grey, messages: [
                Message(fromMe: false, "You have 0 new likes. Good thing you met Sophie.", at: day(3, 20, 15)),
            ]),
            Conversation(id: "grandma", name: "Grandma", initials: "G", photo: "grandma", avatar: grey, messages: [
                Message(fromMe: false, "HOW DO I TURN OFF THE CAPITALS. ALSO WHO IS SOPHIE", at: day(4, 16, 5)),
            ]),
        ]
    }
}
