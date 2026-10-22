import SwiftUI

@main
struct SubtextApp: App {
    @State private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    #if DEBUG
                    FXPreview.renderIfAsked()
                    #endif
                    await store.autoplayIfAsked()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandMenu("Demo") {
                Button("She Sends Next Message") { store.herNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Send Draft as Her") { store.sendDraftAsHer() }
                    .keyboardShortcut(.return, modifiers: .option)
                Divider()
                Toggle("She Replies Automatically", isOn: Binding(
                    get: { store.autoReply },
                    set: { store.autoReply = $0 }))
                Toggle("Prefer Scripted Lines", isOn: Binding(
                    get: { store.translator.preferScript },
                    set: { store.translator.preferScript = $0 }))
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Reset Demo") { store.reset() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
