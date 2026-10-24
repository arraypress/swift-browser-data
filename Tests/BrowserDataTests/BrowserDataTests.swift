//
//  BrowserDataTests.swift
//  BrowserDataTests
//
//  Created by David Sherlock on 2026.
//
//  A fixture home with Safari's files in their real shapes (the measured
//  schemas and keys); every address, title and device invented.
//

import Foundation
import SQLite3
import Testing
@testable import BrowserData

struct Fixture {

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("browser-data-\(UUID().uuidString.prefix(8))")
    var locations: SafariLocations { SafariLocations(home: root) }
    var safari: SafariData { SafariData(locations: locations) }

    init() throws {
        for folder in [locations.history, locations.cloudTabs].map({ $0.deletingLastPathComponent() }) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func remove() {
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.history.deletingLastPathComponent().path)
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs statements against a new database at `url`, with each blob bound to its `?`s in order.
    func database(_ url: URL, _ statements: [String], blobs: [Data] = []) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        var remaining = blobs[...]
        for sql in statements {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: sql]) }
            for index in 0..<sqlite3_bind_parameter_count(statement) {
                let blob = remaining.popFirst() ?? Data()
                _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, index + 1, $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: sql]) }
            sqlite3_finalize(statement)
        }
    }

    func plist(_ value: Any, to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
    }

    /// History: a landed page, a redirect hop onto it, a failed load, and an older visit.
    func writeHistory(now: Double) throws {
        try database(locations.history, [
            "CREATE TABLE history_items (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, domain_expansion TEXT NULL, visit_count INTEGER NOT NULL, daily_visit_counts BLOB NOT NULL DEFAULT x'', weekly_visit_counts BLOB NULL, autocomplete_triggers BLOB NULL, should_recompute_derived_visit_counts INTEGER NOT NULL DEFAULT 0, visit_count_score INTEGER NOT NULL DEFAULT 0, status_code INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE history_visits (id INTEGER PRIMARY KEY AUTOINCREMENT, history_item INTEGER NOT NULL, visit_time REAL NOT NULL, title TEXT NULL, load_successful BOOLEAN NOT NULL DEFAULT 1, http_non_get BOOLEAN NOT NULL DEFAULT 0, synthesized BOOLEAN NOT NULL DEFAULT 0, redirect_source INTEGER NULL UNIQUE, redirect_destination INTEGER NULL UNIQUE, origin INTEGER NOT NULL DEFAULT 0, generation INTEGER NOT NULL DEFAULT 0, attributes INTEGER NOT NULL DEFAULT 0, score INTEGER NOT NULL DEFAULT 0)",
            "INSERT INTO history_items (id, url, visit_count) VALUES (1, 'https://www.example.org/guide?ref=mail#part-2', 3), (2, 'http://example.org/', 1), (3, 'https://down.example.net/', 1), (4, 'https://old.example.com/page', 7)",
            "INSERT INTO history_visits (id, history_item, visit_time, title, redirect_destination) VALUES (2, 2, \(now - 61), NULL, 1)",
            "INSERT INTO history_visits (id, history_item, visit_time, title, redirect_source, origin) VALUES (1, 1, \(now - 60), 'A Guide to Rust', 2, 1)",
            "INSERT INTO history_visits (history_item, visit_time, title, load_successful) VALUES (3, \(now - 30), 'Failed', 0)",
            "INSERT INTO history_visits (history_item, visit_time, title) VALUES (4, \(now - 10 * 86_400), 'Old Page')",
        ])
    }

    func writeBookmarks() throws {
        func leaf(_ url: String, _ title: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": url, "URIDictionary": ["title": title]].merging(extra) { $1 }
        }
        func list(_ title: String, _ children: [[String: Any]]) -> [String: Any] {
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": title, "Children": children]
        }
        try plist(["WebBookmarkType": "WebBookmarkTypeList", "Title": "", "WebBookmarkFileVersion": 1, "Children": [
            ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
            list("BookmarksBar", [leaf("https://news.example.com/", "News"), list("Work", [leaf("https://docs.example.com/a", "Docs")])]),
            list("BookmarksMenu", [leaf("https://menu.example.com/", "Menu Page"), leaf("https://hidden.example.com/", "Hidden", ["ShouldOmitFromUI": true])]),
            list("com.apple.ReadingList", [
                leaf("https://read.example.com/old", "Older", ["ReadingList": ["DateAdded": Date(timeIntervalSince1970: 1_700_000_000), "PreviewText": "First words"]]),
                leaf("https://read.example.com/new", "Newer", ["ReadingList": ["DateAdded": Date(timeIntervalSince1970: 1_750_000_000)]]),
            ]),
        ]], to: locations.bookmarks)
    }

    /// zlib framing as Safari writes it: a two-byte header, then deflate.
    static func position(_ value: Int) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: ["sortValues": [["sortValue": value, "changeID": 1, "deviceIdentifier": "D"]]])
        return Data([0x78, 0xDA]) + (try (json as NSData).compressed(using: .zlib) as Data)
    }

    func writeCloudTabs() throws {
        try database(locations.cloudTabs, [
            "CREATE TABLE cloud_tab_devices (device_uuid TEXT PRIMARY KEY NOT NULL, system_fields BLOB NOT NULL DEFAULT x'', device_name TEXT, device_type_identifier TEXT, has_duplicate_device_name BOOLEAN DEFAULT 0, is_ephemeral_device BOOLEAN DEFAULT 0, last_modified REAL NOT NULL DEFAULT 0)",
            "CREATE TABLE cloud_tabs (tab_uuid TEXT PRIMARY KEY NOT NULL, system_fields BLOB NOT NULL DEFAULT x'', device_uuid TEXT NOT NULL, position BLOB NOT NULL, title TEXT, url TEXT NOT NULL, is_showing_reader BOOLEAN DEFAULT 0, is_pinned BOOLEAN DEFAULT 0, reader_scroll_position_page_index INTEGER, scene_id TEXT, last_viewed_time REAL DEFAULT 0, topic_title TEXT)",
            "INSERT INTO cloud_tab_devices (device_uuid, device_name) VALUES ('P', 'Test Phone'), ('L', 'Test Laptop')",
            "INSERT INTO cloud_tabs (tab_uuid, device_uuid, position, title, url, last_viewed_time) VALUES ('t1', 'P', ?, 'Second', 'https://b.example.com/', 800000000)",
            "INSERT INTO cloud_tabs (tab_uuid, device_uuid, position, title, url, is_pinned) VALUES ('t2', 'P', ?, 'First', 'https://a.example.com/', 1)",
            "INSERT INTO cloud_tabs (tab_uuid, device_uuid, position, title, url) VALUES ('t3', 'L', ?, 'Laptop Tab', 'https://c.example.com/')",
        ], blobs: [try Self.position(20), try Self.position(10), try Self.position(5)])
    }

    func writeTabGroups() throws {
        try database(locations.tabGroups, [
            "CREATE TABLE bookmarks (id INTEGER PRIMARY KEY, parent INTEGER, type INTEGER, title TEXT, url TEXT, order_index INTEGER, deleted INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0)",
            "CREATE TABLE windows_tab_groups (window_id INTEGER, tab_group_id INTEGER)",
            "INSERT INTO bookmarks (id, parent, type, title, order_index) VALUES (0, NULL, 1, 'Root', 0), (5, 0, 1, 'Holiday', 1), (6, 0, 1, 'Local', 2), (7, 0, 1, 'Gone', 3)",
            "UPDATE bookmarks SET hidden = 1 WHERE id = 6",
            "UPDATE bookmarks SET deleted = 1 WHERE id = 7",
            "INSERT INTO bookmarks (id, parent, type, title, url, order_index) VALUES (10, 5, 0, 'Flights', 'https://flights.example.com/', 1), (11, 5, 0, 'Hotel', 'https://hotel.example.com/', 0), (12, 6, 0, 'Loose', 'https://loose.example.com/', 0)",
            "INSERT INTO windows_tab_groups VALUES (1, 5)",
        ])
    }

    func writeSession() throws {
        let closed = Date(timeIntervalSince1970: 1_760_000_000)
        try plist(["ClosedTabOrWindowPersistentStatesVersion": "1", "ClosedTabOrWindowPersistentStates": [
            ["PersistentStateType": 1, "PersistentState": ["IsPrivateWindow": false, "TabStates": [
                ["TabURL": "https://first.example.com/", "TabTitle": "First Closed", "DateClosed": closed, "LastVisitTime": closed.addingTimeInterval(-60)]]]],
            ["PersistentStateType": 0, "PersistentState": ["IsPrivateWindow": false, "DateClosed": closed.addingTimeInterval(60), "TabStates": [
                ["TabURL": "https://later.example.com/", "TabTitle": "Later Closed"]]]],
            ["PersistentStateType": 1, "PersistentState": ["IsPrivateWindow": true, "TabStates": [
                ["TabURL": "https://private.example.com/", "TabTitle": "Private", "DateClosed": closed.addingTimeInterval(120)]]]],
        ]], to: locations.recentlyClosed)
        try plist(["DownloadHistory": [
            ["DownloadEntryURL": "https://files.example.com/a.zip", "DownloadEntryPath": "~/Downloads/a.zip", "DownloadEntryProgressBytesSoFar": 2_048,
             "DownloadEntryProgressTotalToLoad": 2_048, "DownloadEntryDateAddedKey": closed, "DownloadEntryDateFinishedKey": closed.addingTimeInterval(5)],
            ["DownloadEntryURL": "https://files.example.com/b.pdf", "DownloadEntryDateAddedKey": closed.addingTimeInterval(100)],
        ]], to: locations.downloads)
    }
}

