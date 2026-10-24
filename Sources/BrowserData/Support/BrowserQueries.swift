//
//  BrowserQueries.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  Searching and counting what was read. Pure.
//

import Foundation

/// Searching and counting.
public enum BrowserQueries {

    /// One site's visits.
    public struct SiteSummary: Codable, Sendable, Hashable {
        public var site: String
        public var visits: Int
        /// Distinct addresses visited on it.
        public var pages: Int
        public var lastVisit: Date
    }

    /// Visits per site, most visited first (the latest visit breaks ties).
    public static func sites(_ visits: [HistoryVisit]) -> [SiteSummary] {
        Dictionary(grouping: visits) { URLPrivacy.host(of: $0.url) ?? "" }
            .compactMap { site, group -> SiteSummary? in
                guard !site.isEmpty else { return nil }
                return SiteSummary(site: site, visits: group.count, pages: Set(group.map(\.url)).count,
                                   lastVisit: group.map(\.date).max() ?? .distantPast)
            }
            .sorted { ($0.visits, $0.lastVisit) > ($1.visits, $1.lastVisit) }
    }

    /// Whether every word of `query` starts a word somewhere in `fields`
    /// (ignoring case and accents). `rust guide` finds "A Guide to Rust".
    public static func matches(_ query: String, _ fields: [String?]) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let text = fold(fields.compactMap { $0 }.joined(separator: " "))
        return words.allSatisfy { startsAWord($0, in: text) }
    }

    /// Whether `needle` starts a word in `text` (both folded).
    static func startsAWord(_ needle: String, in text: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: range) {
            if found.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber) { return true }
            range = found.upperBound..<text.endIndex
        }
        return false
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
