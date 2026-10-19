import Foundation

enum ProjectFolderTool: Int, CaseIterable {
    case terminal, editor

    var title: String { self == .terminal ? "iTerm2" : "VS Code" }
    var bundleIdentifier: String { self == .terminal ? "com.googlecode.iterm2" : "com.microsoft.VSCode" }
}

enum ProjectFolderResolver {
    struct WindowCandidate {
        let id: String
        let bundleIdentifier: String?
        let focusOrder: Int
        let eligible: Bool
    }

    static func reusable(_ windows: [WindowCandidate], members: Set<String>, tool: ProjectFolderTool) -> String? {
        windows.filter { $0.eligible && $0.bundleIdentifier == tool.bundleIdentifier && members.contains($0.id) }
            .min { $0.focusOrder < $1.focusOrder }?.id
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func terminalCommand(folder: String, shell: String) -> String {
        let command = "cd -- \(shellQuoted(folder)) && exec \(shellQuoted(shell)) -l"
        return "/bin/sh -c \(shellQuoted(command))"
    }

    static func editorWorkspaceURL(applicationSupport: URL, requestId: UUID, folder: String) -> URL {
        let folderName = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL.lastPathComponent
        let name = folderName.isEmpty || folderName == "/" ? "Root" : folderName
        return applicationSupport.appendingPathComponent("AltTabProjects/ProjectWorkspaces", isDirectory: true)
            .appendingPathComponent(requestId.uuidString, isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension("code-workspace")
    }

    static func editorWorkspaceData(folder: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["folders": [["path": folder]]], options: [.prettyPrinted, .sortedKeys])
    }

    // iTerm2's scripting dictionary defines window id as the integer accepted by screencapture -l.
    static let terminalScript = """
        on run argv
            tell application id "com.googlecode.iterm2"
                set projectWindow to (create window with default profile command (item 1 of argv))
                activate
                return id of projectWindow
            end tell
        end run
        """

    struct Launch {
        let projectId: String
        let tool: ProjectFolderTool
        let existingIds: Set<String>
        var discoveredIds = Set<String>()
        var readyIds = [String]()
        var succeeded = false
        var terminalWindowId: UInt32?

        mutating func discover(id: String, bundleIdentifier: String?, isNew: Bool) {
            guard isNew, bundleIdentifier == tool.bundleIdentifier, !existingIds.contains(id) else { return }
            discoveredIds.insert(id)
        }

        mutating func ready(id: String) {
            guard discoveredIds.contains(id), !readyIds.contains(id) else { return }
            readyIds.append(id)
        }

        func matches(id: String, windowId: UInt32?) -> Bool {
            guard succeeded, readyIds.contains(id) else { return false }
            if tool == .terminal { return terminalWindowId != nil && terminalWindowId == windowId }
            return readyIds.first == id
        }
    }
}
