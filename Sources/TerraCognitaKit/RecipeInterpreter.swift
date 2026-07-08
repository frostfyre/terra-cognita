import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Natural-language → `ImportRecipe` via on-device FoundationModels.
/// Pure type-erased entry point so non-FoundationModels builds (older
/// OS or platforms without the framework) still compile and can
/// surface "AI unavailable" to the user.
enum RecipeInterpreter {

    enum InterpreterError: LocalizedError {
        case unavailable
        case parseFailed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "AI is not available. Update to macOS 26 / iOS 26."
            case .parseFailed(let why):
                return "Couldn't parse the recipe — \(why)"
            }
        }
    }

    /// Whether the on-device model is ready right now. Used by the
    /// UI to gate the "Interpret" button.
    static var isAvailable: Bool {
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

    /// Parse the user's natural-language instructions into a typed
    /// recipe. Throws `InterpreterError.unavailable` if the model
    /// isn't available; throws `.parseFailed` if the response can't
    /// be coerced into `ImportRecipe`.
    static func interpret(_ instructions: String) async throws -> ImportRecipe {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            return try await interpretWithFoundationModels(instructions)
        }
        #endif
        throw InterpreterError.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
extension RecipeInterpreter {

    @Generable
    struct GenRecipe {
        @Guide(description: "One-sentence summary of what this recipe does")
        let summary: String
        @Guide(description: "Node-type rules — at least one. Each rule defines an atlas subfolder + the file pattern that materializes into nodes of that type.", .count(1...8))
        let nodeRules: [GenNodeRule]
        @Guide(description: "Edge rules — strategies for linking the materialized nodes. May be empty.", .count(0...8))
        let edgeRules: [GenEdgeRule]
    }

    @Generable
    struct GenNodeRule {
        @Guide(description: "Lowercase type name (e.g. 'texture', 'asset', 'class'). Becomes the front-matter `type:` AND the atlas subfolder.")
        let typeName: String
        @Guide(description: "SwiftUI color name (red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray) OR a hex like '#FF8000'.")
        let color: String
        @Guide(description: "File pattern like '*.png' or '*.swift'.")
        let filePattern: String
        @Guide(description: "Label derivation: 'basename' strips the extension (foo.png → foo); 'fullName' keeps it.")
        let labelStrategy: String
    }

    @Generable
    struct GenEdgeRule {
        @Guide(description: "Source node type (must be one of the typeNames declared in nodeRules).")
        let sourceType: String
        @Guide(description: "Target node type (must be one of the typeNames declared in nodeRules).")
        let targetType: String
        @Guide(description: "Edge strategy: 'nameReference' (target's label appears in source's file contents), 'sameDirectory' (both files live in the same directory), 'sharedPrefix' (basenames share a prefix of ≥3 characters).")
        let strategy: String
    }

    static func interpretWithFoundationModels(_ instructions: String) async throws -> ImportRecipe {
        let session = LanguageModelSession(instructions: """
        You convert natural-language import instructions into a
        structured ImportRecipe. The recipe will be executed
        deterministically against a folder the user picks — your
        job is to capture the user's intent as typed rules, NOT to
        try to imagine what the folder contains. Stick to what the
        user explicitly says.

        For each distinct kind of file the user mentions, produce
        one nodeRule. For each "link X to Y" the user mentions,
        produce one edgeRule. If the user gives no edge linking
        instructions, return an empty edgeRules array.
        """)
        let response = try await session.respond(
            to: instructions,
            generating: GenRecipe.self
        )
        return Self.translate(response.content)
    }

    /// Coerce the AI's loose strings into our typed enums, falling
    /// back to sensible defaults on unknown values rather than
    /// failing — the interpreter prioritizes "ship something" over
    /// "ship perfectly".
    private static func translate(_ gen: GenRecipe) -> ImportRecipe {
        let nodeRules: [ImportRecipe.NodeRule] = gen.nodeRules.map { g in
            let strategy = ImportRecipe.LabelStrategy(
                rawValue: g.labelStrategy.lowercased()
            ) ?? .basename
            return ImportRecipe.NodeRule(
                typeName: g.typeName.lowercased(),
                color: g.color,
                filePattern: g.filePattern,
                labelStrategy: strategy
            )
        }
        let validTypes = Set(nodeRules.map { $0.typeName })
        let edgeRules: [ImportRecipe.EdgeRule] = gen.edgeRules.compactMap { g in
            let src = g.sourceType.lowercased()
            let tgt = g.targetType.lowercased()
            guard validTypes.contains(src), validTypes.contains(tgt) else {
                return nil
            }
            let strategy = ImportRecipe.EdgeStrategy(
                rawValue: g.strategy
            ) ?? .nameReference
            return ImportRecipe.EdgeRule(
                sourceType: src,
                targetType: tgt,
                strategy: strategy
            )
        }
        return ImportRecipe(
            summary: gen.summary,
            nodeRules: nodeRules,
            edgeRules: edgeRules
        )
    }
}
#endif
