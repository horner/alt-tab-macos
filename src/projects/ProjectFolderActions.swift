import Cocoa

/// Launch bookkeeping is main-thread-only; application lookup and child processes run on the launch queue.
enum ProjectFolderActions {
    private final class Request {
        let id = UUID()
        var launch: ProjectFolderResolver.Launch
        weak var parent: NSWindow?
        var timeout: DispatchWorkItem?

        init(project: Project, tool: ProjectFolderTool, parent: NSWindow?) {
            launch = .init(projectId: project.id, tool: tool, existingIds: Set(Windows.list.map { $0.tracked.id }))
            self.parent = parent
        }
    }

    private static let queue = DispatchQueue(label: "project-folder-launch", qos: .userInitiated, attributes: .concurrent)
    private static var requests = [ProjectFolderTool: Request]()
    private static var folderChooser: FolderChooser?

    static func chooseFolder(for project: Project, from window: NSWindow?, completion: @escaping () -> Void) {
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        if let folderChooser, folderChooser.project === project, folderChooser.isVisible {
            folderChooser.makeKeyAndOrderFront(nil)
            folderChooser.selectPath()
            return
        }
        folderChooser?.close()
        let chooser = FolderChooser(project: project, completion: completion)
        folderChooser = chooser
        chooser.present(from: window)
    }

    private final class FolderChooser: NSPanel, NSTextFieldDelegate {
        let project: Project
        private let completion: () -> Void
        private let field = NSTextField(frame: NSRect(x: 20, y: 116, width: 420, height: 24))
        private let detail = NSTextField(wrappingLabelWithString: "")
        private let use = NSButton(title: NSLocalizedString("Use Folder", comment: "Project folder action"), target: nil, action: nil)
        private var validationRevision = 0
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        init(project: Project, completion: @escaping () -> Void) {
            self.project = project
            self.completion = completion
            super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 184), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            title = "Choose a folder for \(project.resolvedName)"
            collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            isFloatingPanel = true
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            isExcludedFromWindowsMenu = true
            setAccessibilitySubrole(.floatingWindow)
            makeContent()
            field.stringValue = project.folderPath ?? ""
            field.delegate = self
            initialFirstResponder = field
            updateInput()
        }

        required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

        func present(from parent: NSWindow?) {
            if let parent, parent.isVisible {
                parent.beginSheet(self)
            } else {
                center()
                makeKeyAndOrderFront(nil)
            }
            selectPath()
        }

