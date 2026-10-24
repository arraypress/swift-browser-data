//
//  SafariScripting.swift
//  BrowserData
//
//  Created by David Sherlock on 2026.
//
//  What Safari has open, asked through its own scripting dictionary (the
//  `tab` class: `URL`, `name`, `text`; a window's `current tab`). Each ask
//  runs /usr/bin/osascript; macOS asks the person once whether the host
//  (the terminal, the agent) may control Safari — refused is -1743.
//
//  Safari is never launched: the script checks `is running` (which sends
//  Safari nothing) before it speaks to it. Read-only: no script here
//  changes a tab.
//

import Foundation

/// Safari's open windows and tabs, read through AppleScript.
public struct SafariScripting: Sendable {

    /// Runs an AppleScript with arguments and returns what it returned.
    public typealias Runner = @Sendable (_ script: String, _ arguments: [String]) throws(BrowserDataError) -> String

    let run: Runner

    public init(run: @escaping Runner = SafariScripting.osascript) {
        self.run = run
    }

    /// Every tab in every window; window 1 is the frontmost.
    public func tabs() throws(BrowserDataError) -> [OpenTab] {
        try ScriptOutput.tabs(try run(ScriptOutput.tabsScript, []))
    }

    /// A tab's visible text: `window` 1 is the frontmost; no `tab` means the one it shows.
    public func page(window: Int = 1, tab: Int? = nil) throws(BrowserDataError) -> PageText {
        try ScriptOutput.page(try run(ScriptOutput.pageScript, [String(window), String(tab ?? 0)]))
    }

    /// The real runner: /usr/bin/osascript, its output and errors in files
    /// (a pipe left unread can stall a child that writes a lot — a page's text).
    public static let osascript: Runner = { script, arguments throws(BrowserDataError) in
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("browser-data-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out"), errors = folder.appendingPathComponent("err")
        let process = Process()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: output.path, contents: nil)
            FileManager.default.createFile(atPath: errors.path, contents: nil)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script] + arguments
            process.standardOutput = try FileHandle(forWritingTo: output)
            process.standardError = try FileHandle(forWritingTo: errors)
            try process.run()
        } catch {
            throw .scriptFailed("could not run osascript: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            throw ScriptOutput.error(from: (try? String(contentsOf: errors, encoding: .utf8)) ?? "")
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}

/// The scripts, and reading what they return. Pure.
enum ScriptOutput {

    /// Fields are split by U+001F, records by U+001E — characters no title or address holds.
    static let field: Character = "\u{1F}", record: Character = "\u{1E}"
    static let notRunning = "\u{1E}NOT RUNNING"

    static let prelude = """
        if application id "com.apple.Safari" is not running then return "\(notRunning)"
        set us to character id 31
        set rs to character id 30
        """

    /// One record per tab: window, index, URL, name, whether it is its window's current tab.
    static let tabsScript = prelude + """

        tell application id "com.apple.Safari"
            set out to {}
            set wi to 0
            repeat with w in (every window)
                set wi to wi + 1
                try
                    set urls to URL of every tab of w
                    set names to name of every tab of w
                    set ci to 0
                    try
                        set ci to index of current tab of w
                    end try
                    repeat with i from 1 to count of urls
                        set u to item i of urls
                        if u is missing value then set u to ""
                        set n to item i of names
                        if n is missing value then set n to ""
                        set end of out to (wi as text) & us & (i as text) & us & u & us & n & us & ((i = ci) as text)
                    end repeat
                end try
            end repeat
            set AppleScript's text item delimiters to rs
            return out as text
        end tell
        """

    /// One record: URL, name, text. Arguments: window, tab (0 = the one it shows).
    static let pageScript = """
        on run argv
            \(prelude.replacingOccurrences(of: "\n", with: "\n    "))
            set wi to (item 1 of argv) as integer
            set ti to (item 2 of argv) as integer
            tell application id "com.apple.Safari"
                if (count of windows) < wi then return "\(notRunning)"
                if ti = 0 then
                    set t to current tab of window wi
                else
                    if (count of tabs of window wi) < ti then return "\(notRunning)"
                    set t to tab ti of window wi
                end if
                set u to URL of t
                if u is missing value then set u to ""
                set n to name of t
                if n is missing value then set n to ""
                set x to text of t
                if x is missing value then set x to ""
                return u & us & n & us & x
            end tell
        end run
        """

    static func tabs(_ output: String) throws(BrowserDataError) -> [OpenTab] {
        guard output != notRunning else { throw .notRunning }
        return output.split(separator: record).compactMap { line in
            let parts = line.split(separator: field, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, let window = Int(parts[0]), let index = Int(parts[1]) else { return nil }
            return OpenTab(window: window, index: index, url: parts[2].isEmpty ? nil : parts[2],
                           title: parts[3].isEmpty ? nil : parts[3], current: parts[4] == "true")
        }
    }

    static func page(_ output: String) throws(BrowserDataError) -> PageText {
        guard output != notRunning else { throw .notRunning }
        let parts = output.split(separator: field, maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { throw .scriptFailed("an answer in an unexpected shape") }
        return PageText(url: parts[0].isEmpty ? nil : parts[0], title: parts[1].isEmpty ? nil : parts[1], text: parts[2])
    }

    /// osascript's error line (`… Not authorized to send Apple events to Safari. (-1743)`), classified.
    static func error(from message: String) -> BrowserDataError {
        let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = line.firstMatch(of: /\((-?\d+)\)\s*$/).flatMap { Int($0.output.1) }
        switch code {
        case -1743: return .needsAutomation
        case -600, -609: return .notRunning
        default: return .scriptFailed(line.isEmpty ? "osascript failed" : line)
        }
    }
}
