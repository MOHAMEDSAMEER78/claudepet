import SwiftUI
import ClaudePetCore

private enum CodexChrome {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let border = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.42, green: 0.55, blue: 0.98)
}

private struct CodexBubbleModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var maxWidth: CGFloat?
    var badge: AnyView? = nil

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(CodexChrome.background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(CodexChrome.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    badge
                        .offset(x: 6, y: -6)
                }
            }
    }
}

private extension View {
    func codexBubble(cornerRadius: CGFloat = 18, maxWidth: CGFloat? = nil, badge: AnyView? = nil) -> some View {
        modifier(CodexBubbleModifier(cornerRadius: cornerRadius, maxWidth: maxWidth, badge: badge))
    }
}

private struct StatusBadge: View {
    let state: PetState
    @State private var blink = false

    var body: some View {
        ZStack {
            Circle()
                .fill(CodexChrome.background)
            Circle()
                .strokeBorder(CodexChrome.border, lineWidth: 1)
            content
        }
        .frame(width: 18, height: 18)
        .onAppear {
            if state == .running { startBlinking() }
        }
        .onChange(of: state) { newState in
            if newState == .running {
                startBlinking()
            } else {
                blink = false
            }
        }
    }

    private func startBlinking() {
        blink = false
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            blink = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .running:
            Circle()
                .fill(Color.yellow)
                .frame(width: 9, height: 9)
                .opacity(blink ? 0.25 : 1)
        case .review:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        case .waitingPermission:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .checking:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.purple)
        case .idle:
            EmptyView()
        }
    }
}

private struct PetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct PetQuickActions {
    var bringToFront: () -> Void
    var copySummary: () -> Void
    var openTranscript: (() -> Void)?
    var endSession: () -> Void
}

struct PetContentView: View {
    let state: PetState
    let identityName: String
    let bubbleText: String
    let footnote: String?
    @ObservedObject var library: PetLibrary
    var assetKey: String? = nil
    var overrideRow: String? = nil
    var moodTint: Color? = nil
    var tasksDone: Int? = nil
    var tasksTotal: Int? = nil
    var onTap: (() -> Void)?
    var onSizeChange: ((CGSize) -> Void)? = nil
    var quickActions: PetQuickActions? = nil

    @State private var bobbing = false

    private var resolvedAsset: PetAsset? { library.asset(forKey: assetKey) }

    var body: some View {
        VStack(spacing: 6) {
            sprite.colorMultiply(moodTint ?? .white)

            if !bubbleText.isEmpty {
                ActivityCard(
                    state: state,
                    name: identityName,
                    message: bubbleText,
                    tasksDone: tasksDone,
                    tasksTotal: tasksTotal
                )
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .top)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PetContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PetContentSizeKey.self) { onSizeChange?($0) }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(identityName), \(state.label)")
        .accessibilityValue(bubbleText)
        .contextMenu {
            if let quickActions {
                Button("Bring to Front", action: quickActions.bringToFront)
                Button("Copy Summary", action: quickActions.copySummary)
                if let openTranscript = quickActions.openTranscript {
                    Button("Reveal Transcript in Finder", action: openTranscript)
                }
                Divider()
                Button("End Session", role: .destructive, action: quickActions.endSession)
            }
        }
    }

    @ViewBuilder
    private var sprite: some View {
        Group {
            if let asset = resolvedAsset {
                PetSpriteView(asset: asset, state: state, overrideRow: overrideRow)
            } else if overrideRow == "jumping" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .offset(y: -18)
                    .shadow(radius: 3)
            } else if overrideRow == "waving" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .rotationEffect(.degrees(-12))
                    .shadow(radius: 3)
            } else if overrideRow == "stretching" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .scaleEffect(x: 1.0, y: 1.15, anchor: .bottom)
                    .shadow(radius: 3)
            } else if overrideRow == "looking-around" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .rotationEffect(.degrees(10))
                    .shadow(radius: 3)
            } else {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .offset(y: bobbing ? -4 : 4)
                    .animation(
                        .easeInOut(duration: animationSpeed).repeatForever(autoreverses: true),
                        value: bobbing
                    )
                    .onAppear { bobbing = true }
                    .shadow(radius: 3)
            }
        }
    }

    private var animationSpeed: Double {
        switch state {
        case .running: return 0.35
        case .waitingPermission: return 0.5
        case .failed: return 0.25
        default: return 1.2
        }
    }
}

