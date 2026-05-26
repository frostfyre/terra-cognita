import Foundation

/// A single AI-proposed mutation to a node. UI-facing — the chip view
/// renders one proposal and lets the user accept or reject it.
///
/// The proposal is platform-neutral (no `@Generable` here) so it can
/// live on iOS 17+ even though the model that produced it is iOS 26+.
/// The bridge from `Generable` types to `NodeProposal` happens inside
/// `NodeIntelligence`, behind the platform availability gate.
struct NodeProposal: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    /// Short natural-language reason the AI gave. Surfaced as the
    /// chip's secondary line / tooltip — helps the user judge each
    /// proposal in isolation.
    let reason: String

    init(id: UUID = UUID(), kind: Kind, reason: String) {
        self.id = id
        self.kind = kind
        self.reason = reason
    }

    enum Kind: Equatable {
        /// Append a wikilink to the current node's body. Optional
        /// Dataview relationship type emits `key:: [[target]]` form.
        case addLink(target: String, relationshipType: String?)
        /// Create a fresh node *and* add a wikilink from the current
        /// node to it. Used by Find-Works and Extract-Concepts.
        case createLinkedNode(label: String,
                              type: String,
                              era: String?,
                              relationshipType: String?)
        /// Set (or update) a single YAML front-matter key on the
        /// current node. Used by Suggest-Era.
        case setFrontMatter(key: String, value: String)
        /// Replace the body of the current node wholesale. Used by
        /// Rewrite-As. Heaviest mutation — the chip should show a diff
        /// preview rather than just a one-liner.
        case replaceBody(newBody: String)
    }

    var summary: String {
        switch kind {
        case .addLink(let target, let rel):
            if let rel { return "+ \(rel):: [[\(target)]]" }
            return "+ link to [[\(target)]]"
        case .createLinkedNode(let label, let type, _, let rel):
            let arrow = rel.map { "(\($0)) " } ?? ""
            return "+ new \(type): [[\(label)]] \(arrow)"
        case .setFrontMatter(let key, let value):
            return "✎ \(key): \(value)"
        case .replaceBody:
            return "✎ rewrite note"
        }
    }
}
