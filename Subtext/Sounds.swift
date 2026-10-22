import AppKit

// The real iMessage sounds, copied into the bundle at build time (see project.yml).
// Falls back to a system sound on a Mac without them.
enum Sounds {
    case received      // the soft blip when a message lands in the open chat
    case sent          // the whoosh when you send
    case notification  // tri-tone, for a message in another chat
    case reveal        // iMessage's Spotlight screen effect, for the decode

    func play() {
        guard let sound = Self.cache[self] ?? nil else { return }
        sound.stop()
        sound.volume = 1
        sound.play()
        guard self == .reveal else { return }
        // The effect sound runs for six seconds; keep the first two and fade out.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            for step in stride(from: 1.0, through: 0, by: -0.1) {
                sound.volume = Float(step)
                try? await Task.sleep(for: .milliseconds(40))
            }
            sound.stop()
        }
    }

    private var file: String {
        switch self {
        case .received: "ReceivedMessage"
        case .sent: "SentMessage"
        case .notification: "sms-received1"
        case .reveal: "Spotlight"
        }
    }

    private var fallback: String {
        switch self {
        case .received, .notification: "Pop"
        case .sent: "Tink"
        case .reveal: "Glass"
        }
    }

    private static let cache: [Sounds: NSSound?] = Dictionary(uniqueKeysWithValues:
        [Sounds.received, .sent, .notification, .reveal].map { kind in
            let url = kind == .reveal
                ? URL(fileURLWithPath: "/System/Library/Messages/iMessageEffects/CKSpotlightEffect.bundle/Contents/Resources/Spotlight.m4r")
                : Bundle.main.url(forResource: kind.file, withExtension: "caf")
            return (kind, url.flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: kind.fallback))
        })
}
