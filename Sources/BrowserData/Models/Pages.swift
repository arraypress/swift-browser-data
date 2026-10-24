//
//  Pages.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  The shapes Safari's files hold. Every `url` is as Safari stored it —
//  query strings and all; `URLPrivacy` is how a caller trims them.
//

import Foundation

/// One visit to a page.
public struct HistoryVisit: Codable, Sendable, Hashable {
    public var url: String
    /// The page's title at that visit.
    public var title: String?
    public var date: Date
    /// How many times the page has been visited, all told.
    public var visitCount: Int
    /// Safari's `origin` flag: 0 and 1 are seen (most likely this Mac and
    /// another device through iCloud — not yet measured, so kept raw).
    public var origin: Int

    public init(url: String, title: String?, date: Date, visitCount: Int, origin: Int) {
        self.url = url
        self.title = title
        self.date = date
        self.visitCount = visitCount
        self.origin = origin
    }
}

/// One bookmark, with the folders it sits in.
public struct Bookmark: Codable, Sendable, Hashable {
    public var url: String
    public var title: String?
    /// Outermost first: `["Favourites", "Work"]`.
    public var folder: [String]

    public init(url: String, title: String?, folder: [String]) {
        self.url = url
        self.title = title
        self.folder = folder
    }
}

/// One Reading List item.
public struct ReadingItem: Codable, Sendable, Hashable {
    public var url: String
    public var title: String?
    public var preview: String?
    public var added: Date?

    public init(url: String, title: String?, preview: String?, added: Date?) {
        self.url = url
        self.title = title
        self.preview = preview
        self.added = added
    }
}

/// A tab open on another device, as iCloud shares it.
public struct CloudTab: Codable, Sendable, Hashable {
    public var device: String
    public var url: String
    public var title: String?
    public var pinned: Bool
    public var lastViewed: Date?

    public init(device: String, url: String, title: String?, pinned: Bool, lastViewed: Date?) {
        self.device = device
        self.url = url
        self.title = title
        self.pinned = pinned
        self.lastViewed = lastViewed
    }
}

/// One named tab group.
public struct TabGroup: Codable, Sendable, Hashable {
    public var id: Int
    public var title: String
    public var tabs: [GroupTab]
    /// Whether a Safari window shows it now.
    public var open: Bool

    public init(id: Int, title: String, tabs: [GroupTab], open: Bool) {
        self.id = id
        self.title = title
        self.tabs = tabs
        self.open = open
    }
}

/// A tab in a tab group.
public struct GroupTab: Codable, Sendable, Hashable {
    public var title: String?
    public var url: String?

    public init(title: String?, url: String?) {
        self.title = title
        self.url = url
    }
}

/// A tab closed recently, as Safari keeps it for reopening.
public struct ClosedTab: Codable, Sendable, Hashable {
    public var url: String
    public var title: String?
    public var closed: Date?
    public var lastVisit: Date?

    public init(url: String, title: String?, closed: Date?, lastVisit: Date?) {
        self.url = url
        self.title = title
        self.closed = closed
        self.lastVisit = lastVisit
    }
}

/// One download Safari still lists.
public struct Download: Codable, Sendable, Hashable {
    public var url: String
    /// Where the file was saved.
    public var path: String?
    public var bytes: Int?
    public var totalBytes: Int?
    public var added: Date?
    public var finished: Date?

    public init(url: String, path: String?, bytes: Int?, totalBytes: Int?, added: Date?, finished: Date?) {
        self.url = url
        self.path = path
        self.bytes = bytes
        self.totalBytes = totalBytes
        self.added = added
        self.finished = finished
    }
}

/// A tab open in Safari now.
public struct OpenTab: Codable, Sendable, Hashable {
    /// 1 is the frontmost window.
    public var window: Int
    public var index: Int
    public var url: String?
    public var title: String?
    /// Whether it is the tab its window shows.
    public var current: Bool

    public init(window: Int, index: Int, url: String?, title: String?, current: Bool) {
        self.window = window
        self.index = index
        self.url = url
        self.title = title
        self.current = current
    }
}

/// A page's visible text, as Safari renders it.
public struct PageText: Codable, Sendable, Hashable {
    public var url: String?
    public var title: String?
    public var text: String

    public init(url: String?, title: String?, text: String) {
        self.url = url
        self.title = title
        self.text = text
    }
}
