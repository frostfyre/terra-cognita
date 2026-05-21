import Foundation

/// A parser responsible for reading a GEXF file and creating a `HeritageGraph`.
/// Uses Foundation's `XMLParser` to avoid external dependencies.
final class GEXFParser: NSObject, XMLParserDelegate {

    /// The URL of the GEXF file to parse.
    let fileURL: URL

    /// The graph that will be populated from the GEXF file.
    private(set) var graph = HeritageGraph()

    // MARK: - Parsing state

    /// Attribute id -> title (declared in <attributes><attribute id="..." title="..."/></attributes>)
    private var attributeTitles: [String: String] = [:]

    /// Per-node attribute values, accumulated between <node> and </node>.
    private var pendingAttributes: [String: String] = [:]

    /// Working node fields.
    private var pendingNodeID: String?
    private var pendingNodeLabel: String?

    /// Parse error captured from the delegate.
    private var parseError: Error?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    /// Parses the GEXF file and populates the `graph` property.
    func parse() throws {
        graph = HeritageGraph()
        attributeTitles.removeAll()
        pendingAttributes.removeAll()
        pendingNodeID = nil
        pendingNodeLabel = nil
        parseError = nil

        let data = try Data(contentsOf: fileURL)
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? parseError ?? NSError(
                domain: "GEXFParser",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown parse failure"]
            )
        }
        if let parseError { throw parseError }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "attribute":
            if let id = attributeDict["id"], let title = attributeDict["title"] {
                attributeTitles[id] = title
            }
        case "node":
            pendingNodeID = attributeDict["id"]
            pendingNodeLabel = attributeDict["label"] ?? attributeDict["id"]
            pendingAttributes.removeAll()
        case "attvalue":
            if let forKey = attributeDict["for"], let value = attributeDict["value"] {
                let title = attributeTitles[forKey] ?? forKey
                pendingAttributes[title] = value
            }
        case "edge":
            guard let source = attributeDict["source"],
                  let target = attributeDict["target"] else { return }
            let id = attributeDict["id"] ?? "\(source)->\(target)"
            var edge = Edge(id: id, sourceID: source, targetID: target)
            edge.relationshipType = attributeDict["label"] ?? attributeDict["kind"]
            if let weight = attributeDict["weight"] {
                edge.confidence = Double(weight)
            }
            graph.addEdge(edge)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "node" {
            guard let id = pendingNodeID else { return }
            let label = pendingNodeLabel ?? id
            var node = Node(id: id, label: label)
            node.attributes = pendingAttributes
            node.filePath = pendingAttributes["file"]
            graph.addNode(node)

            pendingNodeID = nil
            pendingNodeLabel = nil
            pendingAttributes.removeAll()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}
