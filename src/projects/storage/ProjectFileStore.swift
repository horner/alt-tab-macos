import Foundation
import Yams

/// Confined to ProjectPersistence's utility queue; no AppKit objects cross this boundary.
final class ProjectFileStore {
    struct Record {
        var document: ProjectFileDocument
        var text: String
        var node: Node
    }
    let root: URL
    private(set) var records = [String: Record]()
    private(set) var desktopRecords = [String: Record]()
    private var desktopText: String?
    private var desktopNode = ProjectDesktopDocument.empty()
    private var baseline = [String: Node]()
    private(set) var errors = [String]()
    var recovery: ProjectFileRecovery { ProjectFileRecovery(projects: records.mapValues(\.document), desktops: desktopRecords.mapValues(\.document)) }
    var documents: [ProjectFileDocument] {
        records.values.map(\.document).filter { desktopRecords[$0.entry.id] == nil } + desktopRecords.values.map(\.document)
    }
    var entries: [ProjectEntry] {
        documents.filter { !$0.isDeleted }.sorted {
            $0.order == $1.order ? $0.entry.id < $1.entry.id : $0.order < $1.order
        }.map(\.entry)
    }
    var projectsDirectory: URL { root.appendingPathComponent("projects", isDirectory: true) }
    var desktopsFile: URL { root.appendingPathComponent("desktops.yaml") }
    var migrationDirectory: URL { root.appendingPathComponent("migration-backups/v1-desktop-folders", isDirectory: true) }

    init(root: URL, recovery: ProjectFileRecovery = ProjectFileRecovery(projects: [:], desktops: [:])) {
        self.root = root
        for (folder, document) in recovery.projects where URL(fileURLWithPath: folder).lastPathComponent == folder && !folder.hasPrefix(".") {
            guard let node = try? document.node(), let text = try? ProjectYAML.render(node) else { continue }
            records[folder] = Record(document: document, text: text, node: node)
            baseline[document.entry.id] = node
        }
        for (id, document) in recovery.desktops where document.entry.id == id && document.entry.kind == "desktop" {
            guard let node = try? document.node() else { continue }
            desktopRecords[id] = Record(document: document, text: "", node: node)
            baseline[id] = node
        }
    }

    func load(legacy: [ProjectEntry], migrated: Bool, preservingBaseline: Bool = false) -> Bool {
        do {
            try prepareDirectories()
            read()
            guard errors.isEmpty else { return false }
            try migrateDesktopFolders()
            try nameUnnamedProjects()
            if !migrated {
                for (order, entry) in legacy.enumerated() where !documents.contains(where: { $0.entry.id == entry.id }) {
                    try create(ProjectFileDocument(entry: entry, order: order))
                }
                read()
            }
            try canonicalizeDirectories()
            if !preservingBaseline {
                baseline = try Dictionary(uniqueKeysWithValues: documents.map { ($0.entry.id, try $0.node()) })
            }
            return errors.isEmpty
        } catch {
            errors.append(error.localizedDescription)
            return false
        }
    }

    func directory(for projectId: String) -> URL? {
        guard let folder = records.first(where: { $0.value.document.entry.id == projectId })?.key else { return nil }
        return projectsDirectory.appendingPathComponent(folder, isDirectory: true)
    }

    func acceptInitialSnapshot(_ entries: [ProjectEntry]) {
        for (order, entry) in entries.enumerated() { baseline[entry.id] = try? ProjectFileDocument(entry: entry, order: order).node() }
    }

