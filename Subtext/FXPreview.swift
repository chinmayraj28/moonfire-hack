#if DEBUG
import AppKit
import SwiftUI

// Renders the decode burst frame by frame without a screen, for tuning the shaders:
//   Subtext.app/Contents/MacOS/Subtext -renderfx /some/folder
@MainActor
enum FXPreview {
    static func renderIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-renderfx"), i + 1 < args.count else { return }
        let dir = args[i + 1]
        let literal = "Hey great day at the beach today. I was wondering if you'd like to meet my best friend tomorrow 🙂"
        let decoded = "She likes you and trusts you enough to meet her best friend. The best friend is HR and this is your final interview. Don't fuck this up."
        // (phase, progress, reveal): burst out on the blue bubble, back in on the purple one.
        let frames: [(Bool, Double, Double)] = [(false, 0.0, 1), (false, 0.2, 1), (false, 0.45, 1), (false, 0.75, 1), (false, 1.0, 1),
                                                (true, 0.8, 0.2), (true, 0.5, 0.5), (true, 0.2, 0.8), (true, 0.0, 1)]
        for (n, frame) in frames.enumerated() {
            let (alt, progress, reveal) = frame
            let full = alt ? decoded : literal
            let view = BubbleView(text: reveal < 1 ? Scramble.text(full, revealed: reveal, seed: n * 7) : full,
                                  fill: alt ? AnyShapeStyle(Theme.purple) : AnyShapeStyle(Theme.blue),
                                  textColor: .white, fromMe: false, tail: true)
                .frame(width: 420)
                .padding(MessageRow.burst)
                .modifier(ShatterEffect(progress: progress, time: Double(n) * 0.12, tint: Theme.decodeTint))
                .shadow(color: Theme.decodeTint.opacity(0.85 * progress), radius: 22 * progress)
                .background(Color(white: 0.12))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/fx-\(n).png"))
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
