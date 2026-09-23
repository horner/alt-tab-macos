import XCTest
import Yams

final class ProjectFileStoreTests: XCTestCase {
    private var root: URL!
    private var store: ProjectFileStore!
    private let identity = ProjectWindowIdentity(windowId: "42", pid: 123, processLaunchedAt: Date(timeIntervalSince1970: 100))

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AltTabProjectFilesTests-" + UUID().uuidString)
        store = ProjectFileStore(root: root)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    private func project(_ name: String = "Research") -> ProjectEntry {
        ProjectEntry(id: "stable-id", kind: "custom", spaceUuid: nil, homeSpaceUuid: "desktop-1", name: name, autoName: nil,
            members: [identity], memberPatterns: [ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Notes: #1 🐈", lastSeenAt: Date(timeIntervalSince1970: 200), url: "https://example.com/notes#one", confirmedAt: Date(timeIntervalSince1970: 100))])
    }

    private func yamlURL() throws -> URL {
        let folder = try XCTUnwrap(store.records.keys.first)
        return store.projectsDirectory.appendingPathComponent(folder).appendingPathComponent("project.yaml")
    }

    func testMigrationRoundTripSeparatesRuntimeAndPreservesNotes() throws {
        let entry = project()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false), store.errors.description)
        let url = try yamlURL()
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("processLaunchedAt"))
        XCTAssertFalse(text.contains("lastSeenAt"))
        XCTAssertFalse(text.contains("pendingDesktopRemoval"))
        XCTAssertTrue(text.contains("schemaVersion: 1"))
        XCTAssertTrue(text.contains("confirmedAt:"))
        let loaded = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(loaded.memberPatterns.first?.title, entry.memberPatterns.first?.title)
        XCTAssertEqual(loaded.memberPatterns.first?.confirmedAt, entry.memberPatterns.first?.confirmedAt)
        XCTAssertTrue(loaded.members.isEmpty)
        let restored = ProjectRuntimeEntry(entry).applying(to: loaded)
        XCTAssertEqual(restored.members, entry.members)
        XCTAssertEqual(restored.memberPatterns.first?.lastSeenAt, entry.memberPatterns.first?.lastSeenAt)
        let notes = url.deletingLastPathComponent().appendingPathComponent("README.md")
        try "My own notes\n".write(to: notes, atomically: true, encoding: .utf8)
        var renamed = entry
        renamed.name = "New Name"
        store.save([renamed])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(try yamlURL().deletingLastPathComponent().lastPathComponent, "new-name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: yamlURL().deletingLastPathComponent().appendingPathComponent("README.md")), "My own notes\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".gitignore")), ".state/\n.DS_Store\n")
    }

    func testTransientChangesDoNotRewriteYAML() throws {
        var entry = project()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false))
        let url = try yamlURL()
        let before = try Data(contentsOf: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        entry.members = []
        entry.pendingDesktopRemoval = true
        entry.memberPatterns[0].lastSeenAt = Date()
        store.save([entry])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
    }

    func testExternalEditsWinConflictsAndMergeIndependentChanges() throws {
        let entry = project()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false))
        let url = try yamlURL()
        let text = try String(contentsOf: url).replacingOccurrences(of: "name: Research", with: "# User heading\nname: External # Keep this comment") + "notesCategory: experiments\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        var local = entry
        local.name = "App rename"
        local.isClosed = true
        store.save([local])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(store.entries.first?.name, "External")
        XCTAssertEqual(store.entries.first?.isClosed, true)
        let result = try String(contentsOf: yamlURL())
        XCTAssertTrue(result.contains("# User heading\nname: External # Keep this comment"))
        XCTAssertTrue(result.contains("notesCategory: experiments"))
        store.save([local])
        XCTAssertEqual(try String(contentsOf: yamlURL()), result)
    }

    func testChangedFieldKeepsCommentsAndBlockScalarContentIsNotAComment() throws {
        let entry = project()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false))
        let url = try yamlURL()
        let text = try String(contentsOf: url).replacingOccurrences(of: "name: Research", with: "name: Research # explanation")
        try text.write(to: url, atomically: true, encoding: .utf8)
        var renamed = entry
        renamed.name = "Updated"
        store.save([renamed])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        let result = try String(contentsOf: yamlURL())
        XCTAssertTrue(result.contains("# explanation\nname: Updated"))
        let block = result.replacingOccurrences(of: "name: Updated", with: "name: |\n  # This is the actual title\n  More text")
        let (_, node) = try ProjectYAML.parse(block)
        var desired = node
        desired["name"] = Node("Fresh")
        let updated = try ProjectYAML.updating(block, from: node, to: desired)
        XCTAssertFalse(updated.contains("# This is the actual title"))
        XCTAssertTrue(updated.contains("# explanation"))
    }

    func testInvalidYAMLPreservesFileAndLastValidStateIncludingAfterRestart() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let recovery = try JSONDecoder().decode(ProjectFileRecovery.self, from: JSONEncoder().encode(store.recovery))
        let url = try yamlURL()
        let invalid = "schemaVersion: 1\nname: [unfinished\n"
        try invalid.write(to: url, atomically: true, encoding: .utf8)
        store.save([project("New name")])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(store.entries.first?.name, "Research")
        XCTAssertEqual(try String(contentsOf: url), invalid)
        let restarted = ProjectFileStore(root: root, recovery: recovery)
        XCTAssertFalse(restarted.load(legacy: [], migrated: true))
        XCTAssertEqual(restarted.entries.first?.name, "Research")
    }

    func testExcessiveNestingFailsBeforeRecursiveComposition() {
        let texts = ["notes: " + String(repeating: "[", count: 1_001) + "value" + String(repeating: "]", count: 1_001) + "\n",
                     "notes:\n  " + String(repeating: "- ", count: 40) + "value\n"]
        for text in texts {
            XCTAssertThrowsError(try ProjectYAML.parseNode(text)) { error in
                guard case let ProjectFileError.invalid(problem) = error else { return XCTFail("Expected complexity error, got \(error)") }
                XCTAssertEqual(problem, "YAML is too complex to parse")
            }
        }
    }

    func testBracketsInStringsAndBlockTextDoNotCountAsNesting() throws {
        let brackets = String(repeating: "[", count: 100)
        let text = "quoted: '\(brackets)'\nliteral: |\n  \(brackets)\nnotes: {empty: [], text: OK}\n"
        XCTAssertEqual(try ProjectYAML.parseNode(text)["quoted"]?.string, brackets)
    }

    func testAliasEditsPreserveFileAndLastValidProject() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let url = try yamlURL()
        let text = try String(contentsOf: url) + "notes: &notes [*notes]\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        store.save([project("Changed")])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(store.entries.first?.name, "Research")
        XCTAssertEqual(try String(contentsOf: url), text)
    }

    func testQuotedHashesAndDoubledApostrophesAreNotComments() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let text = try String(contentsOf: yamlURL()).replacingOccurrences(of: "name: Research", with: "name: 'it''s # a title' # user comment")
        let (_, node) = try ProjectYAML.parse(text)
        var desired = node
        desired["name"] = Node("Renamed")
        let updated = try ProjectYAML.updating(text, from: node, to: desired)
        XCTAssertTrue(updated.contains("# user comment"))
        XCTAssertFalse(updated.contains("# a title"))
    }

    func testFixingInvalidFileResumesMergeWithoutLosingAppChanges() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let url = try yamlURL()
        let valid = try String(contentsOf: url)
        try "invalid: [".write(to: url, atomically: true, encoding: .utf8)
        var local = project()
        local.isClosed = true
        store.save([local])
        XCTAssertFalse(store.errors.isEmpty)
        try valid.replacingOccurrences(of: "name: Research", with: "name: Fixed").write(to: url, atomically: true, encoding: .utf8)
        store.save([local])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(store.entries.first?.name, "Fixed")
        XCTAssertEqual(store.entries.first?.isClosed, true)
    }

    func testStartupRecoveryDoesNotOverwriteTheUsersRepair() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let recovery = store.recovery
        let url = try yamlURL()
        let valid = try String(contentsOf: url)
        try "name: [invalid".write(to: url, atomically: true, encoding: .utf8)
        let restarted = ProjectFileStore(root: root, recovery: recovery)
        XCTAssertFalse(restarted.load(legacy: [], migrated: true))
        restarted.acceptInitialSnapshot(restarted.entries)
        var pending = project()
        pending.isClosed = true
        try valid.replacingOccurrences(of: "name: Research", with: "name: Repaired").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(restarted.load(legacy: [], migrated: true, preservingBaseline: true))
        restarted.save([pending])
        XCTAssertTrue(restarted.errors.isEmpty, restarted.errors.description)
        XCTAssertEqual(restarted.entries.first?.name, "Repaired")
        XCTAssertEqual(restarted.entries.first?.isClosed, true)
    }

    func testStrictValidationRejectsPartialAndFutureDocuments() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let text = try String(contentsOf: yamlURL())
        for invalid in [text.replacingOccurrences(of: "schemaVersion: 1", with: "schemaVersion: 99"),
                        text + "name: duplicate\n", text.replacingOccurrences(of: "kind: custom", with: "kind: invalid"),
                        text.replacingOccurrences(of: "homeSpaceUuid: desktop-1", with: "homeSpaceUuid: []"),
                        text.replacingOccurrences(of: "isClosed: false", with: "isClosed: nonsense"),
                        text + "---\nname: second\n"] {
            XCTAssertThrowsError(try ProjectYAML.parse(invalid), invalid)
        }
    }

    func testArchiveDeleteAndRelaunchKeepProjectFolderAndUserFiles() throws {
        var entry = project()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false))
        let url = try yamlURL()
        entry.isClosed = true
        store.save([entry])
        XCTAssertEqual(store.entries.first?.isClosed, true)
        store.save([])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.directory(for: "stable-id"), url.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("README.md").path))
        let restarted = ProjectFileStore(root: root)
        XCTAssertTrue(restarted.load(legacy: [project()], migrated: false))
        XCTAssertTrue(restarted.entries.isEmpty)
        XCTAssertEqual(restarted.records.count, 1)
    }

    func testFolderRenameIsRecognizedAndMissingFilesAreNotRecreated() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let original = try yamlURL().deletingLastPathComponent()
        let moved = store.projectsDirectory.appendingPathComponent("my-notes", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        store.save([project()])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(store.records.keys.sorted(), ["research"])
        XCTAssertEqual(store.directory(for: "stable-id"), original)
        XCTAssertNil(store.directory(for: "unknown-id"))
        let url = original.appendingPathComponent("project.yaml")
        try FileManager.default.removeItem(at: url)
        store.save([project()])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.entries.count, 1)
    }

    func testMigrationDoesNotOverwriteExistingFilesOrReimportAfterCompletion() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let url = try yamlURL()
        let external = try String(contentsOf: url).replacingOccurrences(of: "name: Research", with: "name: Edited")
        try external.write(to: url, atomically: true, encoding: .utf8)
        let restarted = ProjectFileStore(root: root)
        XCTAssertTrue(restarted.load(legacy: [project("Old defaults")], migrated: true))
        XCTAssertEqual(restarted.entries.first?.name, "Edited")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(restarted.directory(for: "stable-id")).appendingPathComponent("project.yaml")), external)
        XCTAssertEqual(restarted.records.count, 1)
    }

    func testDuplicateIdsAreRejectedWithoutOverwritingEitherFile() throws {
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let url = try yamlURL()
        let duplicate = store.projectsDirectory.appendingPathComponent("duplicate")
        try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: url, to: duplicate.appendingPathComponent("project.yaml"))
        let original = try Data(contentsOf: url)
        store.save([project("New")])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testBootFolderAndDiagnosticEncoding() throws {
        let boot = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProjectDiagnosticSnapshot.bootFolder(boot), "1970-01-01T00-00-00Z")
        XCTAssertLessThanOrEqual(ProjectDiagnosticSnapshot.bootDate(), Date())
        let snapshot = ProjectDiagnosticSnapshot(bootedAt: boot, appVersion: "test", bundleIdentifier: "test", activeProjectId: "stable-id",
            autoMinimizedWindows: [identity], projects: [ProjectRuntimeEntry(project())], windows: [])
        let decoded = try JSONDecoder().decode(ProjectDiagnosticSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.projects.first?.members, [identity])
        XCTAssertEqual(decoded.bootedAt, boot)
    }

    func testFilesystemObserverSeesAtomicEditorSave() throws {
        // macOS excludes the per-user temporary directory from FSEvents on the test host.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".alt-tab-observer-test-" + UUID().uuidString)
        store = ProjectFileStore(root: root)
        XCTAssertTrue(store.load(legacy: [project()], migrated: false))
        let url = try yamlURL()
        let changed = expectation(description: "YAML changed")
        changed.assertForOverFulfill = false
        let observer = try ProjectDirectoryObserver(root: root, queue: DispatchQueue(label: "project-file-test")) { changed.fulfill() }
        try (String(contentsOf: url) + "# atomic editor save\n").write(to: url, atomically: true, encoding: .utf8)
        withExtendedLifetime(observer) { wait(for: [changed], timeout: 5) }
    }

    private func desktop(_ name: String = "Research") -> ProjectEntry {
        ProjectEntry(id: "desktop-1", kind: "desktop", spaceUuid: "space-1", homeSpaceUuid: "space-1", name: name,
            autoName: nil, linkedProjectIds: ["stable-id"])
    }

    private func legacyFolder(_ entry: ProjectEntry, folder: String) throws -> URL {
        let directory = store.projectsDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = try ProjectYAML.render(ProjectFileDocument(entry: entry, order: 0).node())
        try ("# My desktop settings\n" + text + "notesCategory: personal\n").write(to: directory.appendingPathComponent("project.yaml"), atomically: true, encoding: .utf8)
        try "Keep my notes exactly\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return directory
    }

    func testFreshImportSeparatesSameNamedProjectsAndDesktops() throws {
        XCTAssertTrue(store.load(legacy: [project(), desktop()], migrated: false), store.errors.description)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.desktopRecords.count, 1)
        XCTAssertEqual(store.entries.map(\.kind), ["custom", "desktop"])
        XCTAssertNil(store.directory(for: desktop().id))
        let parsed = try ProjectDesktopDocument.parse(String(contentsOf: store.desktopsFile))
        XCTAssertEqual(parsed.node["schemaVersion"]?.int, 2)
        XCTAssertEqual(parsed.documents[desktop().id]?.entry.linkedProjectIds, ["stable-id"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.migrationDirectory.path))
        let restarted = ProjectFileStore(root: root)
        XCTAssertTrue(restarted.load(legacy: [project(), desktop()], migrated: false), restarted.errors.description)
        XCTAssertEqual(restarted.entries.count, 2)
        XCTAssertEqual(restarted.records.count, 1)
    }

    func testDesktopFolderMigrationPreservesEveryFileAndCustomIdsWithDesktopPrefix() throws {
        let old = try legacyFolder(desktop(), folder: "research--old")
        var custom = project()
        custom.id = "desktop-archived-project"
        custom.isClosed = true
        let customFolder = try legacyFolder(custom, folder: "research--custom")
        let yaml = try Data(contentsOf: old.appendingPathComponent("project.yaml"))
        let readme = try Data(contentsOf: old.appendingPathComponent("README.md"))
        let extra = old.appendingPathComponent("my-research")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: false)
        try Data([1, 2, 3]).write(to: extra.appendingPathComponent("attachment.bin"))
        let oldCache = ProjectFileRecovery(projects: ["research--old": ProjectFileDocument(entry: desktop(), order: 0)], desktops: [:])
        XCTAssertTrue(store.load(legacy: [], migrated: true), store.errors.description)
        XCTAssertEqual(store.records.keys.sorted(), ["research"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: customFolder.path))
        XCTAssertEqual(store.entries.first(where: { $0.kind == "custom" })?.id, custom.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        let backup = store.migrationDirectory.appendingPathComponent(old.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("project.yaml")), yaml)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("README.md")), readme)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("my-research/attachment.bin")), Data([1, 2, 3]))
        let text = try String(contentsOf: store.desktopsFile)
        XCTAssertTrue(text.contains("notesCategory: personal"))
        let restarted = ProjectFileStore(root: root, recovery: oldCache)
        XCTAssertTrue(restarted.load(legacy: [], migrated: true), restarted.errors.description)
        XCTAssertEqual(restarted.entries.count, 2)
        XCTAssertEqual(try String(contentsOf: store.desktopsFile), text)
    }

    func testInterruptedMigrationKeepsCollectionEditsAndDoesNotOverwriteBackup() throws {
        let old = try legacyFolder(desktop(), folder: "research--old")
        XCTAssertTrue(store.load(legacy: [], migrated: true), store.errors.description)
        let backup = store.migrationDirectory.appendingPathComponent(old.lastPathComponent)
        try FileManager.default.copyItem(at: backup, to: old)
        try "A newer note\n".write(to: old.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let text = try String(contentsOf: store.desktopsFile).replacingOccurrences(of: "name: Research", with: "name: External")
        try text.write(to: store.desktopsFile, atomically: true, encoding: .utf8)
        let restarted = ProjectFileStore(root: root, recovery: store.recovery)
        XCTAssertTrue(restarted.load(legacy: [], migrated: true), restarted.errors.description)
        XCTAssertEqual(restarted.entries.count, 1)
        XCTAssertEqual(restarted.entries.first?.name, "External")
        XCTAssertTrue(restarted.records.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at: store.migrationDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("README.md")), "Keep my notes exactly\n")
        XCTAssertTrue(try backups.contains { try String(contentsOf: $0.appendingPathComponent("README.md")) == "A newer note\n" })
    }

    func testDesktopEditsMergeByFieldAndPreserveNestedComments() throws {
        let entry = desktop()
        var another = desktop("Second")
        another.id = "desktop-2"
        another.spaceUuid = "space-2"
        another.homeSpaceUuid = "space-2"
        XCTAssertTrue(store.load(legacy: [entry, another], migrated: false), store.errors.description)
        let text = try String(contentsOf: store.desktopsFile)
            .replacingOccurrences(of: "    name: Research", with: "    # My heading\n    name: External # My name comment\n    personalNote: 'keep  spacing'")
            .replacingOccurrences(of: "    name: Second", with: "    name: 'Second' # untouched") + "category: desktops\n"
        try text.write(to: store.desktopsFile, atomically: true, encoding: .utf8)
        var local = entry
        local.name = "App rename"
        local.linkedProjectIds = ["new-project"]
        store.save([local, another])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(store.desktopRecords[entry.id]?.document.entry.name, "External")
        XCTAssertEqual(store.desktopRecords[entry.id]?.document.entry.linkedProjectIds, ["new-project"])
        let result = try String(contentsOf: store.desktopsFile)
        XCTAssertTrue(result.contains("    # My heading\n    name: External # My name comment\n    personalNote: 'keep  spacing'"))
        XCTAssertTrue(result.contains("    name: 'Second' # untouched"))
        XCTAssertTrue(result.contains("category: desktops"))
        store.save([local, another])
        XCTAssertEqual(try String(contentsOf: store.desktopsFile), result)
        var accepted = try XCTUnwrap(store.entries.first)
        accepted.name = "A later rename"
        store.acceptInitialSnapshot(store.entries)
        store.save([accepted, another])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertTrue(try String(contentsOf: store.desktopsFile).contains("    # My name comment\n    name: A later rename"))
    }

    func testDesktopTransientChangesAndTombstonesSurviveRestart() throws {
        let entry = desktop()
        XCTAssertTrue(store.load(legacy: [entry], migrated: false))
        let before = try Data(contentsOf: store.desktopsFile)
        let date = try store.desktopsFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        var runtime = entry
        runtime.members = [identity]
        runtime.pendingDesktopRemoval = true
        store.save([runtime])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertEqual(try Data(contentsOf: store.desktopsFile), before)
        XCTAssertEqual(try store.desktopsFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date)
        store.save([])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        XCTAssertTrue(store.entries.isEmpty)
        let restarted = ProjectFileStore(root: root)
        XCTAssertTrue(restarted.load(legacy: [entry], migrated: false))
        XCTAssertTrue(restarted.entries.isEmpty)
        XCTAssertTrue(restarted.records.isEmpty)
    }

    func testInvalidDesktopFileBlocksMigrationAndRetainsRecovery() throws {
        let old = try legacyFolder(desktop(), folder: "research--old")
        let future = "schemaVersion: 99\ndesktops: {}\n"
        try future.write(to: store.desktopsFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.load(legacy: [], migrated: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(try String(contentsOf: store.desktopsFile), future)
        try FileManager.default.removeItem(at: store.desktopsFile)
        XCTAssertTrue(store.load(legacy: [], migrated: true), store.errors.description)
        let recovery = try XCTUnwrap(ProjectFileRecovery.decode(JSONEncoder().encode(store.recovery)))
        let valid = try String(contentsOf: store.desktopsFile)
        for invalid in ["desktops: [unfinished", future,
                        valid.replacingOccurrences(of: "kind: desktop", with: "kind: custom"),
                        valid.replacingOccurrences(of: "  desktop-1:", with: "  wrong-key:"),
                        "schemaVersion: 2\ndesktops: {}\n"] {
            try invalid.write(to: store.desktopsFile, atomically: true, encoding: .utf8)
            let restarted = ProjectFileStore(root: root, recovery: recovery)
            XCTAssertFalse(restarted.load(legacy: [], migrated: true), invalid)
            restarted.save([desktop("App rename")])
            XCTAssertEqual(restarted.entries.first?.name, "Research")
            XCTAssertEqual(try String(contentsOf: store.desktopsFile), invalid)
        }
        try FileManager.default.removeItem(at: store.desktopsFile)
        let restarted = ProjectFileStore(root: root, recovery: recovery)
        XCTAssertFalse(restarted.load(legacy: [], migrated: true))
        XCTAssertEqual(restarted.entries.first?.name, "Research")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.desktopsFile.path))
        try valid.replacingOccurrences(of: "name: Research", with: "name: Repaired").write(to: store.desktopsFile, atomically: true, encoding: .utf8)
        restarted.acceptInitialSnapshot(restarted.entries)
        XCTAssertTrue(restarted.load(legacy: [], migrated: true, preservingBaseline: true))
        var pending = desktop()
        pending.linkedProjectIds = ["another-project"]
        restarted.save([pending])
        XCTAssertTrue(restarted.errors.isEmpty, restarted.errors.description)
        XCTAssertEqual(restarted.entries.first?.name, "Repaired")
        XCTAssertEqual(restarted.entries.first?.linkedProjectIds, ["another-project"])
    }

    func testLegacyRecoveryCacheLoadsVersionOneFolders() throws {
        let original = ["research--old": ProjectFileDocument(entry: desktop(), order: 0)]
        let recovery = try XCTUnwrap(ProjectFileRecovery.decode(JSONEncoder().encode(original)))
        XCTAssertEqual(recovery.schemaVersion, 2)
        XCTAssertEqual(recovery.projects.keys.sorted(), ["research--old"])
        XCTAssertTrue(recovery.desktops.isEmpty)
    }

    func testNestedYAMLAdditionsAtSameBoundaryStayInTheirMappings() throws {
        let text = "desktops:\n  first:\n    name: First\nschemaVersion: 2\n"
        let node = try ProjectYAML.parseNode(text)
        var target = node
        target["desktops"]?["first"]?["note"] = Node("A note")
        target["desktops"]?["second"] = Node([(Node("name"), Node("Second"))])
        XCTAssertEqual(try ProjectYAML.parseNode(ProjectYAML.updating(text, from: node, to: target)), target)
    }

    func testFilesystemObserverSeesAtomicDesktopFileSave() throws {
        // macOS excludes the per-user temporary directory from FSEvents on the test host.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".alt-tab-observer-test-" + UUID().uuidString)
        store = ProjectFileStore(root: root)
        XCTAssertTrue(store.load(legacy: [desktop()], migrated: false))
        let changed = expectation(description: "Desktop YAML changed")
        changed.assertForOverFulfill = false
        let observer = try ProjectDirectoryObserver(root: root, queue: DispatchQueue(label: "desktop-file-test")) { changed.fulfill() }
        try (String(contentsOf: store.desktopsFile) + "# atomic desktop edit\n").write(to: store.desktopsFile, atomically: true, encoding: .utf8)
        withExtendedLifetime(observer) { wait(for: [changed], timeout: 5) }
    }


    func testNamedFoldersMigrateAndFollowRenamesWithoutLosingNotes() throws {
        let original = try legacyFolder(project(), folder: "research--1234abcd")
        XCTAssertTrue(store.load(legacy: [], migrated: true), store.errors.description)
        let initial = try XCTUnwrap(store.directory(for: "stable-id"))
        XCTAssertEqual(initial.lastPathComponent, "research")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        store.save([project("New Research")])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        let renamed = try XCTUnwrap(store.directory(for: "stable-id"))
        XCTAssertEqual(renamed.lastPathComponent, "new-research")
        XCTAssertEqual(try String(contentsOf: renamed.appendingPathComponent("README.md")), "Keep my notes exactly\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: initial.path))
        let restarted = ProjectFileStore(root: root, recovery: store.recovery)
        XCTAssertTrue(restarted.load(legacy: [], migrated: true), restarted.errors.description)
        XCTAssertEqual(restarted.records.count, 1)
        XCTAssertEqual(restarted.directory(for: "stable-id"), renamed)
    }

    func testDuplicateProjectNamesAreRejectedIncludingArchivedAndDeletedProjects() throws {
        let first = project()
        var second = project("Personal")
        second.id = "second-id"
        second.isClosed = true
        XCTAssertTrue(store.load(legacy: [first, second], migrated: false), store.errors.description)
        let firstURL = try XCTUnwrap(store.directory(for: first.id)).appendingPathComponent("project.yaml")
        let before = try Data(contentsOf: firstURL)
        store.save([project("  PERSONAL  "), second])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: firstURL), before)
        XCTAssertEqual(store.entries.first?.name, "Research")
        store.save([first])
        XCTAssertTrue(store.errors.isEmpty, store.errors.description)
        store.save([project("Personal")])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: firstURL), before)
    }

    func testExternalDuplicateNameKeepsLastValidProjectsAndOriginalText() throws {
        var second = project("Personal")
        second.id = "second-id"
        XCTAssertTrue(store.load(legacy: [project(), second], migrated: false))
        let url = try XCTUnwrap(store.directory(for: second.id)).appendingPathComponent("project.yaml")
        let conflict = try String(contentsOf: url).replacingOccurrences(of: "name: Personal", with: "name: RESEARCH")
        try conflict.write(to: url, atomically: true, encoding: .utf8)
        store.save([project(), second])
        XCTAssertFalse(store.errors.isEmpty)
        XCTAssertEqual(store.entries.map(\.name), ["Research", "Personal"])
        XCTAssertEqual(try String(contentsOf: url), conflict)
    }

    func testFolderCollisionNeverOverwritesUserFiles() throws {
        let old = try legacyFolder(project(), folder: "research--1234abcd")
        let conflicting = store.projectsDirectory.appendingPathComponent("research")
        try FileManager.default.createDirectory(at: conflicting, withIntermediateDirectories: false)
        try "Unrelated user notes\n".write(to: conflicting.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.load(legacy: [], migrated: true))
        XCTAssertEqual(try String(contentsOf: conflicting.appendingPathComponent("README.md")), "Unrelated user notes\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("project.yaml").path))
    }

    func testUnnamedLegacyProjectsReceiveDistinctPermanentNames() throws {
        var first = project()
        first.name = nil
        first.autoName = "Finder"
        var second = first
        second.id = "second-id"
        XCTAssertTrue(store.load(legacy: [first, second], migrated: false), store.errors.description)
        XCTAssertEqual(store.entries.map(\.name), ["Finder", "Finder 2"])
        XCTAssertEqual(store.records.keys.sorted(), ["finder", "finder-2"])
    }

}
