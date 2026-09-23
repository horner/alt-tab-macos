import Cocoa

/// AppKit models are captured on main; parsing, defaults writes and all file I/O run on queue.
enum ProjectPersistence {
    enum Folder {
        case projects
        case desktops
        case project(String)
        case diagnostics
    }
    static let openProjectsFolderTitle = NSLocalizedString("Open Projects Folder", comment: "Open project storage in Finder")
    static let openProjectFolderTitle = NSLocalizedString("Open Project Folder", comment: "Open one project's files in Finder")
    static let openDiagnosticsFolderTitle = NSLocalizedString("Open Diagnostics Folder", comment: "Open current boot's project diagnostics in Finder")
    private static let queue = DispatchQueue(label: "com.alt-tab.projects.files", qos: .utility)
    private static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".alt-tab-projects", isDirectory: true)
    private static var store: ProjectFileStore?
    static private(set) var projectNames = [String: String]()
    private static var observer: ProjectDirectoryObserver?
    private static var bootedAt = Date.distantPast
    private static var legacy = [ProjectEntry]()
    private static var ready = false
    private static var revision = 0
    private static var reportedErrors = [String]()
    private static var lastRecovery: Data?
    private static var pendingSnapshot: DispatchWorkItem?
    private static var isFinishing = false
    private static var apply: (([ProjectEntry], Bool) -> Void)?
    private static var snapshotHistories = [String: [ProjectSnapshotHistory.Entry]]()
    private static var historyDirectories = [String: URL]()
    private static var pendingHistoryRefresh: DispatchWorkItem?

    static func start(legacy entries: [ProjectEntry], apply: @escaping ([ProjectEntry], Bool) -> Void) {
        self.apply = apply
        queue.async {
            legacy = entries
            bootedAt = ProjectDiagnosticSnapshot.bootDate()
            let recovery = UserDefaults.standard.data(forKey: "projectsFileRecovery").flatMap {
                ProjectFileRecovery.decode($0)
            } ?? ProjectFileRecovery(projects: [:], desktops: [:])
            let files = ProjectFileStore(root: root, recovery: recovery)
            store = files
            let migrated = UserDefaults.standard.bool(forKey: "projectsFileStoreMigrated")
            ready = files.load(legacy: entries, migrated: migrated)
            if ready { UserDefaults.standard.set(true, forKey: "projectsFileStoreMigrated") }
            let runtime = UserDefaults.standard.data(forKey: "projectsRuntime").flatMap {
                try? JSONDecoder().decode([ProjectRuntimeEntry].self, from: $0)
            } ?? entries.map(ProjectRuntimeEntry.init)
            let knownIds = Set(files.documents.map { $0.entry.id })
            let fallback = !ready && !migrated ? entries.filter { !knownIds.contains($0.id) } : []
            let loaded = restoringRuntime(runtime, to: files.entries + fallback)
            files.acceptInitialSnapshot(loaded)
            saveRecovery(files)
            report(files.errors)
            do {
                observer = try ProjectDirectoryObserver(root: root, queue: queue, snapshotsChanged: { scheduleHistoryRefresh() }) {
                    DispatchQueue.main.async { scheduleSnapshot() }
                }
            } catch {
                report(files.errors + [error.localizedDescription])
            }
            let names = savedNames(files)
            loadSnapshotHistory()
            DispatchQueue.main.async {
                projectNames = names
                apply(loaded, true)
                scheduleSnapshot()
            }
        }
    }

    static func scheduleSnapshot() {
        guard !isFinishing else { return }
        revision += 1
        guard pendingSnapshot == nil else { return }
        let work = DispatchWorkItem {
            pendingSnapshot = nil
            Projects.persistSnapshot()
        }
        pendingSnapshot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func save(_ entries: [ProjectEntry], windows: [ProjectDiagnosticSnapshot.Window], desktops: [ProjectDiagnosticSnapshot.Desktop], activeId: String?) {
        revision += 1
        let submitted = revision
        let autoMinimized = CachedUserDefaults.json("projectsAutoMinimizedWindows", [ProjectWindowIdentity].self)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let bundle = App.bundleIdentifier
        queue.async {
            guard let files = store else { return }
            if !ready {
                ready = files.load(legacy: legacy, migrated: UserDefaults.standard.bool(forKey: "projectsFileStoreMigrated"), preservingBaseline: true)
                if ready { UserDefaults.standard.set(true, forKey: "projectsFileStoreMigrated") }
            }
            if ready { files.save(entries) }
            let runtime = entries.map(ProjectRuntimeEntry.init)
            if let data = try? JSONEncoder().encode(runtime) { UserDefaults.standard.set(data, forKey: "projectsRuntime") }
            saveRecovery(files)
            let names = savedNames(files)
            if snapshotDirectories() != historyDirectories { loadSnapshotHistory() }
            DispatchQueue.main.async { projectNames = names }
            let resulting = restoringRuntime(runtime, to: files.entries)
            let requested = try? entries.map { try ProjectFileDocument(entry: $0, order: 0).node() }
            let actual = try? resulting.map { try ProjectFileDocument(entry: $0, order: 0).node() }
            if ready, files.errors.isEmpty, requested != actual {
                DispatchQueue.main.async {
                    guard revision == submitted else { return }
                    apply?(resulting, false)
                }
            }
            var snapshot = ProjectDiagnosticSnapshot(bootedAt: bootedAt, appVersion: version, bundleIdentifier: bundle,
                activeProjectId: activeId, autoMinimizedWindows: autoMinimized, projects: runtime, windows: windows)
            snapshot.desktops = desktops
            snapshot.errors = files.errors
            do {
                let directory = root.appendingPathComponent(".state").appendingPathComponent(ProjectDiagnosticSnapshot.bootFolder(bootedAt), isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try files.write(encoder.encode(snapshot), to: directory.appendingPathComponent("state.json"))
                report(files.errors)
            } catch {
                report(files.errors + [error.localizedDescription])
            }
        }
    }

    static func archiveDirectories(for ids: [String], completion: @escaping (Result<[URL], Error>) -> Void) {
        Projects.persistSnapshot()
        queue.async {
            let urls = ids.compactMap { store?.directory(for: $0) }
            let result: Result<[URL], Error> = ready && store?.errors.isEmpty == true && urls.count == ids.count && !urls.isEmpty
                ? .success(urls) : .failure(ProjectFileError.invalid("Project folders could not be saved. No windows were closed."))
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func snapshotHistory(for projectId: String) -> [ProjectSnapshotHistory.Entry] {
        snapshotHistories[projectId] ?? []
    }

    static func refreshSnapshotHistory() {
        queue.async { scheduleHistoryRefresh() }
    }

    private static func scheduleHistoryRefresh() {
        pendingHistoryRefresh?.cancel()
        let work = DispatchWorkItem { loadSnapshotHistory() }
        pendingHistoryRefresh = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static func snapshotDirectories() -> [String: URL] {
        guard let files = store else { return [:] }
        return Dictionary(uniqueKeysWithValues: files.documents.filter { $0.entry.kind == "custom" && !$0.isDeleted }.compactMap { document in
            files.directory(for: document.entry.id).map { (document.entry.id, $0) }
        })
    }

    private static func loadSnapshotHistory() {
        pendingHistoryRefresh?.cancel()
        pendingHistoryRefresh = nil
        historyDirectories = snapshotDirectories()
        let histories = historyDirectories.mapValues { ProjectSnapshotHistory.load(in: $0) }
        DispatchQueue.main.async { snapshotHistories = histories }
    }

    static func openSnapshot(_ entry: ProjectSnapshotHistory.Entry) {
        guard !isFinishing else { return }
        DispatchQueue.main.async {
            guard !isFinishing else { return }
            SnapshotViewerWindow.open(entry)
        }
    }

    static func openFolder(_ folder: Folder) {
        guard !isFinishing else { return }
        DispatchQueue.main.async {
            Projects.persistSnapshot()
            queue.async {
                let url: URL?
                switch folder {
                case .desktops:
                    guard let file = store?.desktopsFile else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    return
                case .projects: url = root
                case .project(let id): url = store?.directory(for: id)
                case .diagnostics: url = root.appendingPathComponent(".state").appendingPathComponent(ProjectDiagnosticSnapshot.bootFolder(bootedAt), isDirectory: true)
                }
                guard let url, NSWorkspace.shared.open(url) else {
                    DispatchQueue.main.async {
                        ProjectRestoreNotice.showSummary(title: NSLocalizedString("Couldn’t open folder", comment: "Project folder open failure"),
                            rows: [.init(title: NSLocalizedString("The folder may have been moved or could not be saved.", comment: "Project folder open failure explanation"), detail: url?.path ?? root.path)])
                    }
                    return
                }
            }
        }
    }

    private static func restoringRuntime(_ runtime: [ProjectRuntimeEntry], to entries: [ProjectEntry]) -> [ProjectEntry] {
        entries.map { entry in runtime.first { $0.id == entry.id }?.applying(to: entry) ?? entry }
    }

    private static func savedNames(_ files: ProjectFileStore) -> [String: String] {
        Dictionary(uniqueKeysWithValues: files.documents.filter { $0.entry.kind == "custom" }.compactMap { document in
            document.entry.name.map { (document.entry.id, $0) }
        })
    }

    private static func saveRecovery(_ files: ProjectFileStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(files.recovery), data != lastRecovery else { return }
        lastRecovery = data
        UserDefaults.standard.set(data, forKey: "projectsFileRecovery")
    }

    private static func report(_ errors: [String]) {
        guard errors != reportedErrors else { return }
        reportedErrors = errors
        guard !errors.isEmpty else { return }
        Logger.warning { "Project files: \(errors.joined(separator: "\n"))" }
        DispatchQueue.main.async {
            ProjectRestoreNotice.showSummary(title: NSLocalizedString("Project files need attention", comment: "Project file error"),
                rows: errors.prefix(4).map { .init(title: NSLocalizedString("Keeping the last valid project", comment: "Project file recovery"), detail: $0) })
        }
    }

    static func finishPendingSave(_ completion: @escaping () -> Void) {
        isFinishing = true
        pendingSnapshot?.cancel()
        pendingSnapshot = nil
        Projects.persistSnapshot()
        // UserDefaults writes synchronously deliver main-queue observers. A main-thread queue.sync
        // here deadlocks against that notification; keep the runloop free until the save completes.
        queue.async { DispatchQueue.main.async(execute: completion) }
    }
}
