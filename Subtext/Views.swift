import AppKit
import SwiftUI

enum Theme {
    // Real iMessage shows incoming messages in grey. Set this to false for that look.
    static let herBubbleIsBlue = true

    static let blue = LinearGradient(colors: [Color(red: 0.16, green: 0.60, blue: 1.0), Color(red: 0.03, green: 0.48, blue: 1.0)],
                                     startPoint: .top, endPoint: .bottom)
    static let purple = LinearGradient(colors: [Color(red: 0.72, green: 0.38, blue: 1.0), Color(red: 0.50, green: 0.20, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom)
    static let grey = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.23, alpha: 1)
            : NSColor(red: 0.914, green: 0.914, blue: 0.922, alpha: 1)
    })
    static let unread = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let purpleText = Color(red: 0.62, green: 0.30, blue: 1.0)
    static let decodeTint = Color(red: 0.78, green: 0.38, blue: 1.0)
    static let coolTint = Color(red: 0.55, green: 0.92, blue: 1.0)
}

struct ContentView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let id = store.selectedID, store.conversation(id) != nil {
                ChatView(convID: id)
            } else {
                Text("No Conversation Selected").foregroundStyle(.secondary)
            }
        }
        .onChange(of: store.selectedID) { store.markRead() }
    }
}

// MARK: Sidebar

struct SidebarView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            ForEach(store.visibleConversations) { conv in
                ConversationRow(conv: conv).tag(conv.id)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.search, placement: .sidebar, prompt: "Search")
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
        .toolbar {
            ToolbarItem {
                Button {} label: { Image(systemName: "square.and.pencil") }
            }
        }
    }
}

struct ConversationRow: View {
    let conv: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(conv.unread ? Theme.unread : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 20)
            Avatar(conv: conv, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conv.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conv.timeLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(conv.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
    }
}

struct Avatar: View {
    let conv: Conversation
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: conv.avatar, startPoint: .top, endPoint: .bottom))
            if let name = conv.photo, let image = NSImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .clipShape(Circle())
            } else if let emoji = conv.emoji {
                Text(emoji).font(.system(size: size * 0.48))
            } else {
                Text(conv.initials)
                    .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Chat

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    let convID: String

    var body: some View {
        if let conv = store.conversation(convID) {
            VStack(spacing: 0) {
                transcript(conv)
                    .overlay(alignment: .top) { ChatHeader(conv: conv) }
                Composer()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {} label: { Image(systemName: "video") }
                    Button {} label: { Image(systemName: "info.circle") }
                }
            }
        }
    }

    private func transcript(_ conv: Conversation) -> some View {
        let messages = conv.messages
        let lastMine = messages.lastIndex { $0.fromMe }
        return ScrollViewReader { proxy in
            ScrollView {
                TimelineView(.animation(minimumInterval: nil, paused: store.ripple == nil)) { timeline in
                    VStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            let newGroup = i == 0 || messages[i - 1].fromMe != m.fromMe
                            let header = i == 0 || m.time.timeIntervalSince(messages[i - 1].time) > 3600
                            let tail = i == messages.count - 1 || messages[i + 1].fromMe != m.fromMe
                                || messages[i + 1].time.timeIntervalSince(m.time) > 3600
                            if header {
                                Text(Fmt.headerTime(m.time))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 14)
                                    .padding(.bottom, 6)
                            }
                            MessageRow(message: m, convID: conv.id, tail: tail, herChat: conv.id == Seed.herID,
                                       delivered: i == lastMine && i == messages.count - 1)
                                .padding(.top, newGroup && !header ? 10 : 2)
                                .id(m.id)
                        }
                        if store.herTyping && conv.id == Seed.herID {
                            TypingBubble().padding(.top, 8)
                        }
                        Color.clear.frame(height: 10).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, ChatHeader.height)
                    .coordinateSpace(.named("chat"))
                    .modifier(RippleEffect(ripple: store.ripple, now: timeline.date))
                }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.count) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.herTyping) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.fx.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

