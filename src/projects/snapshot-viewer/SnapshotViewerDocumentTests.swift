import XCTest

final class SnapshotViewerDocumentTests: XCTestCase {
    private struct Payload: Decodable {
        let markdown: String
        let images: [String: String]
    }

    private let template = "<html><script type=\"application/json\">__SNAPSHOT_DATA__</script></html>"
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jTioAAAAASUVORK5CYII=")!

    func testUsesReadableMarkdownWithoutSnapshotMetadataAndLeavesArchiveUnchanged() throws {
        try withArchive { _, archive, output in
            let markdown = "# Saved desktop\n\n![A window](screenshots/window-1.png)"
            let readme = archive.appendingPathComponent("README.md")
            let screenshot = archive.appendingPathComponent("screenshots/window-1.png")
            try Data(markdown.utf8).write(to: readme)
            try self.png.write(to: screenshot)
            let viewer = try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output)
            let payload = try self.payload(at: viewer)
            let preparedImage = output.appendingPathComponent("screenshots/window-1.png")
            XCTAssertEqual(payload.markdown, markdown)
            XCTAssertEqual(payload.images, ["screenshots/window-1.png": preparedImage.standardizedFileURL.absoluteString])
            XCTAssertEqual(try String(contentsOf: readme), markdown)
            XCTAssertEqual(try Data(contentsOf: screenshot), self.png)
            XCTAssertEqual(try Data(contentsOf: preparedImage), self.png)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["screenshots", "viewer.html"])
            XCTAssertEqual(viewer.deletingLastPathComponent(), output)
        }
    }

    func testCorruptMetadataDoesNotPreventOpeningMarkdown() throws {
        try withArchive { _, archive, output in
            try Data("damaged JSON".utf8).write(to: archive.appendingPathComponent("snapshot.json"))
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            XCTAssertEqual(try self.payload(at: viewer).markdown, "# Snapshot")
        }
    }

    func testPreparingImageCopiesWhenHardLinksAreUnavailable() throws {
        try withArchive { _, archive, output in
            let source = archive.appendingPathComponent("screenshots/window-1.png")
            let target = output.appendingPathComponent("window-1.png")
            try self.png.write(to: source)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            XCTAssertTrue(SnapshotViewerDocument.prepareImage(source, at: target, link: { _, _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))
            }))
            XCTAssertEqual(try Data(contentsOf: target), self.png)
            XCTAssertEqual(try Data(contentsOf: source), self.png)
        }
    }

    func testPreparedImageSurvivesRemovalOfTheArchiveSource() throws {
        try withArchive { _, archive, output in
            let source = archive.appendingPathComponent("screenshots/window-1.png")
            try self.png.write(to: source)
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            let image = try XCTUnwrap(self.payload(at: viewer).images["screenshots/window-1.png"].flatMap(URL.init(string:)))
            try FileManager.default.removeItem(at: archive)
            XCTAssertEqual(try Data(contentsOf: image), self.png)
        }
    }

    func testMarkdownCannotBreakOutOfEmbeddedJSONScript() throws {
        try withArchive { _, archive, output in
            let markdown = "</script><script>alert('x')</script> & > \u{2028}\u{2029} __SNAPSHOT_DATA__"
            try Data(markdown.utf8).write(to: archive.appendingPathComponent("README.md"))
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            let html = try String(contentsOf: viewer)
            XCTAssertEqual(try self.payload(at: viewer).markdown, markdown)
            XCTAssertEqual(html.components(separatedBy: "</script>").count, 2)
            XCTAssertFalse(html.contains("<script>alert"))
            XCTAssertTrue(html.contains("\\u003c"))
            XCTAssertTrue(html.contains("\\u0026"))
            XCTAssertTrue(html.contains("\\u2028\\u2029"))
        }
    }

    func testOnlyDirectLocalPNGFilesAreMapped() throws {
        try withArchive { root, archive, output in
            try self.png.write(to: root.appendingPathComponent("outside.png"))
            try self.png.write(to: archive.appendingPathComponent("outside.png"))
            try Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8).write(to: archive.appendingPathComponent("screenshots/disguised.png"))
            try self.png.write(to: archive.appendingPathComponent("screenshots/other.jpg"))
            try self.png.write(to: archive.appendingPathComponent("screenshots/.hidden.png"))
            try FileManager.default.createDirectory(at: archive.appendingPathComponent("screenshots/nested"), withIntermediateDirectories: false)
            try self.png.write(to: archive.appendingPathComponent("screenshots/nested/window.png"))
            let markdown = "![remote](https://example.com/image.png) ![escape](../outside.png) ![data](data:image/png;base64,abc)"
            try Data(markdown.utf8).write(to: archive.appendingPathComponent("README.md"))
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            XCTAssertTrue(try self.payload(at: viewer).images.isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent("screenshots").path).isEmpty)
        }
    }

    func testScreenshotSymlinkCannotExposeAFileOutsideTheArchive() throws {
        try withArchive { root, archive, output in
            let outside = root.appendingPathComponent("outside.png")
            try self.png.write(to: outside)
            try FileManager.default.createSymbolicLink(at: archive.appendingPathComponent("screenshots/window-1.png"), withDestinationURL: outside)
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            XCTAssertTrue(try self.payload(at: viewer).images.isEmpty)
        }
    }

    func testScreenshotsDirectorySymlinkCannotExposeOutsideImages() throws {
        try withArchive { root, archive, output in
            let screenshots = archive.appendingPathComponent("screenshots")
            try FileManager.default.removeItem(at: screenshots)
            try self.png.write(to: root.appendingPathComponent("window-1.png"))
            try FileManager.default.createSymbolicLink(at: screenshots, withDestinationURL: root)
            let viewer = try SnapshotViewerDocument.prepare(readme: archive.appendingPathComponent("README.md"), template: self.template, directory: output)
            XCTAssertTrue(try self.payload(at: viewer).images.isEmpty)
        }
    }

    func testReadmeSymlinkIsRejected() throws {
        try withArchive { root, archive, output in
            let readme = archive.appendingPathComponent("README.md")
            let outside = root.appendingPathComponent("private.md")
            try Data("private".utf8).write(to: outside)
            try FileManager.default.removeItem(at: readme)
            try FileManager.default.createSymbolicLink(at: readme, withDestinationURL: outside)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testAncestorSymlinkAndTraversalReadmeAreRejected() throws {
        try withArchive { root, archive, output in
            let link = root.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: link.appendingPathComponent("archive/README.md"), template: self.template, directory: output))
            let traversal = archive.appendingPathComponent("screenshots/../README.md")
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: traversal, template: self.template, directory: output))
        }
    }

    func testMissingUnreadableEncodingAndOversizedMarkdownFailWithoutCreatingViewer() throws {
        try withArchive { _, archive, output in
            let readme = archive.appendingPathComponent("README.md")
            try FileManager.default.removeItem(at: readme)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output))
            try Data([0xff, 0xfe, 0xff]).write(to: readme)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output))
            try Data(repeating: 65, count: 4 * 1024 * 1024 + 1).write(to: readme)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testExistingDestinationAndInvalidTemplateAreNeverOverwritten() throws {
        try withArchive { _, archive, output in
            let readme = archive.appendingPathComponent("README.md")
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: "missing marker", directory: output))
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: "__SNAPSHOT_DATA____SNAPSHOT_DATA__", directory: output))
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            let sentinel = output.appendingPathComponent("viewer.html")
            try Data("existing".utf8).write(to: sentinel)
            XCTAssertThrowsError(try SnapshotViewerDocument.prepare(readme: readme, template: self.template, directory: output))
            XCTAssertEqual(try String(contentsOf: sentinel), "existing")
        }
    }

    private func withArchive(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archive = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Snapshot".utf8).write(to: archive.appendingPathComponent("README.md"))
        try body(root, archive, root.appendingPathComponent("viewer", isDirectory: true))
    }

    private func payload(at viewer: URL) throws -> Payload {
        let html = try String(contentsOf: viewer)
        let start = try XCTUnwrap(html.range(of: "<script type=\"application/json\">"))
        let end = try XCTUnwrap(html.range(of: "</script>"))
        return try JSONDecoder().decode(Payload.self, from: Data(html[start.upperBound..<end.lowerBound].utf8))
    }
}
