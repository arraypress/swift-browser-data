# swift-browser-data

A Mac browser's own data, read-only: Safari's history, bookmarks, Reading List, tabs on your other devices, tab groups, recently closed tabs and downloads, read from the files Safari keeps, plus the tabs open right now through Safari's scripting dictionary. No Apple framework is linked; the databases are read from a private copy and never opened in place. Safari only today; Chrome is planned.

```swift
import BrowserData

let safari = SafariData()
let never = SiteList(["bank.example"])
for visit in try safari.history(since: Date().addingTimeInterval(-86_400)) where !never.contains(url: visit.url) {
    print(visit.date, visit.title ?? "", URLPrivacy.trimmed(visit.url))
}
let open = try SafariScripting().tabs()      // asks macOS for Automation once
```

## Where it is (measured on macOS 27.0.1, Safari 27)

All behind **Full Disk Access**.

| What | File | Shape |
| --- | --- | --- |
| History | `~/Library/Safari/History.db` | `history_items` (address, visit count) + `history_visits` (time since 2001, title, redirect links, `origin`) |
| Bookmarks, Reading List | `~/Library/Safari/Bookmarks.plist` | a tree of List/Leaf/Proxy nodes; the Reading List is the `com.apple.ReadingList` folder |
| Recently closed | `~/Library/Safari/RecentlyClosedTabs.plist` | windows and tabs, with `IsPrivateWindow` |
| Downloads | `~/Library/Safari/Downloads.plist` | `DownloadHistory` |
| Tabs on other devices | `…/Containers/com.apple.Safari/Data/Library/Safari/CloudTabs.db` | devices + tabs; order in a zlib-wrapped JSON `position` |
| Tab groups | `…/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db` | `bookmarks` rows of type 1 under the root |

- **History is where you landed:** a hop that redirected onward and a page that failed to load are left out.
- **A private window's closed tabs are never returned.**
- `origin` is 0 or 1 on a real store — most likely this Mac and another device — and is kept raw until measured.
- Downloads' keys are the `DownloadEntry…` names in Safari's own binary; the measured list was empty, so their values are read leniently.

## Open tabs

`SafariScripting` runs `/usr/bin/osascript` against Safari's dictionary (`tab`: `URL`, `name`, `text`, `source`): `tabs()`, `page()` for a tab's visible text, and `source()` for its HTML as Safari holds it — signed-in pages included — for a reader such as Readability to pull the article from. It never launches Safari: the script asks `is running` first, which sends Safari nothing. The first ask makes macOS show the Automation prompt for the host (Terminal, an agent); refusal is `needsAutomation`. Whether a private window's tabs are listed is not yet measured.

## Privacy helpers

- `URLPrivacy.trimmed` drops the query string, fragment and user:password — except the parameters that name the page itself on sites where nothing else does (YouTube's `v` and `list`, Hacker News's `id`).
- `SiteList` — sites never to show, each with its subdomains (`bank.example` hides `online.bank.example`, not `notbank.example`).
- `BrowserQueries` — search (every word must start a word; case and accents ignored), visits per site, and `collapsed`: Safari records three to six visits for one look at a page (reloads, in-site redirects, the title arriving late); back-to-back repeats within 5 minutes become one.

## Writing

None. Bookmarks, tab groups and the Reading List change only through Safari's own Shortcuts actions; see the `browse` CLI.

## Requirements

macOS 14 or later. Swift 6.2. One dependency: [swift-sqlite-reader](https://github.com/arraypress/swift-sqlite-reader), which copies each database and reads the copy.

## Licence

MIT.
