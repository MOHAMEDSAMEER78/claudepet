import SwiftUI
import ClaudePetCore

struct CommandPaletteView: View {
    @ObservedObject var store: SessionStore
    let identityFor: (String) -> String
    let onSelect: (EffectiveSession) -> Void
    let onCancel: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private func label(for session: EffectiveSession) -> String {
        session.title ?? identityFor(session.sessionId)
    }

    private var results: [EffectiveSession] {
        let sorted = store.sessions.sorted { $0.state.priority > $1.state.priority }
        guard !query.isEmpty else { return sorted }
        let needle = query.lowercased()
        return sorted.filter {
            label(for: $0).lowercased().contains(needle)
                || ($0.cwd?.lowercased().contains(needle) ?? false)
                || $0.bubbleText.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to a session…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { onSelect(first) } }
            }
            .padding(12)

            Divider()

            if results.isEmpty {
                Text(store.sessions.isEmpty ? "No active Claude Code sessions" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results) { session in
                            Button { onSelect(session) } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(dotColor(session.state)).frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(label(for: session)).font(.system(size: 12, weight: .medium))
                                        Text(session.bubbleText)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 440)
        .background(.regularMaterial)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onHeightChange(geo.size.height) }
                    .onChange(of: geo.size.height) { onHeightChange($0) }
            }
        )
        .onAppear { searchFocused = true }
        .onExitCommand { onCancel() }
    }

    private func dotColor(_ state: PetState) -> Color {
        switch state {
        case .waitingPermission: return .orange
        case .failed: return .red
        case .review: return .green
        case .running: return .blue
        case .checking: return .purple
        case .idle: return .secondary
        }
    }
}
