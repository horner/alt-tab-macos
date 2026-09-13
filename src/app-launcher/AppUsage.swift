import Cocoa

enum AppUsage {
    private static let queue = DispatchQueue(label: "appPicker.usage", qos: .utility)
    private static let key = "appPickerLastUsed"
    private static var dates = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]

    static func record(_ url: URL?) {
        guard let url, url != Bundle.main.bundleURL else { return }
        let now = Date().timeIntervalSince1970
        queue.async {
            dates[url.resolvingSymlinksInPath().standardizedFileURL.path] = now
            UserDefaults.standard.set(dates, forKey: key)
        }
    }

    // Called from the picker worker; filesystem resolution and defaults never block a keystroke.
    static func snapshot(seeding recentWindows: [URL: TimeInterval]) -> [URL: TimeInterval] {
        queue.sync {
            var result = Dictionary(uniqueKeysWithValues: dates.map { (URL(fileURLWithPath: $0.key), $0.value) })
            for (url, date) in recentWindows {
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                result[canonical] = max(result[canonical] ?? 0, date)
            }
            return result
        }
    }

    static func windowSnapshot() -> [URL: TimeInterval] {
        let epoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        var result = [URL: TimeInterval]()
        for window in Windows.list {
            guard let url = window.application.bundleURL, url != Bundle.main.bundleURL else { continue }
            let date = window.focusedAt > 0 ? epoch + window.focusedAt : 1 / Double(max(0, window.lastFocusOrder) + 1)
            result[url] = max(result[url] ?? 0, date)
        }
        return result
    }
}