// The big photo and name pill that float over the top of the chat, as in Messages.
struct ChatHeader: View {
    static let height: CGFloat = 112
    let conv: Conversation

    var body: some View {
        let background = Color(nsColor: .textBackgroundColor)
        VStack(spacing: -5) {
            Avatar(conv: conv, size: 68)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            HStack(spacing: 4) {
                Text(conv.name).font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [background, background.opacity(0.92), background.opacity(0)],
                                   startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

struct MessageRow: View {
    @Environment(ChatStore.self) private var store
    let message: Message
    let convID: String
    let tail: Bool
    let herChat: Bool
    let delivered: Bool

    var body: some View {
        let fx = store.fx[message.id]
        VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 0) {
                if message.fromMe { Spacer(minLength: 110) }
                TimelineView(.animation(minimumInterval: nil, paused: fx == nil)) { timeline in
                    let state = FXState(fx, now: timeline.date, showingAlt: message.showingAlt)
                    let style = bubbleStyle(alt: state.showAlt)
                    let full = state.showAlt ? (message.alt ?? message.text) : message.text
                    AnimatedBubble(text: state.reveal < 1 ? Scramble.text(full, revealed: state.reveal, seed: Int(state.time * 24)) : full,
                                   fill: style.fill, textColor: style.text, nextFill: fx.map { bubbleStyle(alt: $0.toAlt).fill },
                                   fromMe: message.fromMe, tail: tail, state: state, tint: fx?.tint ?? .clear,
                                   sheen: state.showAlt && !message.fromMe && !message.altIsBase && fx == nil)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .named("chat")) { location in
                    store.tap(message.id, in: convID, useBase: NSEvent.modifierFlags.contains(.option), at: location)
                }
                if !message.fromMe { Spacer(minLength: 110) }
            }
            caption(animating: fx != nil)
        }
    }

    private func bubbleStyle(alt: Bool) -> (fill: AnyShapeStyle, text: Color) {
        if message.fromMe { return (AnyShapeStyle(Theme.blue), .white) }
        if alt && message.altIsBase { return (AnyShapeStyle(Theme.grey), .primary) }
        if alt { return (AnyShapeStyle(Theme.purple), .white) }
        return Theme.herBubbleIsBlue ? (AnyShapeStyle(Theme.blue), .white) : (AnyShapeStyle(Theme.grey), .primary)
    }

    @ViewBuilder
    private func caption(animating: Bool) -> some View {
        if animating {
            EmptyView()
        } else if !message.fromMe && message.showingAlt {
            HStack(spacing: 4) {
                Text(message.altIsBase ? "base model, not fine-tuned" : "what she really means")
                    .foregroundStyle(message.altIsBase ? Color.secondary : Theme.purpleText)
                if let note = message.altNote {
                    Text("· \(note)").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.leading, 18)
        } else if message.fromMe && message.alt != nil {
            Text(message.showingAlt ? "😎 played it cool · tap to see what you nearly sent" : "💀 what you nearly sent")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 18)
        } else if message.fromMe && delivered {
            Text("Delivered")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 18)
        }
    }
}

struct BubbleView: View {
    let text: String
    let fill: AnyShapeStyle
    let textColor: Color
    let fromMe: Bool
    let tail: Bool
    var nextFill: AnyShapeStyle? = nil   // the colour it is melting into mid-flip
    var morph = 0.0

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .padding(fromMe ? .trailing : .leading, BubbleShape.tailSpace)
            .background {
                ZStack {
                    BubbleShape(fromMe: fromMe, tail: tail).fill(fill)
                    if let nextFill, morph > 0 {
                        BubbleShape(fromMe: fromMe, tail: tail).fill(nextFill).opacity(morph)
                    }
                }
            }
            .frame(maxWidth: 460, alignment: fromMe ? .trailing : .leading)
    }
}

