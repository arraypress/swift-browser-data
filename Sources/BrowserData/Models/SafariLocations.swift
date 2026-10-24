//
//  SafariLocations.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where Safari keeps each file — MEASURED on macOS 27.0.1 (Safari 27):
/// history, bookmarks, closed tabs and downloads in `~/Library/Safari`, the
/// tab databases in Safari's container.
public struct SafariLocations: Sendable, Hashable {

    public var history: URL
    public var bookmarks: URL
    public var recentlyClosed: URL
    public var downloads: URL
    public var cloudTabs: URL
    public var tabGroups: URL

    public init(history: URL, bookmarks: URL, recentlyClosed: URL, downloads: URL, cloudTabs: URL, tabGroups: URL) {
        self.history = history
        self.bookmarks = bookmarks
        self.recentlyClosed = recentlyClosed
        self.downloads = downloads
        self.cloudTabs = cloudTabs
        self.tabGroups = tabGroups
    }

    /// Safari's files under `home`.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let library = home.appendingPathComponent("Library/Safari")
        let container = home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari")
        self.init(history: library.appendingPathComponent("History.db"),
                  bookmarks: library.appendingPathComponent("Bookmarks.plist"),
                  recentlyClosed: library.appendingPathComponent("RecentlyClosedTabs.plist"),
                  downloads: library.appendingPathComponent("Downloads.plist"),
                  cloudTabs: container.appendingPathComponent("CloudTabs.db"),
                  tabGroups: container.appendingPathComponent("SafariTabs.db"))
    }

    /// Every file, named, for a doctor.
    public var all: [(name: String, url: URL)] {
        [("history", history), ("bookmarks", bookmarks), ("recently closed", recentlyClosed),
         ("downloads", downloads), ("iCloud tabs", cloudTabs), ("tab groups", tabGroups)]
    }
}
