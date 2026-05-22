import SwiftUI

/// Lightweight node-search popover. ⌘F opens it; typing filters node
/// labels with a substring + initials fuzzy match; ↑/↓ navigate, ↩ selects.
struct NodeSearchView: View {
    @ObservedObject var store: GraphStore
    /// Called with the chosen node id (or `nil` to cancel).
    var onChoose: (String?) -> Void

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private struct Match: Identifiable {
        let id: String          // node id
        let label: String
        let type: String?
        let score: Int          // smaller = better
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find node…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(chooseHighlighted)
                Button {
                    onChoose(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { idx, match in
                            row(match, highlighted: idx == highlightedIndex)
                                .id(match.id)
                                .onTapGesture { onChoose(match.id) }
                        }
                    }
                }
                .onChange(of: highlightedIndex) { _, newValue in
                    let bounded = max(0, min(newValue, matches.count - 1))
                    if bounded < matches.count {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(matches[bounded].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .onAppear {
            fieldFocused = true
            highlightedIndex = 0
        }
        .onChange(of: query) { _, _ in
            highlightedIndex = 0
        }
        // Keyboard navigation
        .onKeyPress(.upArrow) {
            if !matches.isEmpty {
                highlightedIndex = max(0, highlightedIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !matches.isEmpty {
                highlightedIndex = min(matches.count - 1, highlightedIndex + 1)
            }
            return .handled
        }
    }

    private func row(_ match: Match, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            if let t = match.type {
                Circle()
                    .fill(typeColor(t))
                    .frame(width: 8, height: 8)
            } else {
                Circle().fill(.secondary).frame(width: 8, height: 8)
            }
            Text(match.label)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let t = match.type {
                Text(t)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(highlighted ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private func chooseHighlighted() {
        guard highlightedIndex < matches.count else { return }
        onChoose(matches[highlightedIndex].id)
    }

    // MARK: - Matching

    private var matches: [Match] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes = store.graph.nodes.values
        if q.isEmpty {
            return nodes.prefix(40).map { node in
                Match(id: node.id, label: node.label, type: node.type, score: 0)
            }
            .sorted { $0.label.lowercased() < $1.label.lowercased() }
        }
        let lower = q.lowercased()
        var scored: [Match] = []
        for node in nodes {
            let label = node.label
            let lLower = label.lowercased()
            if let score = Self.score(query: lower, target: lLower) {
                scored.append(Match(id: node.id, label: label, type: node.type, score: score))
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.label.lowercased() < $1.label.lowercased()
        }
        return Array(scored.prefix(60))
    }

    /// Returns a small score on match, smaller = better; nil = no match.
    /// Priority: exact label > prefix > word-prefix > substring > initials.
    private static func score(query: String, target: String) -> Int? {
        if target == query { return 0 }
        if target.hasPrefix(query) { return 10 }
        // Word prefix — split on spaces/hyphens
        let words = target.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        if words.contains(where: { $0.hasPrefix(query) }) { return 25 }
        if target.contains(query) { return 50 }
        // Initials match: query "kkm" matches "Kenneth K. Miller"
        let initials = words.compactMap { $0.first.map(Character.init) }
        if initials.count >= 2 {
            let initialsString = String(initials).lowercased()
            if initialsString.hasPrefix(query) { return 30 }
            if initialsString.contains(query) { return 60 }
        }
        return nil
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "person": return .cyan
        case "concept": return .yellow
        case "institution": return .mint
        case "event": return .orange
        case "work": return .pink
        default: return .secondary
        }
    }
}
