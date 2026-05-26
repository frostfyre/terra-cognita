import Foundation

/// Lightweight, no-auth client for Wikipedia's REST summary endpoint.
/// Used by the Capture flow to enrich AI-proposed nodes with a short
/// authoritative summary when an online match exists.
///
/// All requests have a short timeout — if the network is slow or absent
/// we want to fall back to the AI-only extraction quickly, not stall
/// the whole Capture flow.
struct WebEnrichment {
    struct Summary {
        let title: String
        let description: String?     // short subtitle
        let extract: String          // 1-2 paragraph plain-text summary
        let pageURL: URL?
    }

    static let shared = WebEnrichment()

    /// 4 s ceiling per request. The Capture flow runs these in parallel;
    /// the total budget is dominated by the slowest hit.
    private let timeout: TimeInterval = 4.0

    /// Fetch a Wikipedia summary for `label`. Returns `nil` if there's
    /// no match, the device is offline, or the request times out.
    func summary(for label: String) async -> Summary? {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let encoded = cleaned
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encoded,
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Terra Cognita (heritage workbench)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            // Skip disambiguation pages — they aren't useful as enrichment.
            if let typeStr = json["type"] as? String, typeStr == "disambiguation" {
                return nil
            }
            let title = json["title"] as? String ?? cleaned
            let extract = (json["extract"] as? String) ?? ""
            guard !extract.isEmpty else { return nil }
            let description = json["description"] as? String
            let pageURLString = ((json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
            let pageURL = pageURLString.flatMap(URL.init(string:))
            return Summary(title: title,
                           description: description,
                           extract: extract,
                           pageURL: pageURL)
        } catch {
            return nil
        }
    }

    /// Fan-out enrichment across a batch of labels. Returns a dictionary
    /// keyed by the original label so callers can correlate back.
    func summaries(for labels: [String]) async -> [String: Summary] {
        await withTaskGroup(of: (String, Summary?).self) { group in
            for label in labels {
                group.addTask { (label, await self.summary(for: label)) }
            }
            var out: [String: Summary] = [:]
            for await (label, summary) in group {
                if let summary { out[label] = summary }
            }
            return out
        }
    }

    /// Best-effort network reachability check. Used to decide whether
    /// to show the "enriching from web…" indicator. We don't gate the
    /// flow on this — the actual fetch handles offline gracefully.
    func isNetworkLikelyAvailable() async -> Bool {
        var request = URLRequest(url: URL(string: "https://en.wikipedia.org/api/rest_v1/")!,
                                 timeoutInterval: 1.5)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }
}
