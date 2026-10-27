//
//  BrowserDataError+SQLiteReader.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  The databases are read through swift-sqlite-reader; its errors are
//  reported as this library's own, so callers and messages stay the same.
//

import Foundation
import SQLiteReader

extension BrowserDataError {

    /// This library's error for a reader's.
    init(_ error: SQLiteReaderError) {
        switch error {
        case .notFound(let path): self = .missing(path)
        case .permissionDenied(let path): self = .needsFullDiskAccess(path)
        case .unreadable(let path, let reason): self = .unreadable(path, reason: reason)
        }
    }
}

extension SQLiteReader {

    /// A private copy of a live database and its log, deleted when the
    /// reader goes: Safari writes its databases while this reads, and the
    /// live files are never opened.
    static func snapshot(of database: URL) throws(BrowserDataError) -> SQLiteReader {
        do { return try SQLiteReader(path: database, opening: .snapshot) } catch { throw BrowserDataError(error) }
    }

    /// Runs a query with `?` values bound in order, handing each row over,
    /// and reports a failure as a ``BrowserDataError``.
    func read(_ sql: String, _ values: [Double] = [], row: (SQLiteRow) -> Void) throws(BrowserDataError) {
        do { try query(sql, values.map { .real($0) }, row: row) } catch { throw BrowserDataError(error) }
    }
}
