//
//  FileState.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//

/// Whether one of the browser's files can be read.
public enum FileState: String, Codable, Sendable {
    case readable
    /// Not there: the browser has not written it yet.
    case missing
    /// macOS refused — Full Disk Access.
    case refused
}
