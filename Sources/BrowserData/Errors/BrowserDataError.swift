//
//  BrowserDataError.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong reading a browser's data.
public enum BrowserDataError: Error, Equatable, Sendable, LocalizedError {

    /// macOS refused to let this process read a file — what a missing Full
    /// Disk Access grant looks like. Carries the path.
    case needsFullDiskAccess(String)

    /// No file at the path (the browser has never written it). Carries it.
    case missing(String)

    /// The file is there but could not be understood.
    case unreadable(String, reason: String)

    /// The browser is not running, so it has no open tabs to read.
    case notRunning

    /// macOS refused to let this process control the browser (Automation).
    case needsAutomation

    /// The browser answered with an error. Carries its message.
    case scriptFailed(String)

    /// A sentence a person can act on.
    public var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess(let path):
            "Not allowed to read \(path) — macOS keeps Safari's files behind Full Disk Access"
        case .missing(let path):
            "Nothing at \(path)"
        case .unreadable(let path, let reason):
            "Could not read \(path): \(reason)"
        case .notRunning:
            "Safari is not open"
        case .needsAutomation:
            "Not allowed to ask Safari for its tabs — macOS keeps that behind Automation"
        case .scriptFailed(let message):
            "Safari answered: \(message)"
        }
    }
}
