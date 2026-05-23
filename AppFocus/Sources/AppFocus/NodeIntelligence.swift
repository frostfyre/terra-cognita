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

    /// True only when the on-device model is ready to take a request.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
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
        if #available(macOS 26, *) {
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
        boundNodeID = node.id
        boundContextPrompt = Self.contextPrompt(for: node)
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            session = LanguageModelSession(instructions: Self.instructions)
        } else {
            session = nil
        }
        #else
        session = nil
        #endif
        activity = .idle
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
        if #available(macOS 26, *) {
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
