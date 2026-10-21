import Foundation
import CoreServices

final class ProjectDirectoryObserver {
    private var stream: FSEventStreamRef?
    private let projectsPath: String
    private let desktopsPath: String
    private let changed: () -> Void
    private let snapshotsChanged: () -> Void

    init(root: URL, queue: DispatchQueue, snapshotsChanged: @escaping () -> Void = {}, changed: @escaping () -> Void) throws {
        projectsPath = root.appendingPathComponent("projects").resolvingSymlinksInPath().path
        desktopsPath = root.appendingPathComponent("desktops.yaml").resolvingSymlinksInPath().path
        self.changed = changed
        self.snapshotsChanged = snapshotsChanged
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let observer = Unmanaged<ProjectDirectoryObserver>.fromOpaque(info).takeUnretainedValue()
            let names = unsafeBitCast(paths, to: NSArray.self) as! [String]
            var projectsChanged = false
            var archivesChanged = false
            for index in 0..<count {
                let path = names[index]
                let rescanning = flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                let directory = flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
                let projectPath = path == observer.projectsPath || path.hasPrefix(observer.projectsPath + "/")
                let archivePath = projectPath && path.dropFirst(observer.projectsPath.count + 1).split(separator: "/").dropFirst().first == "archives"
                if rescanning || archivePath && (directory || path.hasSuffix("/README.md") || path.hasSuffix("/snapshot.json")) { archivesChanged = true }
                if rescanning || path == observer.desktopsPath || projectPath && !archivePath && (directory || path.hasSuffix("/project.yaml")) { projectsChanged = true }
            }
            if projectsChanged { observer.changed() }
            if archivesChanged { observer.snapshotsChanged() }
        }, &context, [root.deletingLastPathComponent().resolvingSymlinksInPath().path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        guard let stream else { throw ProjectFileError.invalid("Could not create the project file observer") }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else { throw ProjectFileError.invalid("Could not start the project file observer") }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