@Suite("Reading Safari's files")
struct ReadingTests {

    @Test func historyKeepsWhereThePersonLanded() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date().timeIntervalSinceReferenceDate
        try fixture.writeHistory(now: now)
        let all = try fixture.safari.history()
        #expect(all.map(\.title) == ["A Guide to Rust", "Old Page"])
        #expect(all[0].url == "https://www.example.org/guide?ref=mail#part-2")
        #expect(all[0].visitCount == 3 && all[0].origin == 1)
        #expect(abs(all[0].date.timeIntervalSinceReferenceDate - (now - 60)) < 0.001)
        let recent = try fixture.safari.history(since: Date().addingTimeInterval(-86_400))
        #expect(recent.map(\.title) == ["A Guide to Rust"])
        let older = try fixture.safari.history(until: Date().addingTimeInterval(-86_400))
        #expect(older.map(\.title) == ["Old Page"])
    }

    @Test func bookmarksCarryTheirFolders() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeBookmarks()
        let bookmarks = try fixture.safari.bookmarks()
        #expect(bookmarks.map(\.title) == ["News", "Docs", "Menu Page"])
        #expect(bookmarks.map(\.folder) == [["Favorites"], ["Favorites", "Work"], ["Bookmarks Menu"]])
        let reading = try fixture.safari.readingList()
        #expect(reading.map(\.title) == ["Newer", "Older"])
        #expect(reading[1].preview == "First words")
    }

    @Test func cloudTabsFollowEachDevicesOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeCloudTabs()
        let tabs = try fixture.safari.cloudTabs()
        #expect(tabs.map(\.title) == ["Laptop Tab", "First", "Second"])
        #expect(tabs[1].pinned && !tabs[2].pinned)
        #expect(tabs[2].lastViewed == Date(timeIntervalSinceReferenceDate: 800_000_000) && tabs[1].lastViewed == nil)
    }

    @Test func namedTabGroupsOnly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeTabGroups()
        let groups = try fixture.safari.tabGroups()
        #expect(groups.map(\.title) == ["Holiday"])
        #expect(groups[0].open)
        #expect(groups[0].tabs.map(\.title) == ["Hotel", "Flights"])
    }

    @Test func closedTabsNeverFromAPrivateWindow() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSession()
        let closed = try fixture.safari.recentlyClosed()
        #expect(closed.map(\.title) == ["Later Closed", "First Closed"])
        #expect(closed[0].closed == Date(timeIntervalSince1970: 1_760_000_060))
        let downloads = try fixture.safari.downloads()
        #expect(downloads.map(\.url) == ["https://files.example.com/b.pdf", "https://files.example.com/a.zip"])
        #expect(downloads[1].bytes == 2_048 && downloads[1].path == "~/Downloads/a.zip" && downloads[0].finished == nil)
    }

    @Test func refusalAndAbsenceAreTold() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(throws: BrowserDataError.missing(fixture.locations.bookmarks.path)) { try fixture.safari.bookmarks() }
        try fixture.writeBookmarks()
        try fixture.writeHistory(now: Date().timeIntervalSinceReferenceDate)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.locations.history.deletingLastPathComponent().path)
        #expect(throws: BrowserDataError.needsFullDiskAccess(fixture.locations.history.path)) { try fixture.safari.history() }
        #expect(throws: BrowserDataError.needsFullDiskAccess(fixture.locations.bookmarks.path)) { try fixture.safari.bookmarks() }
        #expect(fixture.safari.access().first { $0.name == "history" }?.state == .refused)
    }
}

