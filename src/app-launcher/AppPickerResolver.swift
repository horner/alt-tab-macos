import Foundation

enum AppCreationAction: Equatable {
    case open, chromeWindow, safariWindow, message

    var title: String {
        switch self {
        case .open: return NSLocalizedString("Open", comment: "App picker action")
        case .chromeWindow, .safariWindow: return NSLocalizedString("New Window", comment: "App picker action")
        case .message: return NSLocalizedString("New Message", comment: "App picker action")
        }
    }

    var aliases: [String] { self == .message ? ["sms", "text", "message", "messages"] : [] }
}

enum AppPickerResolver {
    static func action(bundleIdentifier: String?) -> AppCreationAction {
        switch bundleIdentifier {
        case "com.google.Chrome": return .chromeWindow
        case "com.apple.Safari": return .safariWindow
        case "com.apple.MobileSMS", "com.apple.iChat": return .message
        default: return .open
        }
    }

    static func isEntryKey(characters: String?, command: Bool, extraModifiers: Bool, hasConflict: Bool) -> Bool {
        characters?.lowercased() == "n" && command && !extraModifiers && !hasConflict
    }

    static func selection(previous: URL?, in results: [URL]) -> Int? {
        guard !results.isEmpty else { return nil }
        return previous.flatMap { results.firstIndex(of: $0) } ?? 0
    }

    static func isCreationMenu(_ action: AppCreationAction, identifier: String, title: String) -> Bool {
        switch action {
        case .chromeWindow:
            return identifier == "commandDispatch:" && title == "New Window"
        case .safariWindow:
            // Safari 26's profile menu uses New<profile>Window?isDefaultProfile=true.
            let parts = identifier.components(separatedBy: "?")
            return identifier == "NewWindow" || (parts.count == 2 && parts[0].hasPrefix("New")
                && parts[0].hasSuffix("Window") && parts[1] == "isDefaultProfile=true")
        case .message:
            return identifier == "new_message" || identifier == "newMessage:"
                || (identifier.isEmpty && title == "New Message")
        case .open:
            return false
        }
    }
}
