// Deprecated duplicate of GEXFParser. See canonical implementation in GEXFParser.swift
#if false
import Foundation
import XMLCoder

class GEXFParser {
    let fileURL: URL
    private(set) var graph = HeritageGraph()
    init(fileURL: URL) { self.fileURL = fileURL }
    func parse() throws { /* old implementation */ }
}

// Codable structs would have been here as well.
#endif