@Suite("Privacy and queries")
struct PrivacyTests {

    @Test func trimmingDropsWhatRidesAlong() {
        #expect(URLPrivacy.trimmed("https://user:pw@www.bank.example/acct?id=42&session=abc#top") == "https://www.bank.example/acct")
        #expect(URLPrivacy.trimmed("https://www.youtube.com/watch?v=abc123&t=30s&si=xyz") == "https://www.youtube.com/watch?v=abc123")
        #expect(URLPrivacy.trimmed("https://news.ycombinator.com/item?id=1") == "https://news.ycombinator.com/item?id=1")
        #expect(URLPrivacy.trimmed("https://www.youtube.com/results?search_query=secret") == "https://www.youtube.com/results")
        #expect(URLPrivacy.trimmed("not a url?q=1") == "not a url")
        #expect(URLPrivacy.trimmed("https://example.org/") == "https://example.org/")
    }

    @Test func titlesLoseWhatTheAddressLost() {
        #expect(URLPrivacy.trimmedTitle("private words - Search", for: "https://search.example/?q=private+words") == "… - Search")
        #expect(URLPrivacy.trimmedTitle("Results for Café Paris", for: "https://s.example/?q=cafe%20paris&ok=1") == "Results for …")
        #expect(URLPrivacy.trimmedTitle("Cat Video abc123", for: "https://www.youtube.com/watch?v=abc123") == "Cat Video abc123")
        #expect(URLPrivacy.trimmedTitle("Page 1 of 2", for: "https://a.example/?p=1") == "Page 1 of 2")
        #expect(URLPrivacy.trimmedTitle(nil, for: "https://a.example/?q=abc") == nil)
    }

