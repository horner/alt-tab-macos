import Foundation

enum ProjectSnapshotHistory {
    struct Entry: Equatable {
        let readme: URL
        let capturedAt: Date?
        let windowCount: Int?
        let status: String
    }

    private struct Summary: Decodable {
        struct Window: Decodable {}
        let capturedAt: Date
        let windows: [Window]
        let status: String
    }

    static func load(in projectDirectory: URL) -> [Entry] {
        let archives = projectDirectory.appendingPathComponent("archives", isDirectory: true)
        guard isRegular(archives, directory: true),
              let folders = try? FileManager.default.contentsOfDirectory(at: archives, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX")
        dates.timeZone = TimeZone(secondsFromGMT: 0)
        dates.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return folders.compactMap { folder -> Entry? in
            guard isRegular(folder, directory: true) else { return nil }
            let readme = folder.appendingPathComponent("README.md")
            guard isRegular(readme) else { return nil }
            let metadata = folder.appendingPathComponent("snapshot.json")
            let summary = isRegular(metadata) ? (try? Data(contentsOf: metadata)).flatMap { try? decoder.decode(Summary.self, from: $0) } : nil
            return Entry(readme: readme, capturedAt: summary?.capturedAt ?? dates.date(from: String(folder.lastPathComponent.prefix(20))),
                windowCount: summary?.windows.count,
                status: summary?.status ?? NSLocalizedString("Snapshot details are unavailable. The saved Markdown can still be opened.", comment: "Missing snapshot metadata"))
        }.sorted {
            let first = $0.capturedAt ?? .distantPast
            let second = $1.capturedAt ?? .distantPast
            return first == second ? $0.readme.path < $1.readme.path : first > second
        }
    }

    static func isRegular(_ url: URL, directory: Bool = false) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
        return directory ? values.isDirectory == true : values.isRegularFile == true
    }
}
