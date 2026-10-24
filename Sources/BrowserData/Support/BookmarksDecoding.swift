//
//  BookmarksDecoding.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  Bookmarks.plist, read. MEASURED on macOS 27.0.1 (Safari 27): a tree of
//  dictionaries, `WebBookmarkType` List (a folder, `Title` + `Children`),
//  Leaf (a page, `URLString` + `URIDictionary.title`) or Proxy (the History
//  entry, skipped). The root's own folders are `BookmarksBar` (shown as
//  Favorites), `BookmarksMenu` and `com.apple.ReadingList`, whose leaves add
//  `ReadingList.{DateAdded, PreviewText}`. `ShouldOmitFromUI` marks entries
//  Safari itself never shows.
//

import Foundation

/// Reading Bookmarks.plist. Pure.
enum BookmarksDecoding {

    static let readingListTitle = "com.apple.ReadingList"

    /// The names Safari shows for its own root folders.
    static let folderNames = ["BookmarksBar": "Favorites", "BookmarksMenu": "Bookmarks Menu"]

    static func root(_ data: Data, path: String) throws(BrowserDataError) -> [String: Any] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil), let root = plist as? [String: Any] else {
            throw .unreadable(path, reason: "not a property-list dictionary")
        }
        return root
    }

    /// Every bookmark, in Safari's order, Reading List left out.
    static func bookmarks(_ root: [String: Any]) -> [Bookmark] {
        var found: [Bookmark] = []
        func walk(_ node: [String: Any], folder: [String]) {
            guard node["ShouldOmitFromUI"] as? Bool != true else { return }
            switch node["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                guard let url = node["URLString"] as? String else { return }
                found.append(Bookmark(url: url, title: title(of: node), folder: folder))
            case "WebBookmarkTypeList":
                let name = node["Title"] as? String ?? ""
                guard name != readingListTitle else { return }
                let path = name.isEmpty ? folder : folder + [folderNames[name] ?? name]
                for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, folder: path) }
            default:
                return
            }
        }
        for child in root["Children"] as? [[String: Any]] ?? [] { walk(child, folder: []) }
        return found
    }

    /// The Reading List, in Safari's order.
    static func readingList(_ root: [String: Any]) -> [ReadingItem] {
        let children = root["Children"] as? [[String: Any]] ?? []
        guard let list = children.first(where: { $0["Title"] as? String == readingListTitle }) else { return [] }
        return (list["Children"] as? [[String: Any]] ?? []).compactMap { item in
            guard let url = item["URLString"] as? String else { return nil }
            let reading = item["ReadingList"] as? [String: Any]
            return ReadingItem(url: url, title: title(of: item), preview: reading?["PreviewText"] as? String,
                               added: reading?["DateAdded"] as? Date)
        }
    }

    private static func title(of node: [String: Any]) -> String? {
        ((node["URIDictionary"] as? [String: Any])?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