    @Test func hostsAndTheNeverShowList() {
        #expect(URLPrivacy.host(of: "https://WWW.Example.org/x") == "example.org")
        #expect(URLPrivacy.host(of: "https://m.example.org/x") == "example.org")
        #expect(URLPrivacy.host(of: "about:blank") == nil)
        let list = SiteList(["bank.example", "https://www.health.example/login", "  "])
        #expect(list.sites == ["bank.example", "health.example"])
        #expect(list.contains(url: "https://online.bank.example/acct"))
        #expect(list.contains(url: "https://bank.example"))
        #expect(list.contains(url: "https://portal.health.example/"))
        #expect(!list.contains(url: "https://notbank.example/"))
        #expect(!list.contains(url: nil))
        #expect(!SiteList([]).contains(url: "https://bank.example"))
    }

    @Test func searchMatchesWordStarts() {
        #expect(BrowserQueries.matches("rust guide", ["A Guide to Rust", nil]))
        #expect(BrowserQueries.matches("CAFE", ["Le Café"]))
        #expect(!BrowserQueries.matches("ust", ["A Guide to Rust"]))
        #expect(!BrowserQueries.matches("rust python", ["A Guide to Rust"]))
    }

    @Test func sitesCountVisits() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let visits = [
            HistoryVisit(url: "https://www.a.example/1", title: nil, date: date, visitCount: 1, origin: 0),
            HistoryVisit(url: "https://a.example/2", title: nil, date: date.addingTimeInterval(5), visitCount: 1, origin: 0),
            HistoryVisit(url: "https://a.example/2", title: nil, date: date, visitCount: 1, origin: 0),
            HistoryVisit(url: "https://b.example/", title: nil, date: date, visitCount: 1, origin: 0),
            HistoryVisit(url: "about:blank", title: nil, date: date, visitCount: 1, origin: 0),
        ]
        let sites = BrowserQueries.sites(visits)
        #expect(sites.map(\.site) == ["a.example", "b.example"])
        #expect(sites[0].visits == 3 && sites[0].pages == 2 && sites[0].lastVisit == date.addingTimeInterval(5))
    }
}

