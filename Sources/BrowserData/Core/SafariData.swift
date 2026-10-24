//
//  SafariData.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  Safari's saved data, read from its own files and never written. The
//  databases are copied first (see DatabaseSnapshot); the plists are read
//  whole. All of it sits behind Full Disk Access.
//
//  MEASURED on macOS 27.0.1 (Safari 27), from the schemas and key names
//  only:
//  - History.db: `history_items` (one per address, `visit_count`) and
//    `history_visits` (`visit_time` in seconds since 2001, `title`,
//    `redirect_destination` set on a hop that redirected onward,
//    `load_successful`, `origin` 0 or 1).
//  - CloudTabs.db: `cloud_tab_devices` (`device_name`) and `cloud_tabs`
//    (`title`, `url`, `is_pinned`, `last_viewed_time` since 2001).
//  - SafariTabs.db: tab groups are `bookmarks` rows of type 1 under the root
//    (id 0); a window's own unnamed group is a hidden "Local" row. Tabs are
//    type-0 children; `windows_tab_groups` says which group each window
//    shows. Named groups' rows were checked on a fixture, not a real one.
//

import Foundation

/// Safari's history, bookmarks, Reading List, tabs and downloads, read-only.
public struct SafariData: Sendable {

    public let locations: SafariLocations

    public init(locations: SafariLocations = SafariLocations()) {
        self.locations = locations
    }

    /// Visits, newest first. A hop that redirected onward and a page that
    /// failed to load are left out: what is here is where the person landed.
    public func history(since: Date? = nil, until: Date? = nil) throws(BrowserDataError) -> [HistoryVisit] {
        let snapshot = try DatabaseSnapshot(of: locations.history)
        let columns = snapshot.database.columns(of: "history_visits")
        guard columns.contains("VISIT_TIME") else { throw .unreadable(locations.history.path, reason: "no history_visits table") }
        var conditions = ["v.redirect_destination IS NULL", "v.load_successful = 1"]
        var values: [Double] = []
        if let since {
            conditions.append("v.visit_time >= ?")
            values.append(since.timeIntervalSinceReferenceDate)
        }
        if let until {
            conditions.append("v.visit_time < ?")
            values.append(until.timeIntervalSinceReferenceDate)
        }
        var visits: [HistoryVisit] = []
        try snapshot.database.query("""
            SELECT i.url, v.title, v.visit_time, i.visit_count, v.origin
            FROM history_visits v JOIN history_items i ON i.id = v.history_item
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY v.visit_time DESC
            """, values) { row in
            guard let url = row.text(0), let time = row.double(2) else { return }
            visits.append(HistoryVisit(url: url, title: row.text(1), date: Date(timeIntervalSinceReferenceDate: time),
                                       visitCount: row.integer(3) ?? 0, origin: row.integer(4) ?? 0))
        }
        return visits
    }

    /// Every bookmark, in Safari's order, with its folders.
    public func bookmarks() throws(BrowserDataError) -> [Bookmark] {
        BookmarksDecoding.bookmarks(try BookmarksDecoding.root(try read(locations.bookmarks), path: locations.bookmarks.path))
    }

    /// The Reading List, newest first.
    public func readingList() throws(BrowserDataError) -> [ReadingItem] {
        BookmarksDecoding.readingList(try BookmarksDecoding.root(try read(locations.bookmarks), path: locations.bookmarks.path))
            .sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
    }

    /// Tabs open on this account's other devices, device by device, in their order there.
    public func cloudTabs() throws(BrowserDataError) -> [CloudTab] {
        let snapshot = try DatabaseSnapshot(of: locations.cloudTabs)
        var tabs: [(tab: CloudTab, order: Int)] = []
        try snapshot.database.query("""
            SELECT coalesce(d.device_name, ''), t.url, t.title, t.is_pinned, t.last_viewed_time, t.position
            FROM cloud_tabs t LEFT JOIN cloud_tab_devices d ON d.device_uuid = t.device_uuid
            """) { row in
            guard let url = row.text(1) else { return }
            let viewed = row.double(4).flatMap { $0 > 0 ? Date(timeIntervalSinceReferenceDate: $0) : nil }
            tabs.append((CloudTab(device: row.text(0) ?? "", url: url, title: row.text(2), pinned: row.integer(3) == 1, lastViewed: viewed),
                         SessionDecoding.sortValue(row.blob(5)) ?? .max))
        }
        return tabs.sorted { ($0.tab.device, $0.order) < ($1.tab.device, $1.order) }.map(\.tab)
    }

    /// The named tab groups, with their tabs.
    public func tabGroups() throws(BrowserDataError) -> [TabGroup] {
        let snapshot = try DatabaseSnapshot(of: locations.tabGroups)
        let database = snapshot.database
        var groups: [(id: Int, title: String)] = []
        try database.query("""
            SELECT id, title FROM bookmarks
            WHERE type = 1 AND parent = 0 AND coalesce(deleted, 0) = 0 AND coalesce(hidden, 0) = 0 AND coalesce(title, '') != ''
            ORDER BY order_index, id
            """) { row in
            if let id = row.integer(0), let title = row.text(1) { groups.append((id, title)) }
        }
        var open: Set<Int> = []
        if !database.columns(of: "windows_tab_groups").isEmpty {
            try database.query("SELECT tab_group_id FROM windows_tab_groups") { row in
                if let id = row.integer(0) { open.insert(id) }
            }
        }
        var result: [TabGroup] = []
        for group in groups {
            var tabs: [GroupTab] = []
            try database.query("""
                SELECT title, url FROM bookmarks WHERE parent = ? AND type = 0 AND coalesce(deleted, 0) = 0 ORDER BY order_index, id
                """, [Double(group.id)]) { row in
                tabs.append(GroupTab(title: row.text(0), url: row.text(1)))
            }
            result.append(TabGroup(id: group.id, title: group.title, tabs: tabs, open: open.contains(group.id)))
        }
        return result
    }

    /// Tabs closed recently, most recent first; never a private window's.
    public func recentlyClosed() throws(BrowserDataError) -> [ClosedTab] {
        SessionDecoding.closedTabs(try SessionDecoding.plist(try read(locations.recentlyClosed), path: locations.recentlyClosed.path))
    }

    /// The downloads Safari still lists, newest first.
    public func downloads() throws(BrowserDataError) -> [Download] {
        SessionDecoding.downloads(try SessionDecoding.plist(try read(locations.downloads), path: locations.downloads.path))
    }

    /// Whether each file can be read: for a doctor.
    public func access() -> [(name: String, url: URL, state: FileState)] {
        locations.all.map { file in
            let state: FileState = switch PermissionCheck.access(file.url.path) {
            case .readable: .readable
            case .missing: .missing
            case .refused: .refused
            }
            return (file.name, file.url, state)
        }
    }

    private func read(_ url: URL) throws(BrowserDataError) -> Data {
        switch PermissionCheck.access(url.path) {
        case .readable: break
        case .missing: throw .missing(url.path)
        case .refused: throw .needsFullDiskAccess(url.path)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            if PermissionCheck.isRefusal(error) { throw .needsFullDiskAccess(url.path) }
            throw .unreadable(url.path, reason: error.localizedDescription)
        }
    }
}
