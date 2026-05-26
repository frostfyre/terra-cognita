import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM integration for the graph workbench.
///
/// All Foundation Models calls are gated behind `#if canImport(FoundationModels)`
/// (compile time) and `@available(macOS 26, *)` (runtime) so the app
/// continues to build and run on macOS 14/15 — the AI panel just shows
/// an "unavailable" message there.
///
/// `NodeIntelligence` keeps a single `LanguageModelSession` alive per
/// conversation so follow-up questions inherit the prior context. The
/// session resets whenever the inspector calls `prepare(for:)` with a
/// new node id.
@MainActor
final class NodeIntelligence: ObservableObject {

    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant, system }
        let id = UUID()
        let role: Role
        let content: String
    }

    enum Activity: Equatable {
        case idle
        case running
        case failed(String)
        case unavailable(String)
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var activity: Activity = .idle
    /// Pending proposals from the most-recent structured-generation
    /// call. UI renders these as accept/reject chips.
    @Published var proposals: [NodeProposal] = []

    /// Status text shown during a multi-step Capture flow ("Extracting…",
    /// "Searching the web for context…", etc.). Empty when idle.
    @Published var captureStatus: String = ""

    /// True only when the on-device model is ready to take a request.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    var availabilityNote: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to enable AI features."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading."
            case .unavailable(_):
                return "On-device model is unavailable right now."
            }
        }
        return "Requires macOS 26 or later."
        #else
        return "Foundation Models framework is unavailable in this build."
        #endif
    }

    /// Reset the conversation and bind to a new node. Cheaper than tearing
    /// down the whole intelligence object on each navigation.
    func prepare(for node: Node) {
        cancel()
        messages.removeAll()
        proposals.removeAll()
        boundNodeID = node.id
        boundContextPrompt = Self.contextPrompt(for: node)
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            session = LanguageModelSession(instructions: Self.instructions)
        } else {
            session = nil
        }
        #else
        session = nil
        #endif
        activity = .idle
    }

    /// Remove a proposal (e.g. after user accepts or rejects it).
    func dismissProposal(_ id: UUID) {
        proposals.removeAll { $0.id == id }
    }

    /// Run the Capture flow against a free-form text blob: AI extracts
    /// a constellation of new nodes + edges, then (if online) Wikipedia
    /// enrichments are folded in per node in parallel. Returns `nil`
    /// when the model is unavailable or the call refuses; `activity`
    /// carries the user-facing error.
    func runCapture(text: String, graph: Graph) async -> Constellation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard isAvailable else {
            activity = .unavailable(availabilityNote ?? "Unavailable.")
            return nil
        }
        activity = .running
        captureStatus = "Extracting structure…"
        defer {
            captureStatus = ""
            activity = .idle
        }
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            do {
                var constellation = try await Self.extractConstellation(text: trimmed, graph: graph)
                captureStatus = "Searching the web for context…"
                await Self.enrich(constellation: &constellation, graph: graph)
                return constellation
            } catch LanguageModelSession.GenerationError.refusal {
                activity = .failed("Model declined to extract — try a different framing.")
                return nil
            } catch {
                activity = .failed(error.localizedDescription)
                return nil
            }
        }
        #endif
        activity = .unavailable(availabilityNote ?? "Unavailable.")
        return nil
    }

    /// Kick off a node summary as a fresh-conversation first turn.
    func summarize(node: Node) {
        ensureBound(node)
        let prompt = "Summarize this note in three or four sentences. Use only what's in the note."
        send(userPrompt: prompt)
    }

    /// Explain how the bound node relates to a neighbour, using the
    /// neighbour's note text as additional context.
    func explainRelationship(to other: Node, relationshipType: String?, currentNode: Node) {
        ensureBound(currentNode)
        let neighborSection = """

        --- Note: "\(other.label)" ---
        \(Self.trimmedBody(other.markdownContent ?? ""))
        """
        let prompt = """
        Using the note above and the note below, explain in two or three sentences \
        how "\(currentNode.label)" connects to "\(other.label)"\
        \(relationshipType.map { " (relationship type: \($0))" } ?? ""). \
        If the connection isn't clear, say so plainly rather than guessing.
        \(neighborSection)
        """
        send(userPrompt: prompt)
    }

    /// Send a free-form follow-up question. The session keeps prior turns
    /// in its transcript so the model can refer back.
    func ask(_ question: String, currentNode: Node) {
        ensureBound(currentNode)
        send(userPrompt: question)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        activity = .idle
    }

    // MARK: - Internals

    private var session: Any? // Type-erased so the file compiles pre-macOS 26.
    private var currentTask: Task<Void, Never>?
    private var boundNodeID: String?
    private var boundContextPrompt: String = ""

    private func ensureBound(_ node: Node) {
        if boundNodeID != node.id {
            prepare(for: node)
        }
    }

    private func send(userPrompt: String) {
        guard isAvailable else {
            activity = .unavailable(availabilityNote ?? "Unavailable.")
            return
        }
        cancel()

        // Prepend the bound node's body on the first turn only — subsequent
        // turns can rely on the session's transcript memory.
        let fullPrompt: String
        if messages.isEmpty {
            fullPrompt = boundContextPrompt + "\n\nQuestion: " + userPrompt
        } else {
            fullPrompt = userPrompt
        }

        messages.append(Message(role: .user, content: userPrompt))
        activity = .running

        currentTask = Task { [weak self] in
            await self?.perform(prompt: fullPrompt)
        }
    }

    private func perform(prompt: String) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            guard let session = session as? LanguageModelSession else {
                activity = .failed("No session.")
                return
            }
            do {
                let response = try await session.respond(to: prompt)
                if Task.isCancelled { return }
                messages.append(Message(role: .assistant, content: response.content))
                activity = .idle
            } catch {
                if Task.isCancelled { return }
                activity = .failed(error.localizedDescription)
            }
            return
        }
        #endif
        activity = .unavailable(availabilityNote ?? "Unavailable.")
    }

    // MARK: - Structured proposals (the operations row)

    /// Operation identifier used by the UI's preset buttons. Maps to a
    /// specific prompt + Generable schema combination below.
    enum Operation: String, CaseIterable, Identifiable {
        case findLinks       = "Find links in current graph"
        case suggestConnect  = "Suggest connections"
        case suggestEra      = "Suggest era"
        case findWorks       = "Find and link public works"
        case extractConcepts = "Extract key concepts"
        case rewriteConcise  = "Rewrite — concise"
        case rewriteExpanded = "Rewrite — expanded"
        case rewriteFormal   = "Rewrite — formal"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .findLinks:       return "link"
            case .suggestConnect:  return "point.3.connected.trianglepath.dotted"
            case .suggestEra:      return "calendar.badge.clock"
            case .findWorks:       return "books.vertical"
            case .extractConcepts: return "lightbulb.max"
            case .rewriteConcise:  return "text.alignleft"
            case .rewriteExpanded: return "text.append"
            case .rewriteFormal:   return "text.justify"
            }
        }
    }

    /// Kick off one of the named operations against the bound node.
    /// Populates `proposals` on success; sets `.failed` activity on
    /// model error or refusal.
    func runOperation(_ op: Operation, node: Node, graph: Graph) {
        ensureBound(node)
        cancel()
        proposals.removeAll()
        guard isAvailable else {
            activity = .unavailable(availabilityNote ?? "Unavailable.")
            return
        }
        activity = .running
        currentTask = Task { [weak self] in
            await self?.performOperation(op, node: node, graph: graph)
        }
    }

    private func performOperation(_ op: Operation, node: Node, graph: Graph) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            do {
                let results: [NodeProposal] = try await Self.proposals(
                    for: op,
                    node: node,
                    graph: graph
                )
                if Task.isCancelled { return }
                proposals = results
                activity = .idle
            } catch LanguageModelSession.GenerationError.refusal {
                if Task.isCancelled { return }
                activity = .failed("Model declined to respond — try rephrasing or a different operation.")
            } catch {
                if Task.isCancelled { return }
                activity = .failed(error.localizedDescription)
            }
            return
        }
        #endif
        activity = .unavailable(availabilityNote ?? "Unavailable.")
    }

    // MARK: - Prompt scaffolding

    private static let instructions = """
    You help a person navigate their personal heritage map — a graph of \
    people, institutions, works, events and concepts that have shaped them. \
    Answer based only on the notes provided in the conversation. Keep \
    responses concise (one short paragraph by default). If the notes don't \
    contain enough information to answer, say so plainly instead of guessing.
    """

    private static func contextPrompt(for node: Node) -> String {
        let kind = node.attributes["type"] ?? node.attributes["folder"] ?? "entry"
        return """
        We are looking at this \(kind) note:

        Title: \(node.label)

        \(trimmedBody(node.markdownContent ?? ""))
        """
    }

    private static func trimmedBody(_ raw: String) -> String {
        var body = raw
        if body.hasPrefix("---") {
            if let end = body.range(of: "\n---",
                                    options: [],
                                    range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[body.index(end.upperBound, offsetBy: 0)...])
            }
        }
        if body.count > 3500 {
            body = String(body.prefix(3500)) + "\n…"
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - FoundationModels structured generation
//
// All `@Generable` types and the prompt → proposal bridge live in a
// single availability-gated block so the rest of the file compiles on
// every supported OS.

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
extension NodeIntelligence {

    // ---- Generable schemas (intermediate, model-facing types) ----

    @Generable
    struct GenLink {
        @Guide(description: "Existing node label to link to (must be one of the provided labels)")
        let target: String
        @Guide(description: "Optional Dataview relationship type (e.g. influenced-by, worked-at). Omit if none.")
        let relationshipType: String?
        @Guide(description: "Short reason this link makes sense (one sentence)")
        let reason: String
    }

    @Generable
    struct GenLinkBatch {
        @Guide(description: "Up to six proposed links", .count(0...6))
        let proposals: [GenLink]
    }

    @Generable
    struct GenNewNode {
        @Guide(description: "Label for the new node")
        let label: String
        @Guide(description: "Optional Dataview relationship from the current note (e.g. directed, wrote, influenced-by)")
        let relationshipType: String?
        @Guide(description: "One-sentence reason this should be its own node")
        let reason: String
    }

    @Generable
    struct GenNewNodeBatch {
        @Guide(description: "Up to six proposed new nodes", .count(0...6))
        let proposals: [GenNewNode]
    }

    @Generable
    struct GenEra {
        @Guide(description: "One of: pre-conscious, self-choosing-childhood, pre-blizzard, early-career, blizzard-era, bridge, post-formation, post-blizzard, current, career-spanning")
        let era: String
        @Guide(description: "Short justification grounded in the note body")
        let reason: String
    }

    @Generable
    struct GenRewrite {
        @Guide(description: "The rewritten note body — markdown, preserve all [[wikilinks]] verbatim")
        let body: String
        @Guide(description: "What changed in one short sentence")
        let reason: String
    }

    @Generable
    struct GenCaptureNode {
        @Guide(description: "The node's label (concise — what you'd write on a card)")
        let label: String
        @Guide(description: "One of: concept, person, institution, event, work")
        let type: String
        @Guide(description: "Optional era taxonomy value from: pre-conscious, self-choosing-childhood, pre-blizzard, early-career, blizzard-era, bridge, post-formation, post-blizzard, current, career-spanning. Omit if unknown.")
        let era: String?
        @Guide(description: "Short body (1-3 sentences) synthesizing what the input says about this node")
        let body: String
        @Guide(description: "Labels of OTHER new nodes in this batch this node connects to", .count(0...6))
        let linksToNew: [String]
        @Guide(description: "Labels of EXISTING graph nodes this node connects to (must come from the provided list)", .count(0...6))
        let linksToExisting: [String]
    }

    @Generable
    struct GenConstellation {
        @Guide(description: "Up to 8 new nodes extracted from the input text", .count(0...8))
        let nodes: [GenCaptureNode]
    }

    @Generable
    struct GenLinkOnly {
        @Guide(description: "Target node label (must appear in the provided existing-labels list)")
        let target: String
        @Guide(description: "Optional Dataview relationship type")
        let relationshipType: String?
    }

    @Generable
    struct GenLinkOnlyBatch {
        @Guide(description: "Up to four additional links", .count(0...4))
        let proposals: [GenLinkOnly]
    }

    // ---- Capture orchestration ----

    fileprivate static func extractConstellation(text: String,
                                                 graph: Graph) async throws -> Constellation {
        let session = LanguageModelSession(instructions: instructions)
        // Cap candidates so the prompt fits comfortably.
        let candidates = graph.nodes.values.prefix(120).map { node -> String in
            if let t = node.type { return "\(node.label) [\(t)]" }
            return node.label
        }
        let candidateList = candidates.joined(separator: "\n- ")

        let prompt = """
        Extract a graph of nodes from this captured note. Be assertive:
        each distinct person, work, institution, concept, or event in
        the text should be its own node. Each new node's `body` should
        synthesize (not quote) what the input says.

        For every new node, propose:
          • `linksToNew` — wikilinks to OTHER new nodes in this batch
          • `linksToExisting` — wikilinks to existing graph nodes
            that the new node connects to thematically. Use semantic
            affinity, not just literal mentions.

        ONLY use labels from the existing-labels list below for
        `linksToExisting`.

        Captured note:
        \"\"\"
        \(text)
        \"\"\"

        Existing graph labels:
        - \(candidateList)
        """
        let response = try await session.respond(to: prompt, generating: GenConstellation.self)

        // Build the platform-neutral Constellation. Filter external
        // links down to those that actually resolve in the graph (case
        // insensitive on label or id).
        let existingLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: graph.nodes.values.map { ($0.label.lowercased(), $0.label) }
        )
        let newLabelSet = Set(response.content.nodes.map { $0.label.lowercased() })
        let constellationNodes: [Constellation.NewNode] = response.content.nodes.map { n in
            let cleanedExternal = n.linksToExisting
                .compactMap { existingLookup[$0.lowercased()] }
            let cleanedInternal = n.linksToNew
                .filter { newLabelSet.contains($0.lowercased()) && $0.lowercased() != n.label.lowercased() }
            return Constellation.NewNode(
                label: n.label,
                type: n.type,
                era: (n.era?.isEmpty == false) ? n.era : nil,
                body: n.body,
                linksToNew: cleanedInternal,
                linksToExisting: cleanedExternal
            )
        }
        return Constellation(inputText: text, nodes: constellationNodes)
    }

    fileprivate static func enrich(constellation: inout Constellation,
                                   graph: Graph) async {
        let labels = constellation.nodes.map { $0.label }
        let summaries = await WebEnrichment.shared.summaries(for: labels)
        guard !summaries.isEmpty else { return }

        // Re-run link-finding *per enriched node* with the summary
        // injected, so the AI can spot additional links it missed
        // without the world-knowledge boost. Parallelise — each call
        // is a fresh LanguageModelSession.
        let candidates = graph.nodes.values.prefix(120).map { node -> String in
            if let t = node.type { return "\(node.label) [\(t)]" }
            return node.label
        }
        let existingLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: graph.nodes.values.map { ($0.label.lowercased(), $0.label) }
        )

        let additions: [UUID: (body: String, title: String, url: URL?, extraLinks: [String])]
        = await withTaskGroup(
            of: (UUID, (String, String, URL?, [String]))?.self
        ) { group in
            for node in constellation.nodes {
                guard let summary = summaries[node.label] else { continue }
                group.addTask {
                    let extra = await suggestExtraLinks(
                        body: node.body + "\n\n" + summary.extract,
                        label: node.label,
                        candidateList: candidates.joined(separator: "\n- "),
                        existingLookup: existingLookup,
                        alreadyLinked: Set(node.linksToExisting.map { $0.lowercased() })
                    )
                    return (node.id, (summary.extract, summary.title, summary.pageURL, extra))
                }
            }
            var out: [UUID: (String, String, URL?, [String])] = [:]
            for await result in group {
                if let (id, payload) = result { out[id] = payload }
            }
            return out
        }

        for i in constellation.nodes.indices {
            guard let payload = additions[constellation.nodes[i].id] else { continue }
            // Fold the Wikipedia extract into the body (separated so
            // the user can see where it came from).
            let (extract, title, url, extras) = payload
            var body = constellation.nodes[i].body
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { body += "\n\n" }
            body += "*From Wikipedia:* \(extract)"
            constellation.nodes[i].body = body
            constellation.nodes[i].enrichmentTitle = title
            constellation.nodes[i].enrichmentURL = url
            // Merge in the additional existing-graph links (dedup).
            var seen = Set(constellation.nodes[i].linksToExisting.map { $0.lowercased() })
            for label in extras where !seen.contains(label.lowercased()) {
                constellation.nodes[i].linksToExisting.append(label)
                seen.insert(label.lowercased())
            }
        }
    }

    private static func suggestExtraLinks(body: String,
                                          label: String,
                                          candidateList: String,
                                          existingLookup: [String: String],
                                          alreadyLinked: Set<String>) async -> [String] {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Note "\(label)":

        \(body)

        Propose up to four ADDITIONAL existing-graph nodes this note
        should link to. ONLY use labels from the list. Don't repeat
        anything the note already links to.

        Existing labels:
        - \(candidateList)
        """
        do {
            let response = try await session.respond(to: prompt, generating: GenLinkOnlyBatch.self)
            return response.content.proposals
                .compactMap { existingLookup[$0.target.lowercased()] }
                .filter { !alreadyLinked.contains($0.lowercased()) }
        } catch {
            return []
        }
    }

    // ---- Operation dispatch ----

    fileprivate static func proposals(for op: Operation,
                                      node: Node,
                                      graph: Graph) async throws -> [NodeProposal] {
        let session = LanguageModelSession(instructions: instructions)
        let body = trimmedBody(node.markdownContent ?? "")
        let label = node.label
        let kind = node.attributes["type"] ?? "entry"

        switch op {
        case .findLinks:
            return try await findLinks(session: session, body: body, label: label, kind: kind, graph: graph, currentID: node.id)
        case .suggestConnect:
            return try await suggestConnections(session: session, body: body, label: label, kind: kind, graph: graph, currentID: node.id)
        case .suggestEra:
            return try await suggestEra(session: session, body: body, label: label)
        case .findWorks:
            return try await findWorks(session: session, body: body, label: label, graph: graph)
        case .extractConcepts:
            return try await extractConcepts(session: session, body: body, label: label, graph: graph)
        case .rewriteConcise:
            return try await rewrite(session: session, body: body, label: label,
                                     instruction: "more concisely — preserve the author's voice, keep every [[wikilink]] verbatim, don't introduce new facts. Aim for roughly two-thirds the original length.")
        case .rewriteExpanded:
            return try await rewrite(session: session, body: body, label: label,
                                     instruction: "with more depth — keep the author's voice and every existing [[wikilink]], add at most a sentence or two per paragraph drawing out implications already present in the text. Don't introduce new facts.")
        case .rewriteFormal:
            return try await rewrite(session: session, body: body, label: label,
                                     instruction: "in a more formal register — keep every [[wikilink]] verbatim, don't change the content, just elevate the prose: complete sentences, third-person where natural, less colloquial.")
        }
    }

    // ---- Individual operations ----

    private static func findLinks(session: LanguageModelSession,
                                  body: String,
                                  label: String,
                                  kind: String,
                                  graph: Graph,
                                  currentID: String) async throws -> [NodeProposal] {
        // Restrict candidates to nodes not already linked, capped so the
        // prompt fits comfortably in the context window.
        let existingTargets: Set<String> = Set(graph.edges
            .filter { $0.sourceID == currentID }
            .map { $0.targetID })
        let candidates = graph.nodes.values
            .filter { $0.id != currentID && !existingTargets.contains($0.id) }
            .prefix(120)
            .map { $0.label }
        let candidateList = candidates.joined(separator: "\n- ")

        let prompt = """
        We are reading this \(kind) note titled "\(label)":

        \(body)

        Below is a list of EXISTING node labels in the graph. Propose up
        to six wikilinks the body's content implies but doesn't already
        explicitly link. ONLY propose targets that appear in the list.
        Skip the note itself. Prefer concrete, specific connections.

        Existing labels:
        - \(candidateList)
        """
        let response = try await session.respond(to: prompt, generating: GenLinkBatch.self)
        let valid = Set(candidates.map { $0.lowercased() })
        return response.content.proposals
            .filter { valid.contains($0.target.lowercased()) }
            .map {
                NodeProposal(
                    kind: .addLink(target: $0.target, relationshipType: $0.relationshipType),
                    reason: $0.reason
                )
            }
    }

    private static func suggestConnections(session: LanguageModelSession,
                                           body: String,
                                           label: String,
                                           kind: String,
                                           graph: Graph,
                                           currentID: String) async throws -> [NodeProposal] {
        // Broader than findLinks: propose connections by topic / theme,
        // not just by literal mention in the body.
        let existingTargets: Set<String> = Set(graph.edges
            .filter { $0.sourceID == currentID }
            .map { $0.targetID })
        let candidates = graph.nodes.values
            .filter { $0.id != currentID && !existingTargets.contains($0.id) }
            .prefix(120)
            .map { node -> String in
                if let t = node.type { return "\(node.label) [\(t)]" }
                return node.label
            }
        let candidateList = candidates.joined(separator: "\n- ")

        let prompt = """
        Note "\(label)" (\(kind)):

        \(body)

        Propose up to six existing nodes that share a meaningful theme,
        influence, or affinity with this note — not just literal mentions.
        ONLY propose labels from the list. Skip the note itself.

        Existing labels:
        - \(candidateList)
        """
        let response = try await session.respond(to: prompt, generating: GenLinkBatch.self)
        // Strip the optional [type] suffix we added to disambiguate.
        let lookup: [String: String] = Dictionary(uniqueKeysWithValues:
            graph.nodes.values.map { ($0.label.lowercased(), $0.label) })
        return response.content.proposals.compactMap { p in
            let bareLabel = lookup[p.target.lowercased()] ?? p.target
            guard lookup[bareLabel.lowercased()] != nil else { return nil }
            return NodeProposal(
                kind: .addLink(target: bareLabel, relationshipType: p.relationshipType),
                reason: p.reason
            )
        }
    }

    private static func suggestEra(session: LanguageModelSession,
                                   body: String,
                                   label: String) async throws -> [NodeProposal] {
        let prompt = """
        Note "\(label)":

        \(body)

        Pick exactly one `era:` value from this ordered taxonomy:
        pre-conscious, self-choosing-childhood, pre-blizzard,
        early-career, blizzard-era, bridge, post-formation,
        post-blizzard, current, career-spanning.

        Base your choice on the dates / period implied in the body.
        """
        let response = try await session.respond(to: prompt, generating: GenEra.self)
        return [NodeProposal(
            kind: .setFrontMatter(key: "era", value: response.content.era),
            reason: response.content.reason
        )]
    }

    private static func findWorks(session: LanguageModelSession,
                                  body: String,
                                  label: String,
                                  graph: Graph) async throws -> [NodeProposal] {
        let existingLower = Set(graph.nodes.keys.map { $0.lowercased() }
                                + graph.nodes.values.map { $0.label.lowercased() })
        let prompt = """
        Note "\(label)":

        \(body)

        List up to six public *works* mentioned in the body — films,
        books, games, albums, etc. — that should each become a node of
        their own. For each, pick a Dataview-style relationshipType
        connecting this note to the work (e.g. directed, wrote, played,
        watched, influenced-by). Use the title exactly as it appears.
        Skip anything that's clearly already a node in this graph.
        """
        let response = try await session.respond(to: prompt, generating: GenNewNodeBatch.self)
        return response.content.proposals.compactMap { p in
            // Drop dupes against the existing graph (we'll let
            // GraphStore.createNode block real collisions on submit).
            if existingLower.contains(p.label.lowercased()) { return nil }
            return NodeProposal(
                kind: .createLinkedNode(
                    label: p.label,
                    type: "work",
                    era: nil,
                    relationshipType: p.relationshipType
                ),
                reason: p.reason
            )
        }
    }

    private static func extractConcepts(session: LanguageModelSession,
                                        body: String,
                                        label: String,
                                        graph: Graph) async throws -> [NodeProposal] {
        let existingLower = Set(graph.nodes.keys.map { $0.lowercased() }
                                + graph.nodes.values.map { $0.label.lowercased() })
        let prompt = """
        Note "\(label)":

        \(body)

        Identify up to six stable, reusable *concepts* this note expresses
        — abstract ideas, methods, recurring themes. Each should be a
        thing that could also describe other notes in the heritage graph.
        Skip anything that's a person, work, or institution.
        """
        let response = try await session.respond(to: prompt, generating: GenNewNodeBatch.self)
        return response.content.proposals.compactMap { p in
            if existingLower.contains(p.label.lowercased()) { return nil }
            return NodeProposal(
                kind: .createLinkedNode(
                    label: p.label,
                    type: "concept",
                    era: nil,
                    relationshipType: p.relationshipType
                ),
                reason: p.reason
            )
        }
    }

    private static func rewrite(session: LanguageModelSession,
                                body: String,
                                label: String,
                                instruction: String) async throws -> [NodeProposal] {
        let prompt = """
        Note "\(label)":

        \(body)

        Rewrite the body \(instruction)
        """
        let response = try await session.respond(to: prompt, generating: GenRewrite.self)
        return [NodeProposal(
            kind: .replaceBody(newBody: response.content.body),
            reason: response.content.reason
        )]
    }
}
#endif
