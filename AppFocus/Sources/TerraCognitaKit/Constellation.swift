import Foundation

/// A Capture proposal: a small graph fragment the AI extracted from
/// user input. Each `NewNode` carries everything we need to materialize
/// it (label / type / era / body), the wikilinks the AI proposed
/// (internal between new nodes + external to existing graph nodes), and
/// an optional Wikipedia enrichment.
///
/// Lives outside `NodeIntelligence` so the UI can render proposals
/// without importing FoundationModels.
struct Constellation: Equatable {
    var inputText: String
    var nodes: [NewNode]

    struct NewNode: Identifiable, Equatable {
        let id: UUID
        var label: String
        var type: String
        var era: String?
        var body: String
        /// Labels of other new nodes in this same batch this node
        /// should link to.
        var linksToNew: [String]
        /// Labels of existing graph nodes this node should link to.
        var linksToExisting: [String]
        /// Wikipedia summary if one was fetched (network + match).
        var enrichmentTitle: String?
        var enrichmentURL: URL?
        /// User toggle — defaults to true; the review UI lets the user
        /// flip this off to skip individual nodes.
        var accepted: Bool

        init(label: String,
             type: String,
             era: String? = nil,
             body: String = "",
             linksToNew: [String] = [],
             linksToExisting: [String] = [],
             enrichmentTitle: String? = nil,
             enrichmentURL: URL? = nil,
             accepted: Bool = true) {
            self.id = UUID()
            self.label = label
            self.type = type
            self.era = era
            self.body = body
            self.linksToNew = linksToNew
            self.linksToExisting = linksToExisting
            self.enrichmentTitle = enrichmentTitle
            self.enrichmentURL = enrichmentURL
            self.accepted = accepted
        }
    }

    var acceptedCount: Int { nodes.filter { $0.accepted }.count }
}
