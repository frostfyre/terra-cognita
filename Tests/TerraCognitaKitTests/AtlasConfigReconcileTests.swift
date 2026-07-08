import Testing
import SwiftUI
@testable import TerraCognitaKit

/// `reconcilingTypes` is what keeps Atlas Settings + the lens picker
/// in sync with the network actually loaded. Before it, a config-less
/// atlas (e.g. a GEXF import) fell back to the `.default` sample
/// ontology and showed person/concept/… lenses that had nothing to do
/// with the loaded nodes.
@Suite("AtlasConfig type reconciliation")
struct AtlasConfigReconcileTests {

    @Test("no config file → types derived from the network, defaults dropped")
    func derivesFromNetwork() {
        let cfg = AtlasConfig.default.reconcilingTypes(
            presentInNodeTypes: ["gene", "protein"],
            hadExplicitConfig: false)
        #expect(cfg.types.map(\.name).sorted() == ["gene", "protein"])
        // None of the .default sample user-types leak through.
        #expect(!cfg.types.contains { $0.name == "person" })
    }

    @Test("synthetic types (tag/embed/placeholder) appear only when present")
    func syntheticOnlyWhenPresent() {
        let withTag = AtlasConfig.default.reconcilingTypes(
            presentInNodeTypes: ["gene", "tag"],
            hadExplicitConfig: false)
        #expect(withTag.types.contains { $0.name == "tag" })

        let without = AtlasConfig.default.reconcilingTypes(
            presentInNodeTypes: ["gene"],
            hadExplicitConfig: false)
        #expect(!without.types.contains { $0.name == "tag" })
    }

    @Test("authored config keeps declared types and appends undeclared ones")
    func additiveWhenExplicit() {
        let authored = AtlasConfig(
            types: [.init(name: "person", color: .cyan, icon: "person.fill", folder: nil)],
            eras: [],
            extractors: AtlasConfig.Extractors())
        let cfg = authored.reconcilingTypes(
            presentInNodeTypes: ["person", "gene"],
            hadExplicitConfig: true)
        #expect(cfg.types.contains { $0.name == "person" })  // declared, kept
        #expect(cfg.types.contains { $0.name == "gene" })    // undeclared, appended
    }
}
