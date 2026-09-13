import Foundation

struct AppCatalogItem {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    var action: AppCreationAction { AppPickerResolver.action(bundleIdentifier: bundleIdentifier) }
    var title: String { "\(name) — \(action.title)" }
}

enum AppCatalog {
    static let roots = ["/Applications", "~/Applications", "/System/Applications", "/System/Library/CoreServices/Applications"]
        .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }

    static func scan(roots: [URL] = roots) -> [AppCatalogItem] {
        let manager = FileManager.default
        var items = [URL: AppCatalogItem]()
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let item = item(at: url) else { continue }
                items[item.url] = item
            }
        }
        return items.values.sorted(by: ordered)
    }

    static func item(at url: URL) -> AppCatalogItem? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard let bundle = Bundle(url: canonical), bundle.bundleURL.pathExtension.lowercased() == "app",
              bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL",
              (bundle.infoDictionary?["LSBackgroundOnly"] as? NSNumber)?.boolValue != true,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        return AppCatalogItem(url: canonical, name: name.flatMap { $0.isEmpty ? nil : $0 }
            ?? canonical.deletingPathExtension().lastPathComponent, bundleIdentifier: bundle.bundleIdentifier)
    }

    static func matching(_ query: String, in items: [AppCatalogItem], recentlyUsed: [URL: TimeInterval] = [:],
        frequencyScores: [URL: Double] = [:]) -> [AppCatalogItem] {
        let empty = SearchTestable.normalize(query).text.isEmpty
        return items.compactMap { item -> (AppCatalogItem, Int)? in
            if empty { return (item, 0) }
            let texts = [item.name, item.url.deletingPathExtension().lastPathComponent, item.title] + item.action.aliases
            guard let score = texts.compactMap({ SearchTestable.tierMatch(query: query, text: $0)?.score }).max() else { return nil }
            return (item, score)
        }.sorted {
            let lhsFrequency = frequencyScores[$0.0.url] ?? 0
            let rhsFrequency = frequencyScores[$1.0.url] ?? 0
            if lhsFrequency != rhsFrequency { return lhsFrequency > rhsFrequency }
            let lhs = recentlyUsed[$0.0.url] ?? 0
            let rhs = recentlyUsed[$1.0.url] ?? 0
            if lhs != rhs { return lhs > rhs }
            return $0.1 == $1.1 ? ordered($0.0, $1.0) : $0.1 > $1.1
        }.map { $0.0 }
    }

    private static func ordered(_ lhs: AppCatalogItem, _ rhs: AppCatalogItem) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedSame ? lhs.url.path < rhs.url.path : comparison == .orderedAscending
    }
}
