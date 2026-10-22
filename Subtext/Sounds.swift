import AppKit

// The real iMessage sounds, copied into the bundle at build time (see project.yml).
// Falls back to a system sound on a Mac without them.
enum Sounds {
    case received      // the soft blip when a message lands in the open chat
    case sent          // the whoosh when you send
    case notification  // tri-tone, for a message in another chat

    func play() {
        guard let sound = Self.cache[self] ?? nil else { return }
        sound.stop()
        sound.play()
    }

    private var file: String {
        switch self {
        case .received: "ReceivedMessage"
        case .sent: "SentMessage"
        case .notification: "sms-received1"
        }
    }

    private var fallback: String {
        switch self {
        case .received, .notification: "Pop"
        case .sent: "Tink"
        }
    }

    private static let cache: [Sounds: NSSound?] = Dictionary(uniqueKeysWithValues:
        [Sounds.received, .sent, .notification].map { kind in
            let url = Bundle.main.url(forResource: kind.file, withExtension: "caf")
            return (kind, url.flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: kind.fallback))
        })
}