@Suite("Open tabs, through AppleScript")
struct ScriptingTests {

    static func answering(_ text: String) -> SafariScripting {
        SafariScripting { _, _ throws(BrowserDataError) in text }
    }

    @Test func tabsAreRead() throws {
        let f = "\u{1F}", r = "\u{1E}"
        let output = ["1\(f)1\(f)https://a.example/\(f)A\(f)false", "1\(f)2\(f)https://b.example/\(f)B\(f)true", "2\(f)1\(f)\(f)\(f)true"].joined(separator: r)
        let tabs = try Self.answering(output).tabs()
        #expect(tabs.count == 3)
        #expect(tabs[1] == OpenTab(window: 1, index: 2, url: "https://b.example/", title: "B", current: true))
        #expect(tabs[2].url == nil && tabs[2].title == nil)
        #expect(try Self.answering("").tabs().isEmpty)
        #expect(throws: BrowserDataError.notRunning) { try Self.answering(ScriptOutput.notRunning).tabs() }
    }

    @Test func pageTextKeepsItsOwnSeparators() throws {
        let f = "\u{1F}"
        let page = try Self.answering("https://a.example/\(f)Title\(f)line one\nline\(f)two").page()
        #expect(page.url == "https://a.example/" && page.title == "Title")
        #expect(page.text == "line one\nline\(f)two")
    }

    @Test func errorsAreClassified() {
        #expect(ScriptOutput.error(from: "0:12: execution error: Not authorized to send Apple events to Safari. (-1743)\n") == .needsAutomation)
        #expect(ScriptOutput.error(from: "execution error: Safari got an error: Application isn’t running. (-600)") == .notRunning)
        #expect(ScriptOutput.error(from: "execution error: Can’t get window 9. (-1719)") == .scriptFailed("execution error: Can’t get window 9. (-1719)"))
    }

    /// Compiling reads Safari's dictionary; only run while Safari is open
    /// already, so a test can never be what launches it.
    static var safariIsOpen: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Safari"]
        process.standardOutput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    @Test(.enabled(if: safariIsOpen)) func theScriptsCompile() throws {
        for script in [ScriptOutput.tabsScript, ScriptOutput.pageScript] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("browser-data-\(UUID().uuidString).scpt")
            defer { try? FileManager.default.removeItem(at: file) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            process.arguments = ["-o", file.path, "-e", script]
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
    }
}
