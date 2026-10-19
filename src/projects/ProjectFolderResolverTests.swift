import XCTest

final class ProjectFolderResolverTests: XCTestCase {
    private func window(_ id: String, order: Int, tool: ProjectFolderTool = .terminal, eligible: Bool = true) -> ProjectFolderResolver.WindowCandidate {
        .init(id: id, bundleIdentifier: tool.bundleIdentifier, focusOrder: order, eligible: eligible)
    }

    func testReuseRequiresMembershipAndChoosesMostRecentlyFocusedEligibleWindow() {
        let windows = [window("other-project", order: 0), window("tab", order: 1, eligible: false),
            window("editor", order: 2, tool: .editor), window("recent", order: 3), window("older", order: 4)]
        XCTAssertEqual(ProjectFolderResolver.reusable(windows, members: ["tab", "editor", "recent", "older"], tool: .terminal), "recent")
        XCTAssertNil(ProjectFolderResolver.reusable(windows, members: ["missing"], tool: .terminal))
    }

    func testLaunchRejectsOldWindowsOtherApplicationsAndDiscoveryReadmissions() {
        var launch = ProjectFolderResolver.Launch(projectId: "p", tool: .editor, existingIds: ["old"])
        launch.discover(id: "old", bundleIdentifier: ProjectFolderTool.editor.bundleIdentifier, isNew: true)
        launch.discover(id: "terminal", bundleIdentifier: ProjectFolderTool.terminal.bundleIdentifier, isNew: true)
        launch.discover(id: "restored", bundleIdentifier: ProjectFolderTool.editor.bundleIdentifier, isNew: false)
        for id in ["old", "terminal", "restored"] { launch.ready(id: id) }
        launch.succeeded = true
        XCTAssertTrue(launch.readyIds.isEmpty)
    }

    func testTerminalWaitsForLaunchResultAndMatchesExactWindowId() {
        var launch = ProjectFolderResolver.Launch(projectId: "p", tool: .terminal, existingIds: [])
        for id in ["unrelated", "new"] {
            launch.discover(id: id, bundleIdentifier: ProjectFolderTool.terminal.bundleIdentifier, isNew: true)
            launch.ready(id: id)
        }
        XCTAssertFalse(launch.matches(id: "new", windowId: 42))
        launch.succeeded = true
        XCTAssertFalse(launch.matches(id: "new", windowId: 42))
        launch.terminalWindowId = 42
        XCTAssertFalse(launch.matches(id: "unrelated", windowId: 41))
        XCTAssertTrue(launch.matches(id: "new", windowId: 42))
    }

    func testEditorWaitsForDiscoveryAndIdentityAfterSuccessfulLaunch() {
        var launch = ProjectFolderResolver.Launch(projectId: "p", tool: .editor, existingIds: [])
        launch.succeeded = true
        XCTAssertFalse(launch.matches(id: "new", windowId: 1))
        launch.discover(id: "new", bundleIdentifier: ProjectFolderTool.editor.bundleIdentifier, isNew: true)
        XCTAssertFalse(launch.matches(id: "new", windowId: 1))
        launch.ready(id: "new")
        launch.ready(id: "new")
        XCTAssertEqual(launch.readyIds, ["new"])
        XCTAssertTrue(launch.matches(id: "new", windowId: 1))
    }

    func testEditorWorkspacePreservesLiteralAbsoluteFolderPaths() throws {
        let folder = "/tmp/space ' quote \" $(touch INJECTED) `touch OTHER`\\project\n日本語"
        let data = try ProjectFolderResolver.editorWorkspaceData(folder: folder)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]])
        XCTAssertEqual(document, ["folders": [["path": folder]]])
    }

    func testEditorWorkspaceRequestsUseDistinctDurableDocumentsWithFriendlyNames() {
        let support = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)
        let firstId = UUID()
        let secondId = UUID()
        let first = ProjectFolderResolver.editorWorkspaceURL(applicationSupport: support, requestId: firstId, folder: "/tmp/My Project/")
        let second = ProjectFolderResolver.editorWorkspaceURL(applicationSupport: support, requestId: secondId, folder: "/tmp/My Project")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, ProjectFolderResolver.editorWorkspaceURL(applicationSupport: support, requestId: firstId, folder: "/tmp/My Project"))
        XCTAssertEqual(first.path, "/Users/test/Library/Application Support/AltTabProjects/ProjectWorkspaces/\(firstId.uuidString)/My Project.code-workspace")
        XCTAssertEqual(second.lastPathComponent, "My Project.code-workspace")
    }

    func testEditorWorkspaceRootFolderUsesFriendlyFilenameWithinRequestDirectory() {
        let support = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)
        let requestId = UUID()
        let workspace = ProjectFolderResolver.editorWorkspaceURL(applicationSupport: support, requestId: requestId, folder: "/")
        XCTAssertEqual(workspace.lastPathComponent, "Root.code-workspace")
        XCTAssertEqual(workspace.deletingLastPathComponent().lastPathComponent, requestId.uuidString)
    }

    func testTerminalCommandTreatsFolderAsLiteralShellData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("space ' quote \" $(touch INJECTED) `touch OTHER`\nproject")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = root.appendingPathComponent("test-shell")
        try "#!/bin/sh\n/bin/pwd\n".write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        let process = Process()
        let output = Pipe()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", ProjectFolderResolver.terminalCommand(folder: folder.path, shell: shell.path)]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let path = try XCTUnwrap(String(data: data, encoding: .utf8)).trimmingCharacters(in: .newlines)
        XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("INJECTED").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("OTHER").path))
    }
}
