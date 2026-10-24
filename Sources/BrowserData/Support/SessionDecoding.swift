//
//  SessionDecoding.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  The two plists and one blob Safari keeps about tabs and downloads.
//
//  MEASURED on macOS 27.0.1 (Safari 27):
//  - RecentlyClosedTabs.plist: `ClosedTabOrWindowPersistentStates`, each a
//    `PersistentState` with `TabStates` (`TabURL`, `TabTitle`, `DateClosed`,
//    `LastVisitTime`) and `IsPrivateWindow`. A private window's tabs are
//    never returned.
//  - CloudTabs.db `cloud_tabs.position`: zlib-wrapped JSON,
//    `{"sortValues": [{"sortValue", "changeID", "deviceIdentifier"}]}` —
//    the tab's place on its device.
//  - Downloads.plist: `DownloadHistory`, a list. Its entries' keys are the
//    `DownloadEntry…` names in Safari's own binary (`DownloadEntryURL`,
//    `…Path`, `…ProgressBytesSoFar`, `…ProgressTotalToLoad`,
//    `…DateAddedKey`, `…DateFinishedKey`); this Mac's list was empty, so
//    their value types are read leniently.
//

import Foundation

/// Reading Safari's session files. Pure.
enum SessionDecoding {

    static func plist(_ data: Data, path: String) throws(BrowserDataError) -> [String: Any] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil), let root = plist as? [String: Any] else {
            throw .unreadable(path, reason: "not a property-list dictionary")
        }
        return root
    }

    /// Closed tabs, most recently closed first; private windows left out.
    static func closedTabs(_ root: [String: Any]) -> [ClosedTab] {
        let states = root["ClosedTabOrWindowPersistentStates"] as? [[String: Any]] ?? []
        let tabs = states.flatMap { entry -> [ClosedTab] in
            let state = entry["PersistentState"] as? [String: Any] ?? [:]
            guard state["IsPrivateWindow"] as? Bool != true else { return [] }
            return (state["TabStates"] as? [[String: Any]] ?? []).compactMap { tab in
                guard let url = tab["TabURL"] as? String, !url.isEmpty else { return nil }
                return ClosedTab(url: url, title: (tab["TabTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                 closed: tab["DateClosed"] as? Date ?? state["DateClosed"] as? Date,
                                 lastVisit: tab["LastVisitTime"] as? Date)
            }
        }
        return tabs.sorted { ($0.closed ?? .distantPast) > ($1.closed ?? .distantPast) }
    }

    /// Downloads, newest first.
    static func downloads(_ root: [String: Any]) -> [Download] {
        (root["DownloadHistory"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let url = entry["DownloadEntryURL"] as? String else { return nil }
            return Download(url: url, path: entry["DownloadEntryPath"] as? String,
                            bytes: integer(entry["DownloadEntryProgressBytesSoFar"]),
                            totalBytes: integer(entry["DownloadEntryProgressTotalToLoad"]),
                            added: entry["DownloadEntryDateAddedKey"] as? Date,
                            finished: entry["DownloadEntryDateFinishedKey"] as? Date)
        }
        .sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
    }

    /// A tab's place on its device, from its `position` blob; `nil` when unreadable.
    static func sortValue(_ blob: Data?) -> Int? {
        guard let blob, blob.count > 2,
              let json = try? (blob.dropFirst(2) as NSData).decompressed(using: .zlib) as Data,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let values = object["sortValues"] as? [[String: Any]]
        else { return nil }
        return values.first.flatMap { integer($0["sortValue"]) }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let text as String: Int(text)
        default: nil
        }
    }
}