    func read() {
        errors = []
        do { try readDesktops() } catch { errors.append("\(desktopsFile.path): \(error.localizedDescription)") }
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).sorted { $0.lastPathComponent < $1.lastPathComponent }
            var next = [String: Record]()
            var owners = [String: String]()
            for folder in folders where !folder.lastPathComponent.hasPrefix(".") {
                let name = folder.lastPathComponent
                let url = folder.appendingPathComponent("project.yaml")
                guard FileManager.default.fileExists(atPath: url.path) || records[name] != nil else { continue }
                do {
                    let attributes = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { throw ProjectFileError.invalid("Expected a regular project folder") }
                    try requireRegular(url)
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let (document, node) = try ProjectYAML.parse(text)
                    if document.entry.kind == "custom", ProjectNameResolver.normalized(document.entry.name) == nil,
                       let previous = records[name], ProjectNameResolver.normalized(previous.document.entry.name) != nil {
                        throw ProjectFileError.invalid("Enter a project name")
                    }
                    if let previous = records[name], (previous.document.entry.id != document.entry.id || previous.document.entry.kind != document.entry.kind) {
                        throw ProjectFileError.invalid("Project id and kind are immutable; create a new folder for a new project")
                    }
                    guard owners[document.entry.id] == nil, document.entry.kind == "desktop" || desktopRecords[document.entry.id] == nil else {
                        throw ProjectFileError.invalid("Duplicate project id \(document.entry.id)")
                    }
                    owners[document.entry.id] = name
                    next[name] = Record(document: document, text: text, node: node)
                } catch {
                    errors.append("\(url.path): \(error.localizedDescription)")
                    if let previous = records[name], owners[previous.document.entry.id] == nil {
                        next[name] = previous
                        owners[previous.document.entry.id] = name
                    }
                }
            }
            for (folder, record) in records where next[folder] == nil && owners[record.document.entry.id] == nil {
                // The cache can lag a completed folder move; testDesktopFolderMigrationPreservesEveryFileAndCustomIdsWithDesktopPrefix covers recovery.
                if record.document.entry.kind == "desktop", desktopRecords[record.document.entry.id] != nil { continue }
                next[folder] = record
                errors.append("\(projectsDirectory.appendingPathComponent(folder).path): project.yaml is missing; keeping the last valid project. Set isDeleted: true to remove it.")
            }
            try validateNames(next.values.map(\.document), allowingUnnamed: true)
            records = next
        } catch {
            errors.append("\(projectsDirectory.path): \(error.localizedDescription)")
        }
    }

    private func readDesktops() throws {
        guard FileManager.default.fileExists(atPath: desktopsFile.path) else {
            guard desktopText == nil, desktopRecords.isEmpty else { throw ProjectFileError.invalid("desktops.yaml is missing; keeping the last valid desktops") }
            return
        }
        try requireRegular(desktopsFile)
        let text = try String(contentsOf: desktopsFile, encoding: .utf8)
        let parsed = try ProjectDesktopDocument.parse(text)
        guard desktopRecords.keys.allSatisfy({ parsed.documents[$0] != nil }) else {
            throw ProjectFileError.invalid("A desktop record is missing; set isDeleted: true to remove it")
        }
        acceptDesktops(text, parsed: parsed)
    }

    private func acceptDesktops(_ text: String, parsed: (documents: [String: ProjectFileDocument], node: Node)) {
        desktopRecords = parsed.documents.mapValues { Record(document: $0, text: "", node: parsed.node["desktops"]![$0.entry.id]!) }
        desktopText = text
        desktopNode = parsed.node
    }

    private func saveDesktops(_ node: Node) throws {
        guard desktopText == nil || node != desktopNode else { return }
        let text = try desktopText.map { try ProjectYAML.updating($0, from: desktopNode, to: node) } ?? ProjectYAML.render(node)
        let parsed = try ProjectDesktopDocument.parse(text)
        if let previous = desktopText {
            guard try String(contentsOf: desktopsFile, encoding: .utf8) == previous else { throw ProjectFileError.invalid("desktops.yaml changed during save; retrying on the next filesystem event") }
        } else if FileManager.default.fileExists(atPath: desktopsFile.path) {
            throw ProjectFileError.invalid("desktops.yaml appeared during save; retrying on the next filesystem event")
        }
        try write(Data(text.utf8), to: desktopsFile)
        acceptDesktops(text, parsed: parsed)
    }

    private func migrateDesktopFolders() throws {
        let legacy = records.filter { $0.value.document.entry.kind == "desktop" }
        var target = desktopNode
        for record in legacy.values where desktopRecords[record.document.entry.id] == nil {
            target["desktops"]?[record.document.entry.id] = record.node
        }
        // Commit the complete collection before moving any source folder. Existing collection entries
        // win on retry; the untouched source folders preserve all YAML comments and user files.
        try saveDesktops(target)
        guard !legacy.isEmpty else { return }
        try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (folder, record) in legacy.sorted(by: { $0.key < $1.key }) {
            let source = projectsDirectory.appendingPathComponent(folder, isDirectory: true)
            guard try String(contentsOf: source.appendingPathComponent("project.yaml"), encoding: .utf8) == record.text else {
                throw ProjectFileError.invalid("\(source.path): changed during migration; keeping the source folder")
            }
            let destination = migrationDirectory.appendingPathComponent(folder, isDirectory: true)
            let available = FileManager.default.fileExists(atPath: destination.path) ? migrationDirectory.appendingPathComponent(folder + "--" + UUID().uuidString, isDirectory: true) : destination
            try FileManager.default.moveItem(at: source, to: available)
            records[folder] = nil
        }
    }

    func save(_ entries: [ProjectEntry]) {
        read()
        guard errors.isEmpty else { return }
        do {
            try migrateDesktopFolders()
            try nameUnnamedProjects()
            let incoming = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, ProjectFileDocument(entry: $0.element, order: $0.offset)) })
            try validateIncomingNames(incoming)
            for document in incoming.values.sorted(by: { $0.order < $1.order }) {
                if let folder = records.first(where: { $0.value.document.entry.id == document.entry.id })?.key {
                    guard document.entry.kind == "custom" else { throw ProjectFileError.invalid("Project kind is immutable") }
                    try update(document, folder: folder)
                } else if desktopRecords[document.entry.id] == nil {
                    try create(document)
                    baseline[document.entry.id] = try document.node()
                }
            }
            for (folder, record) in records where incoming[record.document.entry.id] == nil && baseline[record.document.entry.id] != nil && !record.document.isDeleted {
                var deleted = record.document
                deleted.isDeleted = true
                try update(deleted, folder: folder)
            }
            try updateDesktops(incoming)
            try canonicalizeDirectories()
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func target(for requested: ProjectFileDocument, record: Record) throws -> Node {
        guard requested.entry.kind == record.document.entry.kind else { throw ProjectFileError.invalid("Project kind is immutable") }
        let disk = try record.document.node()
        let local = try requested.node()
        let merged = ProjectYAML.merge(base: baseline[requested.entry.id] ?? disk, local: local, disk: disk)
        var target = record.node
        let keys = Set((disk.mapping?.keys.compactMap(\.string) ?? []) + (merged.mapping?.keys.compactMap(\.string) ?? []))
        for key in keys where disk[key] != merged[key] { target.mapping?[key] = merged[key] }
        return target
    }

    private func updateDesktops(_ incoming: [String: ProjectFileDocument]) throws {
        var target = desktopNode
        var submitted = [String: Node]()
        for (id, record) in desktopRecords {
            var requested: ProjectFileDocument
            if let entry = incoming[id] { requested = entry }
            else if baseline[id] != nil && !record.document.isDeleted {
                requested = record.document
                requested.isDeleted = true
            } else { continue }
            target["desktops"]?[id] = try self.target(for: requested, record: record)
            submitted[id] = try requested.node()
        }
        try saveDesktops(target)
        baseline.merge(submitted) { _, local in local }
    }

    private func update(_ requested: ProjectFileDocument, folder: String) throws {
        guard let record = records[folder] else { return }
        let target = try self.target(for: requested, record: record)
        if target != record.node {
            let text = try ProjectYAML.updating(record.text, from: record.node, to: target)
            let (document, node) = try ProjectYAML.parse(text)
            let url = projectsDirectory.appendingPathComponent(folder).appendingPathComponent("project.yaml")
            // An editor may save after read() even on our serial queue. Leave that version intact.
            guard try String(contentsOf: url, encoding: .utf8) == record.text else {
                throw ProjectFileError.invalid("\(url.path): changed during save; retrying on the next filesystem event")
            }
            try write(Data(text.utf8), to: url)
            records[folder] = Record(document: document, text: text, node: node)
        }
        baseline[requested.entry.id] = try requested.node()
    }

    private func create(_ source: ProjectFileDocument) throws {
        var document = source
        if document.entry.kind == "desktop" {
            var target = desktopNode
            target["desktops"]?[document.entry.id] = try document.node()
            try saveDesktops(target)
            return
        }
        if ProjectNameResolver.normalized(document.entry.name) == nil {
            document.entry.name = ProjectNameResolver.available(document.entry.autoName ?? "Project", existing: projectNames)
        }
        try validateNames(documents + [document])
        let folder = Self.slug(document.entry.name!)
        let directory = projectsDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let text = try ProjectYAML.render(document.node())
        let (verified, node) = try ProjectYAML.parse(text)
        try write(Data(text.utf8), to: directory.appendingPathComponent("project.yaml"))
        records[folder] = Record(document: verified, text: text, node: node)
        let readme = "# \(document.entry.name ?? document.entry.autoName ?? "Project")\n\nYour notes go here. AltTab never edits this file.\n"
        try write(Data(readme.utf8), to: directory.appendingPathComponent("README.md"))
    }

    private func prepareDirectories() throws {
        for directory in [root, projectsDirectory, root.appendingPathComponent(".state", isDirectory: true)] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let ignore = root.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: ignore.path) else { return }
        try write(Data(".state/\n.DS_Store\n".utf8), to: ignore)
    }

    func write(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try requireRegular(url)
            if try Data(contentsOf: url) == data { return }
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func requireRegular(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 8 * 1024 * 1024 else {
            throw ProjectFileError.invalid("Expected a regular file no larger than 8 MB")
        }
    }

    private var projectNames: [String] {
        records.values.filter { $0.document.entry.kind == "custom" }.compactMap { ProjectNameResolver.normalized($0.document.entry.name) }
    }

    private func validateNames(_ documents: [ProjectFileDocument], allowingUnnamed: Bool = false) throws {
        var names = [String: String]()
        for document in documents where document.entry.kind == "custom" {
            guard let name = ProjectNameResolver.normalized(document.entry.name) else {
                if allowingUnnamed { continue }
                throw ProjectFileError.invalid("Enter a project name")
            }
            let key = Self.slug(name)
            guard names[key] == nil else { throw ProjectFileError.invalid("Project names must be unique: \(name) and \(names[key]!) use the same folder name (including archived or deleted projects)") }
            names[key] = name
        }
    }

    private func validateIncomingNames(_ incoming: [String: ProjectFileDocument]) throws {
        var candidates = [ProjectFileDocument]()
        for record in records.values {
            guard let requested = incoming[record.document.entry.id] else { candidates.append(record.document); continue }
            candidates.append(try YAMLDecoder().decode(ProjectFileDocument.self, from: target(for: requested, record: record)))
        }
        let known = Set(documents.map { $0.entry.id })
        candidates += incoming.values.filter { !known.contains($0.entry.id) }
        try validateNames(candidates)
    }

    private func nameUnnamedProjects() throws {
        for (folder, record) in records.sorted(by: { $0.key < $1.key }) where record.document.entry.kind == "custom" && ProjectNameResolver.normalized(record.document.entry.name) == nil {
            var named = record.document
            named.entry.name = ProjectNameResolver.available(named.entry.autoName ?? "Project", existing: projectNames)
            try update(named, folder: folder)
        }
    }

    private func canonicalizeDirectories() throws {
        for (folder, record) in records.sorted(by: { $0.key < $1.key }) where record.document.entry.kind == "custom" {
            guard let name = ProjectNameResolver.normalized(record.document.entry.name) else { continue }
            let canonical = Self.slug(name)
            guard folder != canonical else { continue }
            let source = projectsDirectory.appendingPathComponent(folder, isDirectory: true)
            let destination = projectsDirectory.appendingPathComponent(canonical, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ProjectFileError.invalid("\(destination.path) already exists; keeping both folders. Choose a different project name or move the conflicting folder.")
            }
            try FileManager.default.moveItem(at: source, to: destination)
            records[canonical] = record
            records[folder] = nil
        }
    }

    static func slug(_ name: String) -> String { ProjectNameResolver.folderName(name) }
}