        func selectPath() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible, self.attachedSheet == nil else { return }
                self.field.selectText(nil)
            }
        }

        override func close() {
            validationRevision += 1
            if let attachedSheet { endSheet(attachedSheet, returnCode: .cancel) }
            if let sheetParent { sheetParent.endSheet(self) }
            super.close()
            // AppKit can re-enter while closing a window; defer releasing our last ownership.
            DispatchQueue.main.async { [weak self] in
                guard let self, ProjectFolderActions.folderChooser === self else { return }
                ProjectFolderActions.folderChooser = nil
            }
        }

        override func cancelOperation(_ sender: Any?) { close() }

        private func makeContent() {
            let label = NSTextField(labelWithString: NSLocalizedString("Folder path", comment: "Project folder path field"))
            label.frame = NSRect(x: 20, y: 146, width: 520, height: 20)
            field.maximumNumberOfLines = 1
            field.cell?.isScrollable = true
            field.placeholderString = "/Users/name/Projects/My Project"
            field.setAccessibilityLabel(NSLocalizedString("Folder path", comment: "Project folder path field"))
            let browse = NSButton(title: NSLocalizedString("Browse…", comment: "Browse for a Project folder"), target: self, action: #selector(browse))
            browse.bezelStyle = .rounded
            browse.frame = NSRect(x: 450, y: 112, width: 90, height: 32)
            detail.frame = NSRect(x: 20, y: 62, width: 520, height: 44)
            detail.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let cancel = NSButton(title: NSLocalizedString("Cancel", comment: ""), target: self, action: #selector(cancelOperation(_:)))
            for (index, button) in [cancel, use].enumerated() {
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 336 + index * 104, y: 16, width: 100, height: 32)
            }
            use.target = self
            use.action = #selector(save)
            use.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
            defaultButtonCell = use.cell as? NSButtonCell
            [label, field, browse, detail, cancel, use].forEach { contentView?.addSubview($0) }
        }

        func controlTextDidChange(_ notification: Notification) { updateInput() }

        private func updateInput() {
            validationRevision += 1
            use.isEnabled = !field.stringValue.isEmpty
            detail.textColor = .secondaryLabelColor
            detail.stringValue = NSLocalizedString("Paste a full folder path, or choose Browse…", comment: "Project folder path instructions")
        }

        @objc private func browse() {
            guard attachedSheet == nil else { return }
            updateInput()
            let panel = NSOpenPanel()
            panel.title = title
            panel.prompt = NSLocalizedString("Choose Folder", comment: "Project folder browser action")
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            if let path = project.folderPath { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
            panel.beginSheetModal(for: self) { [weak self] response in
                guard let self, self.isVisible, response == .OK, let url = panel.url,
                      Projects.isEnabled, Projects.byId[self.project.id] === self.project else { return }
                self.field.stringValue = url.path
                self.updateInput()
                self.selectPath()
            }
        }

        @objc private func save() {
            guard Projects.isEnabled, Projects.byId[project.id] === project else { close(); return }
            let value = field.stringValue
            validationRevision += 1
            let revision = validationRevision
            use.isEnabled = false
            detail.textColor = .secondaryLabelColor
            detail.stringValue = NSLocalizedString("Checking folder…", comment: "Project folder validation")
            ProjectFolderActions.queue.async { [weak self] in
                let path = ProjectFolderResolver.folderPath(value, homeDirectory: NSHomeDirectory()) { path in
                    var directory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isVisible, self.validationRevision == revision else { return }
                    self.complete(path)
                }
            }
        }

        private func complete(_ path: String?) {
            guard let path else {
                use.isEnabled = !field.stringValue.isEmpty
                detail.textColor = .systemRed
                detail.stringValue = NSLocalizedString("Enter the full path of an existing folder, or choose Browse…", comment: "Invalid Project folder path")
                return
            }
            let project = project
            let completion = completion
            close()
            DispatchQueue.main.async {
                guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
                project.folderPath = path
                completion()
            }
        }
    }

    static func open(_ tool: ProjectFolderTool, for project: Project, from window: NSWindow?, newWindow: Bool = false) {
        MainThreadStall.step()
        guard Projects.isEnabled, project.isCustom, Projects.byId[project.id] === project else { return }
        if !newWindow, let existing = reusable(tool, project: project) {
            Projects.active = project
            existing.focus()
            return
        }
        guard requests[tool] == nil else { return }
        guard let folder = project.folderPath else {
            chooseFolder(for: project, from: window) { open(tool, for: project, from: window, newWindow: newWindow) }
            return
        }
        let request = Request(project: project, tool: tool, parent: window)
        requests[tool] = request
        let timeout = DispatchWorkItem {
            finish(request, error: "\(tool.title) did not provide a new window. Check the application before trying again.")
        }
        request.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        queue.async {
            let result = launch(tool, folder: folder, newWindow: newWindow, requestId: request.id)
            DispatchQueue.main.async {
                guard requests[tool]?.id == request.id else { return }
                guard result.error == nil else { finish(request, error: result.error); return }
                request.launch.succeeded = true
                request.launch.terminalWindowId = result.windowId
                reconcile(request)
            }
        }
    }

    private static func reusable(_ tool: ProjectFolderTool, project: Project) -> Window? {
        let candidates = Windows.list.map {
            ProjectFolderResolver.WindowCandidate(id: $0.tracked.id, bundleIdentifier: $0.application.bundleIdentifier,
                focusOrder: $0.lastFocusOrder, eligible: !$0.isWindowlessApp && !$0.isPhantom && !$0.isTabbed)
        }
        guard let id = ProjectFolderResolver.reusable(candidates, members: project.members, tool: tool) else { return nil }
        return Windows.list.first { $0.tracked.id == id }
    }

    static func windowDiscovered(_ window: Window, isNew: Bool) {
        for request in requests.values {
            request.launch.discover(id: window.tracked.id, bundleIdentifier: window.application.bundleIdentifier, isNew: isNew)
        }
    }

    @discardableResult
    static func windowReady(_ window: Window) -> Bool {
        for request in Array(requests.values) {
            request.launch.ready(id: window.tracked.id)
            if request.launch.matches(id: window.tracked.id, windowId: window.cgWindowId), reconcile(request) { return true }
        }
        return false
    }

    @discardableResult
    private static func reconcile(_ request: Request) -> Bool {
        guard Projects.isEnabled, let project = Projects.byId[request.launch.projectId], project.isCustom else {
            finish(request, error: nil)
            return false
        }
        guard let window = Windows.list.first(where: {
            !$0.isWindowlessApp && !$0.isPhantom && request.launch.matches(id: $0.tracked.id, windowId: $0.cgWindowId)
        }) else { return false }
        finish(request, error: nil)
        Projects.assign([window.tracked.id], to: project, move: true)
        return true
    }

    private static func finish(_ request: Request, error: String?) {
        guard requests[request.launch.tool]?.id == request.id else { return }
        requests.removeValue(forKey: request.launch.tool)
        request.timeout?.cancel()
        request.timeout = nil
        guard let error else { return }
        let alert = NSAlert()
        alert.messageText = "Could not open \(request.launch.tool.title)"
        alert.informativeText = error
        ProjectPrompt.present(alert, from: request.parent) { _ in }
    }

    private static func loginShell() -> String {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16384)
        return buffer.withUnsafeMutableBufferPointer { bytes in
            guard getpwuid_r(getuid(), &entry, bytes.baseAddress!, bytes.count, &result) == 0,
                  result != nil, let shell = entry.pw_shell, shell.pointee != 0 else {
                return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            }
            return String(cString: shell)
        }
    }

    /// VS Code deduplicates folders even with --new-window, so explicit launches need a distinct workspace.
    private static func editorPath(folder: String, newWindow: Bool, requestId: UUID) throws -> String {
        guard newWindow else { return folder }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let workspace = ProjectFolderResolver.editorWorkspaceURL(applicationSupport: support, requestId: requestId, folder: folder)
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep the document after launch errors too: a late window or VS Code session restore may still use it.
        try ProjectFolderResolver.editorWorkspaceData(folder: folder).write(to: workspace, options: .atomic)
        return workspace.path
    }

    private static func launch(_ tool: ProjectFolderTool, folder: String, newWindow: Bool, requestId: UUID) -> (windowId: UInt32?, error: String?) {
        var directory: ObjCBool = false
        guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else {
            return (nil, "The project folder is unavailable: \(folder). Use Folder… to choose its new location.")
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleIdentifier) else {
            return (nil, "Install \(tool.title) to open this project folder.")
        }
        let process = Process()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            if tool == .terminal {
                process.launchPath = "/usr/bin/osascript"
                let shell = loginShell()
                process.arguments = ["-e", ProjectFolderResolver.terminalScript, ProjectFolderResolver.terminalCommand(folder: folder, shell: shell)]
            } else {
                process.launchPath = app.appendingPathComponent("Contents/Resources/app/bin/code").path
                process.arguments = ["--new-window", try editorPath(folder: folder, newWindow: newWindow, requestId: requestId)]
            }
            try process.run()
        }
        catch { return (nil, error.localizedDescription) }
        let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25, execute: stop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        let response = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            return (nil, response.isEmpty ? "The application did not complete the launch." : response)
        }
        if tool == .terminal, UInt32(response) == nil { return (nil, "iTerm2 did not return the new window's identity.") }
        return (UInt32(response), nil)
    }
}
