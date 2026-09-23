import Foundation

enum SnapshotViewerDocument {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Payload: Encodable {
        let markdown: String
        let images: [String: String]
    }

    private static let maximumMarkdownBytes = 4 * 1024 * 1024
    private static let marker = "__SNAPSHOT_DATA__"
    private static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])

    /// Perform filesystem work on a background queue. The caller owns the returned document's temporary directory.
    static func prepare(readme: URL, template: String, directory: URL) throws -> URL {
        guard template.components(separatedBy: marker).count == 2 else {
            throw Failure(message: "The snapshot viewer is unavailable. Reinstall the app and try again.")
        }
        let archive = readme.deletingLastPathComponent()
        guard readme.isFileURL, readme.lastPathComponent == "README.md", isUnaliased(readme), isRegular(readme), isRegular(archive, directory: true) else {
            throw Failure(message: "The saved snapshot could not be found or its path is a symbolic link.")
        }
        let markdown = try markdown(at: readme)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let payload = Payload(markdown: markdown, images: try imagePaths(in: archive, prepared: directory))
            let data = try JSONEncoder().encode(payload)
            let html = template.replacingOccurrences(of: marker, with: scriptSafe(String(decoding: data, as: UTF8.self)))
            let document = directory.appendingPathComponent("viewer.html")
            try Data(html.utf8).write(to: document, options: .atomic)
            return document
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private static func markdown(at readme: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: readme)
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: maximumMarkdownBytes + 1)
        guard data.count <= maximumMarkdownBytes else { throw Failure(message: "This snapshot is too large to preview. Open the saved Markdown externally to read it.") }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure(message: "The saved snapshot is not valid UTF-8 Markdown.") }
        return text
    }

    private static func imagePaths(in archive: URL, prepared: URL) throws -> [String: String] {
        let screenshots = archive.appendingPathComponent("screenshots", isDirectory: true)
        guard isUnaliased(screenshots), isRegular(screenshots, directory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: screenshots, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { return [:] }
        let destination = prepared.appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var paths = [String: String]()
        for file in files {
            guard file.pathExtension.lowercased() == "png", isUnaliased(file), isRegular(file), isPNG(file) else { continue }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            guard prepareImage(file, at: target) else { continue }
            paths["screenshots/" + file.lastPathComponent] = target.standardizedFileURL.absoluteString
        }
        return paths
    }

    static func prepareImage(_ source: URL, at target: URL, link: (URL, URL) throws -> Void = FileManager.default.linkItem) -> Bool {
        let manager = FileManager.default
        do {
            do { try link(source, target) }
            catch { try manager.copyItem(at: source, to: target) }
            guard isUnaliased(target), isRegular(target), isPNG(target) else {
                try? manager.removeItem(at: target)
                return false
            }
            return true
        } catch {
            try? manager.removeItem(at: target)
            return false
        }
    }

    private static func isPNG(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { handle.closeFile() }
        return handle.readData(ofLength: pngSignature.count) == pngSignature
    }

    private static func isUnaliased(_ url: URL) -> Bool {
        let standard = url.standardizedFileURL
        return !url.pathComponents.contains("..") && standard.path == standard.resolvingSymlinksInPath().path
    }

    private static func isRegular(_ url: URL, directory: Bool = false) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
        return directory ? values.isDirectory == true : values.isRegularFile == true
    }

    private static func scriptSafe(_ json: String) -> String {
        json.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
