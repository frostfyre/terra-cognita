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
    ///
    /// Two-stage lookup: try the direct title endpoint first (cheap when
    /// the label happens to be Wikipedia's exact title). If that comes
    /// back empty or as a disambiguation, fall back to `opensearch`
    /// to fuzzy-match — "Frank Reilly method" → "Frank J. Reilly",
    /// "Doctor Who fourth doctor" → "Fourth Doctor", etc. The fuzzy
    /// step is what makes the user-friction reduction real: vault labels
    /// don't have to match Wikipedia's article titles letter-for-letter.
    func summary(for label: String) async -> Summary? {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Stage 1: direct title hit.
        if let direct = await fetchSummary(title: cleaned) {
            return direct
        }

        // Stage 2: fuzzy via opensearch.
        if let resolved = await searchCanonicalTitle(query: cleaned),
           resolved.lowercased() != cleaned.lowercased() {
            return await fetchSummary(title: resolved)
        }
        return nil
    }

    /// Hit the REST summary endpoint for an exact title. Returns `nil`
    /// on disambiguation, miss, or transport failure — callers fall
    /// back to fuzzy resolution.
    private func fetchSummary(title: String) async -> Summary? {
        let encoded = title
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
            if let typeStr = json["type"] as? String, typeStr == "disambiguation" {
                return nil
            }
            let title = json["title"] as? String ?? title
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

    /// OpenSearch-based fuzzy disambiguation. Returns the top matching
    /// canonical title for `query`, or `nil` if there's no plausible
    /// match. The endpoint is free, key-less, and well-suited to
    /// heritage-graph labels (people / places / works) where the user's
    /// shorthand rarely matches the Wikipedia article title exactly.
    private func searchCanonicalTitle(query: String) async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Terra Cognita (heritage workbench)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            // opensearch returns: [query, [titles], [descriptions], [urls]]
            guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
                  array.count >= 2,
                  let titles = array[1] as? [String],
                  let first = titles.first,
                  !first.isEmpty else {
                return nil
            }
            return first
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

    /// Fetch a URL and return a plain-text rendering suitable for
    /// feeding into the AI capture pipeline. Wikipedia article URLs are
    /// short-circuited through the REST extract endpoint (clean and
    /// fast); other URLs fall back to an HTML download + naive tag
    /// strip. The result is "good enough for the on-device model" —
    /// no Readability heuristics, no cleanup beyond whitespace.
    /// Returns `nil` on transport failure or timeout.
    func fetchText(from url: URL) async -> String? {
        // Wikipedia fast path — use REST summary instead of scraping.
        if let host = url.host?.lowercased(),
           host.hasSuffix("wikipedia.org"),
           let title = wikipediaTitle(from: url),
           let summary = await fetchSummary(title: title) {
            return [
                summary.title,
                summary.description ?? "",
                summary.extract,
            ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout * 2)
        request.setValue("Terra Cognita (heritage workbench)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let html = String(decoding: data, as: UTF8.self)
            return stripHTMLTags(html)
        } catch {
            return nil
        }
    }

    /// Extract the article title from a Wikipedia URL of the form
    /// `https://en.wikipedia.org/wiki/Frank_J._Reilly`. Returns `nil`
    /// for non-article paths (talk pages, special pages, edit views).
    private func wikipediaTitle(from url: URL) -> String? {
        let components = url.pathComponents
        guard let wikiIdx = components.firstIndex(of: "wiki"),
              wikiIdx + 1 < components.count else { return nil }
        let raw = components[wikiIdx + 1]
        return raw
            .removingPercentEncoding?
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Strip HTML tags + collapse whitespace. Not a Readability-style
    /// content extractor — just enough to hand the on-device LLM
    /// something more useful than raw tag soup. The model is tolerant
    /// of noise; what matters is that script/style blocks are gone so
    /// we don't blow the context window on CSS.
    private func stripHTMLTags(_ html: String) -> String {
        var s = html
        // Drop script + style blocks wholesale.
        for tag in ["script", "style", "noscript"] {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            s = s.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Strip remaining tags.
        s = s.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        // Decode a handful of common HTML entities — full entity
        // decoding would need a parser, but these cover the vast
        // majority of visible glyphs in article bodies.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ]
        for (e, replacement) in entities {
            s = s.replacingOccurrences(of: e, with: replacement)
        }
        // Collapse runs of whitespace.
        s = s.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
