#if DEBUG
import AppKit
import SwiftUI

// Renders the decode flip frame by frame without a screen, for tuning the shaders:
//   Subtext.app/Contents/MacOS/Subtext -renderfx /some/folder
@MainActor
enum FXPreview {
    static func renderIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-renderfx"), i + 1 < args.count else { return }
        let dir = args[i + 1]
        let literal = "Hey great day at the beach today. I was wondering if you'd like to meet my best friend tomorrow 🙂"
        let decoded = "She likes you and trusts you enough to meet her best friend. The best friend is HR and this is your final interview. Don't fuck this up."
        // Times through one decode (seconds from the click); the swap happens at rampIn.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let times = [0.0, 0.15, 0.3, 0.4, 0.5, 0.65, 0.85, 1.1, 1.4]
        for (n, t) in times.enumerated() {
            let fx = FX(start: start, swapAt: start.addingTimeInterval(FX.rampIn), toAlt: true, tint: Theme.decodeTint)
            let state = FXState(fx, now: start.addingTimeInterval(t), showingAlt: false)
            let full = state.showAlt ? decoded : literal
            let view = AnimatedBubble(text: state.reveal < 1 ? Scramble.text(full, revealed: state.reveal, seed: n * 7) : full,
                                      fill: state.showAlt ? AnyShapeStyle(Theme.purple) : AnyShapeStyle(Theme.blue),
                                      textColor: .white, nextFill: AnyShapeStyle(Theme.purple), fromMe: false, tail: true,
                                      state: state, tint: Theme.decodeTint, sheen: false)
                .frame(width: 420)
                .padding(60)
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