// A bubble mid-decode: it turns away in 3D, melts into the new colour and goes to jelly, then the
// text swaps edge-on and it swings back round with an overshoot.
struct AnimatedBubble: View {
    static let room: CGFloat = 40   // transparent margin so the jelly and glow aren't clipped
    let text: String
    let fill: AnyShapeStyle
    let textColor: Color
    let nextFill: AnyShapeStyle?
    let fromMe: Bool
    let tail: Bool
    let state: FXState
    let tint: Color
    let sheen: Bool

    var body: some View {
        BubbleView(text: text, fill: fill, textColor: textColor, fromMe: fromMe, tail: tail,
                   nextFill: nextFill, morph: state.morph)
            .modifier(SheenEffect(on: sheen))
            .padding(Self.room)
            .modifier(MorphEffect(amount: state.wobble, time: state.time))
            .shadow(color: tint.opacity(0.8 * state.wobble), radius: 20 * state.wobble)
            .padding(-Self.room)
            .rotation3DEffect(.degrees(state.angle), axis: (x: 0.1, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(1 + 0.06 * state.wobble)
    }
}

// A rounded bubble with the iMessage tail. The tail lives inside the frame so Metal effects never clip it.
struct BubbleShape: Shape {
    static let tailSpace: CGFloat = 6
    var fromMe: Bool
    var tail: Bool

    func path(in rect: CGRect) -> Path {
        let t = Self.tailSpace
        let body = CGRect(x: rect.minX + (fromMe ? 0 : t), y: rect.minY, width: rect.width - t, height: rect.height)
        let bubble = Path(roundedRect: body, cornerRadius: min(18, body.height / 2), style: .continuous)
        guard tail else { return bubble }
        let s: CGFloat = fromMe ? 1 : -1
        let x = fromMe ? body.maxX : body.minX
        let y = body.maxY
        var hook = Path()
        hook.move(to: CGPoint(x: x - s * 4, y: y - 16))
        hook.addCurve(to: CGPoint(x: x + s * t, y: y),
                      control1: CGPoint(x: x - s * 4, y: y - 6), control2: CGPoint(x: x + s * 1, y: y - 1))
        hook.addCurve(to: CGPoint(x: x - s * 14, y: y - 3),
                      control1: CGPoint(x: x - s * 3, y: y + 0.5), control2: CGPoint(x: x - s * 9, y: y - 1))
        hook.addLine(to: CGPoint(x: x - s * 14, y: y - 16))
        hook.closeSubpath()
        // A union, not two subpaths: opposite winding would punch a hole where they overlap.
        return bubble.union(hook)
    }
}

struct TypingBubble: View {
    var body: some View {
        HStack {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                            .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.8)))
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .padding(.leading, BubbleShape.tailSpace)
                .background(BubbleShape(fromMe: false, tail: true).fill(Theme.grey))
            }
            Spacer()
        }
    }
}

struct Composer: View {
    @Environment(ChatStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.18)))
            }
            .buttonStyle(.plain)
            HStack {
                TextField("iMessage", text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { store.sendDraft() }
                Image(systemName: "face.smiling").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }
}

// MARK: Metal effects

struct MorphEffect: ViewModifier {
    var amount: Double
    var time: Double

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            view.distortionEffect(
                ShaderLibrary.subtextMorph(.float2(proxy.size), .float(amount), .float(time)),
                maxSampleOffset: CGSize(width: 80, height: 40),
                isEnabled: amount > 0.001)
        }
    }
}

struct RippleEffect: ViewModifier {
    var ripple: Ripple?
    var now: Date

    func body(content: Content) -> some View {
        let t = ripple.map { now.timeIntervalSince($0.start) } ?? 0
        content.layerEffect(
            ShaderLibrary.subtextRipple(.float2(ripple?.origin ?? .zero), .float(t), .float(9), .float(15),
                                        .float(5.5), .float(1100), .color(Theme.decodeTint)),
            maxSampleOffset: CGSize(width: 20, height: 20),
            isEnabled: ripple != nil && t < 1.8)
    }
}

struct SheenEffect: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !on)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            content.visualEffect { view, proxy in
                view.colorEffect(ShaderLibrary.subtextSheen(.float2(proxy.size), .float(t)), isEnabled: on)
            }
        }
    }
}
