//
//  URLPrivacy.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  Addresses carry more than the page: search words, account numbers,
//  session tokens and sign-in links ride in the query string and fragment.
//  `trimmed` keeps the page and drops the rest — every parameter except the
//  few that ARE the page on sites where nothing else says which page it is
//  (a YouTube video's `v`) — and drops any user:password@. `trimmedTitle`
//  masks what was dropped where the page's title repeats it.
//
//  `SiteList` is the never-show list: a site and every subdomain of it.
//

import Foundation

/// Trimming addresses. Pure.
public enum URLPrivacy {

    /// The query parameters kept on a site's paths: they name the page itself.
    public static let pageParameters: [String: [String: Set<String>]] = [
        "youtube.com": ["/watch": ["v"], "/playlist": ["list"]],
        "news.ycombinator.com": ["/item": ["id"]],
    ]

    /// `url` without its query string (bar the page-naming parameters),
    /// fragment, or user and password.
    public static func trimmed(_ url: String) -> String {
        guard var parts = URLComponents(string: url), parts.scheme != nil else {
            let cut = url.firstIndex { $0 == "?" || $0 == "#" } ?? url.endIndex
            return String(url[..<cut])
        }
        parts.user = nil
        parts.password = nil
        parts.fragment = nil
        let kept = host(of: url).flatMap { pageParameters[$0]?[parts.path] } ?? []
        let items = (parts.queryItems ?? []).filter { kept.contains($0.name) }
        parts.queryItems = items.isEmpty ? nil : items
        return parts.string ?? url
    }

    /// `title` with any value `trimmed` would drop from `url` masked as `…`:
    /// a search page's title repeats the words its address carried
    /// ("private words - Search"). Values under three characters are left.
    public static func trimmedTitle(_ title: String?, for url: String) -> String? {
        guard var title, let parts = URLComponents(string: url) else { return title }
        let kept = host(of: url).flatMap { pageParameters[$0]?[parts.path] } ?? []
        let dropped = (parts.queryItems ?? []).filter { !kept.contains($0.name) }.compactMap(\.value)
            + (parts.fragment.map { [$0] } ?? [])
        for value in dropped.map({ $0.replacingOccurrences(of: "+", with: " ") }).sorted(by: { $0.count > $1.count }) where value.count >= 3 {
            title = title.replacingOccurrences(of: value, with: "…", options: [.caseInsensitive, .diacriticInsensitive])
        }
        return title
    }

    /// The site: the host, lower-cased, without `www.` or `m.`; `nil` for
    /// addresses with no host (`about:blank`, `file:`).
    public static func host(of url: String) -> String? {
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) && host.count > prefix.count {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }
}

/// Sites never shown — a bank, a health portal — each with its subdomains.
public struct SiteList: Sendable, Hashable {

    /// Normalised: `bank.example`, no scheme, path or `www.`.
    public let sites: [String]

    /// Entries as people type them: `bank.example`, `https://www.bank.example/login`.
    public init(_ entries: [String]) {
        sites = entries.compactMap(SiteList.normalise)
    }

    public var isEmpty: Bool { sites.isEmpty }

    /// Whether `url` is on a listed site or a subdomain of one.
    public func contains(url: String?) -> Bool {
        guard !sites.isEmpty, let url, let host = URLPrivacy.host(of: url) else { return false }
        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func normalise(_ entry: String) -> String? {
        let typed = entry.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty else { return nil }
        let withScheme = typed.contains("://") ? typed : "https://" + typed
        return URLPrivacy.host(of: withScheme) ?? typed
    }
}