struct ActivityCard: View {
    let state: PetState
    let name: String
    let message: String
    let tasksDone: Int?
    let tasksTotal: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CodexChrome.primaryText)
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexChrome.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let total = tasksTotal, total > 0, let done = tasksDone {
                TaskProgressRing(done: done, total: total)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10))
        .codexBubble(maxWidth: 210, badge: AnyView(StatusBadge(state: state)))
    }
}

struct TaskProgressRing: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(CodexChrome.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CodexChrome.primaryText)
        }
        .frame(width: 30, height: 30)
    }
}

struct PetView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var library: PetLibrary
    @ObservedObject var animator: PetAnimator
    @ObservedObject var progressStore: PetProgressStore
    var onOpenTray: (() -> Void)? = nil
    var onSizeChange: ((CGSize) -> Void)? = nil

    private var moodTint: Color? {
        switch progressStore.progress.level {
        case 0: return nil
        case 1, 2: return Color(red: 1.0, green: 0.97, blue: 0.85)
        default: return Color(red: 1.0, green: 0.92, blue: 0.62)
        }
    }

    private var quickActions: PetQuickActions? {
        guard let session = store.winningSession else { return nil }
        return PetQuickActions(
            bringToFront: {
                TerminalFocuser.focus(
                    terminalApp: session.terminalApp, terminalPid: session.terminalPid,
                    tty: session.tty, cwd: session.cwd
                )
            },
            copySummary: { Clipboard.copy(session.bubbleText) },
            openTranscript: TranscriptUsage.transcriptURL(forSession: session.sessionId).map { url in
                { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            },
            endSession: { store.killSession(session) }
        )
    }

    var body: some View {
        PetContentView(
            state: store.aggregate,
            identityName: store.title ?? library.current?.name ?? "Claude",
            bubbleText: store.bubbleText,
            footnote: store.sessionCount > 1 ? "\(store.sessionCount) sessions - click to switch" : nil,
            library: library,
            overrideRow: animator.overrideRow,
            moodTint: moodTint,
            tasksDone: store.tasksDone,
            tasksTotal: store.tasksTotal,
            onTap: {
                animator.triggerJump()
                onOpenTray?()
            },
            onSizeChange: onSizeChange,
            quickActions: quickActions
        )
    }
}

struct SinglePetView: View {
    @ObservedObject var viewModel: SessionPetViewModel
    @ObservedObject var library: PetLibrary
    var onSizeChange: ((CGSize) -> Void)? = nil
    var onEndSession: (() -> Void)? = nil

    private var quickActions: PetQuickActions? {
        guard let onEndSession else { return nil }
        return PetQuickActions(
            bringToFront: { viewModel.focusTerminal() },
            copySummary: { Clipboard.copy(viewModel.bubbleText) },
            openTranscript: TranscriptUsage.transcriptURL(forSession: viewModel.sessionId).map { url in
                { NSWorkspace.shared.open(url) }
            },
            endSession: onEndSession
        )
    }

    var body: some View {
        PetContentView(
            state: viewModel.state,
            identityName: viewModel.title ?? viewModel.identityName,
            bubbleText: viewModel.bubbleText,
            footnote: nil,
            library: library,
            assetKey: viewModel.assetKey,
            overrideRow: viewModel.overrideRow,
            tasksDone: viewModel.tasksDone,
            tasksTotal: viewModel.tasksTotal,
            onTap: {
                viewModel.triggerJump()
                viewModel.focusTerminal()
            },
            onSizeChange: onSizeChange,
            quickActions: quickActions
        )
    }
}
