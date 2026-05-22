import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM integration for the graph workbench.
///
/// All Foundation Models calls are gated behind `#if canImport(FoundationModels)`
/// (compile time) and `@available(macOS 26, *)` (runtime) so the app
/// continues to build and run on macOS 14/15 — the AI section simply
/// shows an "unavailable" message there.
///
/// Per DESIGN.md: "Apple Intelligence should support node summarization,
/// relationship explanation, semantic search". This module exposes the
/// first two; semantic search hangs off the same plumbing later.
@MainActor
final class NodeIntelligence: ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        case finished(String)
        case failed(String)
        case unavailable(String)
    }

    @Published var status: Status = .idle

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

    /// A human-friendly explanation of why the model isn't available.
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

    /// Generate a short summary of a single node.
    func summarize(node: Node) {
        let prompt = Self.summaryPrompt(for: node)
        run(instructions: Self.summaryInstructions, prompt: prompt)
    }

    /// Explain how the selected node relates to a neighbor in plain prose.
    func explainRelationship(from: Node, to: Node, relationshipType: String?) {
        let prompt = """
        Explain in two or three sentences how "\(from.label)" connects to "\(to.label)" \
        in this person's heritage map\(relationshipType.map { " (relationship type: \($0))" } ?? ""). \
        Use only the information in the notes below.

        --- "\(from.label)" ---
        \(Self.trimmedBody(from.markdownContent ?? ""))

        --- "\(to.label)" ---
        \(Self.trimmedBody(to.markdownContent ?? ""))
        """
        run(instructions: Self.relationshipInstructions, prompt: prompt)
    }

    /// Cancel any in-flight call and reset to idle.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        status = .idle
    }

    // MARK: - Internals

    private var currentTask: Task<Void, Never>?

    private func run(instructions: String, prompt: String) {
        cancel()
        guard isAvailable else {
            status = .unavailable(availabilityNote ?? "Unavailable.")
            return
        }
        status = .running
        currentTask = Task { [weak self] in
            await self?.perform(instructions: instructions, prompt: prompt)
        }
    }

    private func perform(instructions: String, prompt: String) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                if Task.isCancelled { return }
                status = .finished(response.content)
            } catch {
                if Task.isCancelled { return }
                status = .failed(error.localizedDescription)
            }
            return
        }
        #endif
        status = .unavailable(availabilityNote ?? "Unavailable.")
    }

    // MARK: - Prompt scaffolding

    private static let summaryInstructions = """
    You are a careful reader who summarizes a single note about a person, \
    institution, work, event, or concept. Produce one short paragraph \
    (three to four sentences) that captures the essence of the note and \
    its role in this heritage map. Use only information present in the \
    note itself — do not invent facts, names, or dates.
    """

    private static let relationshipInstructions = """
    You explain how two entities in a personal heritage map relate to each \
    other, using only the text in the two notes provided. Keep it concise \
    (two to three sentences). If the notes don't make the connection clear, \
    say so plainly rather than guessing.
    """

    private static func summaryPrompt(for node: Node) -> String {
        let kind = node.attributes["type"] ?? node.attributes["folder"] ?? "entry"
        return """
        Summarize the following \(kind) note:

        Title: \(node.label)

        \(trimmedBody(node.markdownContent ?? ""))
        """
    }

    /// Foundation Models has a context window. Trim very long notes so we
    /// don't blow past it (the vault has a few long ones).
    private static func trimmedBody(_ raw: String) -> String {
        // Drop front-matter and the leading `# heading`.
        var body = raw
        if body.hasPrefix("---") {
            if let end = body.range(of: "\n---",
                                    options: [],
                                    range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[body.index(end.upperBound, offsetBy: 0)...])
            }
        }
        // Cap at ~3500 characters — well under typical context for one note.
        if body.count > 3500 {
            body = String(body.prefix(3500)) + "\n…"
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
