//
//  SQLiteRow+Columns.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  How this library reads a row's columns: NULL as `nil`, and empty text
//  as absent.
//

import Foundation
import SQLiteReader

extension SQLiteRow {

    /// A column as a double, `nil` for NULL.
    func double(_ index: Int) -> Double? { self[index].double }

    /// A column as an integer, `nil` for NULL; a real is truncated toward zero.
    func integer(_ index: Int) -> Int? {
        if let value = self[index].int { return value }
        return self[index].double.flatMap { Int(exactly: $0.rounded(.towardZero)) }
    }

    /// A column as text, `nil` for NULL or empty.
    func text(_ index: Int) -> String? {
        guard let text = self[index].string, !text.isEmpty else { return nil }
        return text
    }

    /// A column as bytes, `nil` for NULL.
    func blob(_ index: Int) -> Data? { self[index].data }
}
