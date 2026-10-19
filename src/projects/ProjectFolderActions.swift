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

    static func chooseFolder(for project: Project, from window: NSWindow?, completion: @escaping () -> Void) {
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for \(project.resolvedName)"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let path = project.folderPath { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        let selected: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, Projects.isEnabled, Projects.byId[project.id] === project else { return }
            project.folderPath = url.path
            DispatchQueue.main.async(execute: completion)
        }
        if let window, window.isVisible { panel.beginSheetModal(for: window, completionHandler: selected) }
        else { panel.begin(completionHandler: selected) }
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
            let result = launch(tool, folder: folder)
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

    private static func launch(_ tool: ProjectFolderTool, folder: String) -> (windowId: UInt32?, error: String?) {
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
        if tool == .terminal {
            process.launchPath = "/usr/bin/osascript"
            let shell = loginShell()
            process.arguments = ["-e", ProjectFolderResolver.terminalScript, ProjectFolderResolver.terminalCommand(folder: folder, shell: shell)]
        } else {
            process.launchPath = app.appendingPathComponent("Contents/Resources/app/bin/code").path
            process.arguments = ["--new-window", folder]
        }
        do { try process.run() }
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
