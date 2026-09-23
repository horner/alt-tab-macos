import Cocoa

enum AppUsage {
    private static let queue = DispatchQueue(label: "appPicker.usage", qos: .utility)
    private static let key = "appPickerLastUsed"
    private static let frequencyKey = "appPickerFrequencyV1"
    private static var dates = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    private static var frequencies = loadFrequencies()

    static func record(_ url: URL?, pickerOpen: Bool = false) {
        guard let url, url != Bundle.main.bundleURL else { return }
        let now = Date().timeIntervalSince1970
        queue.async {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            dates[path] = now
            UserDefaults.standard.set(dates, forKey: key)
            guard pickerOpen else { return }
            frequencies[path, default: AppUsageScore()].record(at: now)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(frequencies) { UserDefaults.standard.set(data, forKey: frequencyKey) }
        }
    }

    // Called from the picker worker; filesystem resolution and defaults never block a keystroke.
    static func snapshot(seeding recentWindows: [URL: TimeInterval]) -> (lastUsed: [URL: TimeInterval], frequency: [URL: Double]) {
        queue.sync {
            var result = Dictionary(uniqueKeysWithValues: dates.map { (URL(fileURLWithPath: $0.key), $0.value) })
            for (url, date) in recentWindows {
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                result[canonical] = max(result[canonical] ?? 0, date)
            }
            let now = Date().timeIntervalSince1970
            let scores = Dictionary(uniqueKeysWithValues: frequencies.map { (URL(fileURLWithPath: $0.key), $0.value.rankingScore(at: now)) })
            return (result, scores)
        }
    }

    private static func loadFrequencies() -> [String: AppUsageScore] {
        guard let data = UserDefaults.standard.data(forKey: frequencyKey),
              let saved = try? PropertyListDecoder().decode([String: AppUsageScore].self, from: data) else { return [:] }
        return saved.filter { $0.value.isValid }
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
